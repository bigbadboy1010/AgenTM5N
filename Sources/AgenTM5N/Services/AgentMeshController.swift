import Foundation
import SwiftUI

@MainActor
public final class AgentMeshController: ObservableObject {
  public static let shared = AgentMeshController()

  @Published public private(set) var node: AgentMeshNodeDescriptor?
  @Published public private(set) var peers: [AgentMeshPeerRecord] = []
  @Published public private(set) var listenerRunning = false
  @Published public private(set) var remoteTaskEvents: [AgentMeshTaskEvent] = []
  @Published public private(set) var remoteTaskSnapshot: AgentMeshTaskSnapshot?
  @Published public private(set) var remoteTaskResult = ""
  @Published public private(set) var statusMessage = "Agent Mesh bereit"

  @Published public var port: Int {
    didSet {
      let bounded = max(1, min(port, 65_535))
      if bounded != port {
        port = bounded
        return
      }
      UserDefaults.standard.set(port, forKey: Self.portKey)
    }
  }

  /// Compatibility alias for older Build-40 call sites.
  public var listenPort: Int {
    get { port }
    set { port = newValue }
  }

  @Published public var advertisedEndpoint: String {
    didSet {
      UserDefaults.standard.set(advertisedEndpoint, forKey: Self.endpointKey)
    }
  }
  @Published public var peerEndpoint = "http://"
  @Published public var taskPrompt = "Antworte kurz, dass der delegierte Agent-Mesh-Task angekommen ist."
  @Published public var autoStart: Bool {
    didSet {
      UserDefaults.standard.set(autoStart, forKey: Self.autoStartKey)
    }
  }

  private let identity: AgentMeshIdentityStore
  private let peerStore: AgentMeshPeerStore
  private let server: AgentMeshHTTPServer
  private let client: AgentMeshClient
  private var followTask: Task<Void, Never>?

  private static let portKey = "AgenTM5N.AgentMesh.port"
  private static let endpointKey = "AgenTM5N.AgentMesh.advertisedEndpoint"
  private static let autoStartKey = "AgenTM5N.AgentMesh.autoStart"

  public init(
    identity: AgentMeshIdentityStore = .shared,
    peerStore: AgentMeshPeerStore = .shared,
    server: AgentMeshHTTPServer = .shared,
    client: AgentMeshClient = AgentMeshClient()
  ) {
    self.identity = identity
    self.peerStore = peerStore
    self.server = server
    self.client = client

    let defaults = UserDefaults.standard
    let storedPort = defaults.integer(forKey: Self.portKey)
    port = storedPort == 0 ? Int(AgentMeshProtocol.defaultPort) : storedPort
    advertisedEndpoint = defaults.string(forKey: Self.endpointKey)
      ?? "http://127.0.0.1:\(AgentMeshProtocol.defaultPort)"
    autoStart = defaults.bool(forKey: Self.autoStartKey)

    Task { @MainActor [weak self] in
      await self?.refresh()
    }
  }

  deinit {
    followTask?.cancel()
  }

  public func bootstrap(configuration: AppConfiguration) async {
    await updateConfiguration(configuration)
    await refresh()
    if autoStart, !listenerRunning {
      do {
        try await start(configuration: configuration)
      } catch {
        statusMessage = error.localizedDescription
      }
    }
  }

  /// Compatibility entry point for callers that only need peer/listener state.
  public func bootstrap() async {
    await refresh()
  }

  public func updateConfiguration(_ configuration: AppConfiguration) async {
    await AgentMeshExecutionService.shared.configure(configuration)
  }

  public func start(configuration: AppConfiguration) async throws {
    await updateConfiguration(configuration)
    try await startListener()
  }

  public func startListener() async throws {
    guard let resolvedPort = UInt16(exactly: port) else {
      throw AgentMeshHTTPServerError.invalidPort
    }
    try await server.start(port: resolvedPort)
    listenerRunning = server.isRunning
    node = try identity.descriptor()
    statusMessage = "Agent Mesh lauscht auf Port \(port)."
  }

  public func stop() {
    stopListener()
  }

