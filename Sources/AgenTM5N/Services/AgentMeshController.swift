import Foundation

@MainActor
public final class AgentMeshController: ObservableObject {
  public static let shared = AgentMeshController()

  @Published public private(set) var node: AgentMeshNodeDescriptor?
  @Published public private(set) var peers: [AgentMeshPeerRecord] = []
  @Published public private(set) var listenerRunning = false
  @Published public private(set) var statusMessage = "Agent Mesh gestoppt"
  @Published public private(set) var remoteTaskEvents: [AgentMeshTaskEvent] = []
  @Published public private(set) var remoteTaskSnapshot: AgentMeshTaskSnapshot?
  @Published public var port: Int
  @Published public var advertisedEndpoint: String
  @Published public var peerEndpoint = ""
  @Published public var taskPrompt = "Antworte in einem Satz: Welcher Node bearbeitet diesen delegierten Task?"

  private let identity: AgentMeshIdentityStore
  private let peerStore: AgentMeshPeerStore
  private let server: AgentMeshHTTPServer
  private let client: AgentMeshClient
  private let defaults: UserDefaults
  private var followTask: Task<Void, Never>?
  private var activeConfiguration: AppConfiguration?

  private enum Key {
    static let port = "agentMesh.port"
    static let advertisedEndpoint = "agentMesh.advertisedEndpoint"
    static let autoStart = "agentMesh.autoStart"
  }

  public init(
    identity: AgentMeshIdentityStore = .shared,
    peerStore: AgentMeshPeerStore = .shared,
    server: AgentMeshHTTPServer = .shared,
    client: AgentMeshClient = AgentMeshClient(),
    defaults: UserDefaults = .standard
  ) {
    self.identity = identity
    self.peerStore = peerStore
    self.server = server
    self.client = client
    self.defaults = defaults
    let savedPort = defaults.integer(forKey: Key.port)
    port = savedPort > 0 ? savedPort : Int(AgentMeshProtocol.defaultPort)
    advertisedEndpoint = defaults.string(forKey: Key.advertisedEndpoint)
      ?? "http://127.0.0.1:\(AgentMeshProtocol.defaultPort)"
  }

  public func bootstrap(configuration: AppConfiguration) async {
    activeConfiguration = configuration
    await AgentMeshExecutionService.shared.configure(configuration)
    do {
      node = try identity.descriptor()
      peers = try await peerStore.all()
      if defaults.bool(forKey: Key.autoStart) {
        try await start(configuration: configuration)
      }
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  public func updateConfiguration(_ configuration: AppConfiguration) async {
    activeConfiguration = configuration
    await AgentMeshExecutionService.shared.configure(configuration)
  }

  public func start(configuration: AppConfiguration) async throws {
    activeConfiguration = configuration
    await AgentMeshExecutionService.shared.configure(configuration)
    let boundedPort = max(1, min(port, 65_535))
    port = boundedPort
    defaults.set(boundedPort, forKey: Key.port)
    defaults.set(advertisedEndpoint, forKey: Key.advertisedEndpoint)
    guard let portValue = UInt16(exactly: boundedPort) else {
      throw AgentMeshHTTPServerError.invalidPort
    }
    try await server.start(port: portValue)
    listenerRunning = true
    defaults.set(true, forKey: Key.autoStart)
    node = try identity.descriptor()
    peers = try await peerStore.all()
    statusMessage = "Agent Mesh aktiv auf Port \(boundedPort)"
  }

  public func stop() {
    server.stop()
    listenerRunning = false
    defaults.set(false, forKey: Key.autoStart)
    statusMessage = "Agent Mesh gestoppt"
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
      kind: kind
    )
    peers = try await peerStore.all()
    statusMessage = "Peer \(peer.name) wartet auf Trust-Freigabe. Fingerprint pruefen."
    return peer
  }

  public func trustReadOnly(_ peerID: UUID) async throws {
    let capabilities: Set<AgentToolCapability> = [
      .workspace,
      .macPersonal,
      .reminders,
      .system,
      .memory,
      .knowledge,
      .attachments,
    ]
    _ = try await peerStore.trust(id: peerID, allowedCapabilities: capabilities)
    peers = try await peerStore.all()
    statusMessage = "Peer vertraut: Read-or-approved-mutation Scope aktiv."
  }

  public func trustDevOps(_ peerID: UUID) async throws {
    let capabilities: Set<AgentToolCapability> = [
      .workspace,
      .terminal,
      .git,
      .system,
      .macPersonal,
      .reminders,
      .memory,
      .knowledge,
    ]
    _ = try await peerStore.trust(id: peerID, allowedCapabilities: capabilities)
    peers = try await peerStore.all()
    statusMessage = "Peer vertraut: DevOps Scope aktiv; Write/Execute bleibt lokal bestaetigungspflichtig."
  }

  public func revoke(_ peerID: UUID) async throws {
    _ = try await peerStore.revoke(id: peerID)
    peers = try await peerStore.all()
    statusMessage = "Peer wurde widerrufen."
  }

  public func submitTask(to peerID: UUID) async throws {
    guard let peer = peers.first(where: { $0.id == peerID }), peer.status == .trusted else {
      throw AgentMeshSecurityError.peerNotTrusted
    }
    followTask?.cancel()
    remoteTaskEvents = []
    let request = AgentMeshTaskRequest(
      prompt: taskPrompt,
      requestedCapabilities: peer.allowedCapabilities
    )
    let snapshot = try await client.submit(request, to: peer)
    remoteTaskSnapshot = snapshot
    statusMessage = "Task \(snapshot.id.uuidString.prefix(8)) an \(peer.name) delegiert."

    followTask = Task { [weak self] in
      guard let self else { return }
      do {
        for try await event in client.follow(taskID: snapshot.id, peer: peer) {
          if Task.isCancelled { return }
          remoteTaskEvents.append(event)
        }
        if !Task.isCancelled {
          remoteTaskSnapshot = try await client.snapshot(taskID: snapshot.id, peer: peer)
        }
      } catch {
        if !Task.isCancelled {
          statusMessage = error.localizedDescription
        }
      }
    }
  }

  public func cancelRemoteTask(peerID: UUID) async throws {
    guard let peer = peers.first(where: { $0.id == peerID }),
      let snapshot = remoteTaskSnapshot
    else { return }
    followTask?.cancel()
    remoteTaskSnapshot = try await client.cancel(taskID: snapshot.id, peer: peer)
  }
}