  public func stopListener() {
    server.stop()
    listenerRunning = false
    statusMessage = "Agent Mesh Listener gestoppt."
  }

  public func refresh() async {
    do {
      node = try identity.descriptor()
      peers = try await peerStore.all()
      listenerRunning = server.isRunning
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  @discardableResult
  public func enrollPeer(kind: AgentMeshPeerKind = .agentM5N) async throws -> AgentMeshPeerRecord {
    let endpoint = peerEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    _ = try await client.health(endpoint: endpoint)
    let peer = try await client.enroll(
      endpoint: endpoint,
      callbackEndpoint: advertisedEndpoint,
      expectedRemoteKind: kind
    )
    peers = try await peerStore.all()
    statusMessage = "Peer \(peer.name) wartet auf Trust-Freigabe. Fingerprint pruefen."
    return peer
  }

  public func trustReadOnly(_ peerID: UUID) async throws {
    let expectedFingerprint = try displayedPendingFingerprint(peerID)
    let capabilities: Set<AgentToolCapability> = [
      .workspace,
      .system,
      .memory,
      .knowledge,
      .attachments,
    ]
    _ = try await peerStore.trust(
      id: peerID,
      expectedFingerprint: expectedFingerprint,
      allowedCapabilities: capabilities
    )
    peers = try await peerStore.all()
    statusMessage = "Peer vertraut: Workspace/Knowledge Read Scope aktiv. Persoenliche macOS-Daten sind nicht enthalten."
  }

  public func trustDevOps(_ peerID: UUID) async throws {
    let expectedFingerprint = try displayedPendingFingerprint(peerID)
    let capabilities: Set<AgentToolCapability> = [
      .workspace,
      .terminal,
      .git,
      .system,
      .memory,
      .knowledge,
    ]
    _ = try await peerStore.trust(
      id: peerID,
      expectedFingerprint: expectedFingerprint,
      allowedCapabilities: capabilities
    )
    peers = try await peerStore.all()
    statusMessage = "Peer vertraut: DevOps Scope aktiv; Write/Execute bleibt lokal bestaetigungspflichtig. Persoenliche macOS-Daten sind ausgeschlossen."
  }

  public func revoke(_ peerID: UUID) async throws {
    _ = try await peerStore.revoke(id: peerID)
    await AgentMeshTaskCoordinator.shared.cancelAll(peerID: peerID)
    peers = try await peerStore.all()
    statusMessage = "Peer wurde widerrufen und laufende Tasks wurden abgebrochen."
  }

  public func submitTask(to peerID: UUID) async throws {
    guard let peer = peers.first(where: { $0.id == peerID }), peer.status == .trusted else {
      throw AgentMeshSecurityError.peerNotTrusted
    }

    followTask?.cancel()
    remoteTaskEvents = []
    remoteTaskSnapshot = nil
    remoteTaskResult = ""

    let request = AgentMeshTaskRequest(
      prompt: taskPrompt,
      requestedCapabilities: peer.allowedCapabilities
    )
    let snapshot = try await client.submit(request, to: peer)
    remoteTaskSnapshot = snapshot
    statusMessage = "Remote Task \(snapshot.id.uuidString.prefix(8)) gestartet."

    followTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        for try await event in client.follow(taskID: request.id, peer: peer) {
          if Task.isCancelled { return }
          remoteTaskEvents.append(event)
        }

        let terminal = try await client.snapshot(taskID: request.id, peer: peer)
        remoteTaskSnapshot = terminal
        remoteTaskResult = terminal.result ?? terminal.error ?? ""
        statusMessage = "Remote Task: \(terminal.status.rawValue)"
      } catch is CancellationError {
        return
      } catch {
        statusMessage = error.localizedDescription
      }
    }
  }

  private func displayedPendingFingerprint(_ peerID: UUID) throws -> String {
    guard let displayed = peers.first(where: { $0.id == peerID }),
      displayed.status == .pending
    else {
      throw AgentMeshSecurityError.peerNotTrusted
    }
    return displayed.fingerprint
  }
}
