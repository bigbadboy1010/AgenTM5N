import Foundation
import Network

public enum AgentMeshHTTPServerError: LocalizedError {
  case invalidPort
  case malformedRequest
  case requestTooLarge
  case listenerFailed(String)

  public var errorDescription: String? {
    switch self {
    case .invalidPort: "Ungueltiger Agent-Mesh-Port."
    case .malformedRequest: "Ungueltiger Agent-Mesh-HTTP-Request."
    case .requestTooLarge: "Agent-Mesh-Request ist zu gross."
    case .listenerFailed(let detail): "Agent-Mesh-Listener konnte nicht gestartet werden: \(detail)"
    }
  }
}

private struct AgentMeshHTTPRequest: Sendable {
  let method: String
  let target: String
  let path: String
  let query: [String: String]
  let headers: [String: String]
  let body: Data
}

private struct AgentMeshHTTPResponse: Sendable {
  let status: Int
  let reason: String
  let headers: [String: String]
  let body: Data

  init(
    status: Int,
    reason: String,
    headers: [String: String] = [:],
    body: Data = Data()
  ) {
    self.status = status
    self.reason = reason
    self.headers = headers
    self.body = body
  }

  func encoded() -> Data {
    var merged = headers
    merged["Content-Length"] = String(body.count)
    merged["Connection"] = "close"
    if merged["Content-Type"] == nil {
      merged["Content-Type"] = "application/json; charset=utf-8"
    }
    let headerText = merged
      .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
      .map { "\($0.key): \($0.value)" }
      .joined(separator: "\r\n")
    var data = Data("HTTP/1.1 \(status) \(reason)\r\n\(headerText)\r\n\r\n".utf8)
    data.append(body)
    return data
  }
}

private final class AgentMeshHTTPReceiveState: @unchecked Sendable {
  private let lock = NSLock()
  private var data = Data()
  private var finished = false

  func append(_ chunk: Data) throws -> AgentMeshHTTPRequest? {
    lock.lock()
    defer { lock.unlock() }
    guard !finished else { return nil }
    data.append(chunk)
    guard data.count <= AgentMeshProtocol.maximumRequestBytes else {
      finished = true
      throw AgentMeshHTTPServerError.requestTooLarge
    }
    if let request = try AgentMeshHTTPParser.parseIfComplete(data) {
      finished = true
      return request
    }
    return nil
  }

  func markFinished() { lock.withLock { finished = true } }
}

private enum AgentMeshHTTPParser {
  static func parseIfComplete(_ data: Data) throws -> AgentMeshHTTPRequest? {
    let separator = Data("\r\n\r\n".utf8)
    guard let headerRange = data.range(of: separator) else { return nil }
    let headerData = data[..<headerRange.lowerBound]
    guard let headerText = String(data: headerData, encoding: .utf8) else {
      throw AgentMeshHTTPServerError.malformedRequest
    }
    let lines = headerText.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else { throw AgentMeshHTTPServerError.malformedRequest }
    let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
    guard parts.count == 3, parts[2].hasPrefix("HTTP/") else {
      throw AgentMeshHTTPServerError.malformedRequest
    }
    let method = String(parts[0]).uppercased()
    let target = String(parts[1])

    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { continue }
      let name = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
      headers[name] = value
    }
    let contentLength = Int(headers["content-length"] ?? "0") ?? 0
    guard contentLength >= 0, contentLength <= AgentMeshProtocol.maximumRequestBytes else {
      throw AgentMeshHTTPServerError.requestTooLarge
    }
    let bodyStart = headerRange.upperBound
    let available = data.distance(from: bodyStart, to: data.endIndex)
    guard available >= contentLength else { return nil }
    let bodyEnd = data.index(bodyStart, offsetBy: contentLength)
    let body = Data(data[bodyStart..<bodyEnd])

    guard let components = URLComponents(string: "http://mesh.invalid\(target)") else {
      throw AgentMeshHTTPServerError.malformedRequest
    }
    let query = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
      }
    )
    return AgentMeshHTTPRequest(
      method: method,
      target: target,
      path: components.path,
      query: query,
      headers: headers,
      body: body
    )
  }
}

public actor AgentMeshRateLimiter {
  public static let shared = AgentMeshRateLimiter()
  private var requests: [UUID: [Date]] = [:]
  private var taskSubmissions: [UUID: [Date]] = [:]

  public init() {}

  public func allow(peerID: UUID, isTaskSubmission: Bool, now: Date = Date()) -> Bool {
    let minuteAgo = now.addingTimeInterval(-60)
    var peerRequests = (requests[peerID] ?? []).filter { $0 >= minuteAgo }
    guard peerRequests.count < 180 else { return false }
    peerRequests.append(now)
    requests[peerID] = peerRequests

    if isTaskSubmission {
      var submissions = (taskSubmissions[peerID] ?? []).filter { $0 >= minuteAgo }
      guard submissions.count < 12 else { return false }
      submissions.append(now)
      taskSubmissions[peerID] = submissions
    }
    return true
  }
}

public final class AgentMeshHTTPServer: @unchecked Sendable {
  public static let shared = AgentMeshHTTPServer()

  private let lock = NSLock()
  private let queue = DispatchQueue(label: "team.cloudforge.AgenTM5N.agent-mesh.http", qos: .utility)
  private let identity: AgentMeshIdentityStore
  private let peerStore: AgentMeshPeerStore
  private let replayProtector: AgentMeshReplayProtector
  private let rateLimiter: AgentMeshRateLimiter
  private let coordinator: AgentMeshTaskCoordinator
  private var listener: NWListener?
  private var configuredPort: UInt16?

  public init(
    identity: AgentMeshIdentityStore = .shared,
    peerStore: AgentMeshPeerStore = .shared,
    replayProtector: AgentMeshReplayProtector = .shared,
    rateLimiter: AgentMeshRateLimiter = .shared,
    coordinator: AgentMeshTaskCoordinator = .shared
  ) {
    self.identity = identity
    self.peerStore = peerStore
    self.replayProtector = replayProtector
    self.rateLimiter = rateLimiter
    self.coordinator = coordinator
  }

  public func start(port: UInt16 = AgentMeshProtocol.defaultPort) async throws {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
      throw AgentMeshHTTPServerError.invalidPort
    }
    if isRunning { return }

    let listener = try NWListener(using: .tcp, on: nwPort)
    listener.newConnectionHandler = { [weak self] connection in
      guard let self else { return }
      connection.start(queue: self.queue)
      self.receive(connection)
    }
    listener.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      if case .failed = state {
        self.stop()
      }
    }
    lock.withLock {
      self.listener = listener
      configuredPort = port
    }
    listener.start(queue: queue)
  }

  public func stop() {
    let current = lock.withLock { () -> NWListener? in
      let value = listener
      listener = nil
      configuredPort = nil
      return value
    }
    current?.cancel()
  }

  public var isRunning: Bool {
    lock.withLock { listener != nil }
  }

  public var port: UInt16? {
    lock.withLock { configuredPort }
  }

  private func receive(_ connection: NWConnection) {
    let state = AgentMeshHTTPReceiveState()
    receiveNext(connection, state: state)
  }

  private func receiveNext(
    _ connection: NWConnection,
    state: AgentMeshHTTPReceiveState
  ) {
    connection.receive(
      minimumIncompleteLength: 1,
      maximumLength: 64 * 1_024
    ) { [weak self] data, _, isComplete, error in
      guard let self else { connection.cancel(); return }
      if let error {
        self.send(
          AgentMeshHTTPResponse(status: 400, reason: "Bad Request", body: Self.errorBody(error)),
          on: connection
        )
        return
      }
      do {
        if let data, !data.isEmpty, let request = try state.append(data) {
          Task {
            let response = await self.route(request)
            self.send(response, on: connection)
          }
          return
        }
        if isComplete {
          state.markFinished()
          self.send(
            AgentMeshHTTPResponse(status: 400, reason: "Bad Request", body: Self.errorBody(AgentMeshHTTPServerError.malformedRequest)),
            on: connection
          )
          return
        }
        self.receiveNext(connection, state: state)
      } catch {
        self.send(
          AgentMeshHTTPResponse(status: 413, reason: "Payload Too Large", body: Self.errorBody(error)),
          on: connection
        )
      }
    }
  }

  private func send(_ response: AgentMeshHTTPResponse, on connection: NWConnection) {
    connection.send(content: response.encoded(), completion: .contentProcessed { _ in
      connection.cancel()
    })
  }

  private func route(_ request: AgentMeshHTTPRequest) async -> AgentMeshHTTPResponse {
    do {
      if request.method == "GET", request.path == "/v1/health" {
        let value = AgentMeshHealthResponse(nodeID: try identity.nodeID())
        return try jsonResponse(status: 200, reason: "OK", value: value)
      }

      if request.method == "GET", request.path == "/v1/openapi.json" {
        return AgentMeshHTTPResponse(
          status: 200,
          reason: "OK",
          headers: ["Content-Type": "application/json; charset=utf-8"],
          body: Data(Self.openAPIDocument.utf8)
        )
      }

      if request.method == "POST", request.path == "/v1/peers/enroll" {
        return try await handleEnrollment(request)
      }

      let peer = try await authenticate(request)
      let isSubmission = request.method == "POST" && request.path == "/v1/tasks"
      guard await rateLimiter.allow(peerID: peer.id, isTaskSubmission: isSubmission) else {
        return AgentMeshHTTPResponse(status: 429, reason: "Too Many Requests", body: Self.genericError("rate_limited"))
      }

      if request.method == "GET", request.path == "/v1/node" {
        let descriptor = try identity.descriptor()
        return try sealedResponse(request: request, peer: peer, status: 200, reason: "OK", value: descriptor)
      }

      if request.method == "GET", request.path == "/v1/capabilities" {
        let descriptor = try identity.descriptor()
        return try sealedResponse(
          request: request,
          peer: peer,
          status: 200,
          reason: "OK",
          value: AgentMeshCapabilityResponse(
            capabilities: descriptor.capabilities,
            features: descriptor.features
          )
        )
      }

      if request.method == "GET", request.path == "/v1/peers" {
        let peers = try await peerStore.all().filter { $0.status == .trusted }.map(AgentMeshPeerSummary.init)
        return try sealedResponse(request: request, peer: peer, status: 200, reason: "OK", value: peers)
      }

      if request.method == "POST", request.path == "/v1/tasks" {
        let task: AgentMeshTaskRequest = try openRequestBody(request, from: peer)
        let snapshot = try await coordinator.submit(task, from: peer)
        return try sealedResponse(request: request, peer: peer, status: 202, reason: "Accepted", value: snapshot)
      }

      let components = request.path.split(separator: "/").map(String.init)
      if components.count >= 3,
        components[0] == "v1",
        components[1] == "tasks",
        let taskID = UUID(uuidString: components[2])
      {
        if components.count == 3, request.method == "GET" {
          let snapshot = try await coordinator.snapshot(taskID: taskID, peerID: peer.id)
          return try sealedResponse(request: request, peer: peer, status: 200, reason: "OK", value: snapshot)
        }
        if components.count == 4, components[3] == "cancel", request.method == "POST" {
          let snapshot = try await coordinator.cancel(taskID: taskID, peerID: peer.id)
          return try sealedResponse(request: request, peer: peer, status: 200, reason: "OK", value: snapshot)
        }
        if components.count == 4, components[3] == "events", request.method == "GET" {
          let after = Int(request.query["after"] ?? "0") ?? 0
          let batch = try await coordinator.eventBatch(
            taskID: taskID,
            peerID: peer.id,
            afterEventID: max(0, after)
          )
          return try sealedResponse(request: request, peer: peer, status: 200, reason: "OK", value: batch)
        }
      }

      return AgentMeshHTTPResponse(status: 404, reason: "Not Found", body: Self.genericError("not_found"))
    } catch AgentMeshSecurityError.peerNotTrusted {
      return AgentMeshHTTPResponse(status: 403, reason: "Forbidden", body: Self.genericError("peer_not_trusted"))
    } catch AgentMeshSecurityError.replayDetected {
      return AgentMeshHTTPResponse(status: 409, reason: "Conflict", body: Self.genericError("replay_blocked"))
    } catch AgentMeshSecurityError.expiredRequest {
      return AgentMeshHTTPResponse(status: 401, reason: "Unauthorized", body: Self.genericError("request_expired"))
    } catch AgentMeshTaskCoordinatorError.busy {
      return AgentMeshHTTPResponse(status: 503, reason: "Service Unavailable", body: Self.genericError("node_busy"))
    } catch AgentMeshTaskCoordinatorError.taskNotFound {
      return AgentMeshHTTPResponse(status: 404, reason: "Not Found", body: Self.genericError("task_not_found"))
    } catch {
      return AgentMeshHTTPResponse(status: 400, reason: "Bad Request", body: Self.genericError("invalid_request"))
    }
  }

  private func handleEnrollment(_ request: AgentMeshHTTPRequest) async throws -> AgentMeshHTTPResponse {
    guard request.body.count <= 128 * 1_024 else { throw AgentMeshHTTPServerError.requestTooLarge }
    let enrollment = try Self.decoder.decode(AgentMeshEnrollmentRequest.self, from: request.body)
    let localNodeID = try identity.nodeID()
    guard enrollment.node.nodeID != localNodeID else {
      throw AgentMeshHTTPServerError.malformedRequest
    }
    let peer = try await peerStore.registerPending(
      descriptor: enrollment.node,
      endpoint: enrollment.callbackEndpoint
    )
    let local = try identity.descriptor()
    return try jsonResponse(
      status: 202,
      reason: "Accepted",
      value: AgentMeshEnrollmentResponse(node: local, status: peer.status)
    )
  }

  private func authenticate(_ request: AgentMeshHTTPRequest) async throws -> AgentMeshPeerRecord {
    guard let versionText = request.headers["x-agentm5n-protocol"],
      let version = Int(versionText),
      version == AgentMeshProtocol.version
    else {
      throw AgentMeshSecurityError.protocolMismatch(Int(request.headers["x-agentm5n-protocol"] ?? "") ?? -1)
    }
    guard let nodeText = request.headers["x-agentm5n-node"],
      let nodeID = UUID(uuidString: nodeText),
      let timestampText = request.headers["x-agentm5n-timestamp"],
      let timestamp = Int64(timestampText),
      let nonce = request.headers["x-agentm5n-nonce"],
      !nonce.isEmpty,
      let signatureText = request.headers["x-agentm5n-signature"],
      let signature = Data(base64Encoded: signatureText),
      let peer = try await peerStore.trustedPeer(id: nodeID)
    else {
      throw AgentMeshSecurityError.peerNotTrusted
    }

    let authentication = AgentMeshRequestAuthentication(
      nodeID: nodeID,
      timestampMilliseconds: timestamp,
      nonce: nonce,
      signature: signature
    )
    try AgentMeshIdentityStore.verify(
      authentication: authentication,
      method: request.method,
      path: request.target,
      body: request.body,
      peer: peer
    )
    try await replayProtector.validate(
      nodeID: nodeID,
      nonce: nonce,
      timestampMilliseconds: timestamp
    )
    try await peerStore.markSeen(id: nodeID)
    return peer
  }

  private func openRequestBody<T: Decodable & Sendable>(
    _ request: AgentMeshHTTPRequest,
    from peer: AgentMeshPeerRecord
  ) throws -> T {
    let message = try Self.decoder.decode(AgentMeshSealedMessage.self, from: request.body)
    return try identity.open(message, from: peer, as: T.self)
  }

  private func sealedResponse<T: Encodable & Sendable>(
    request: AgentMeshHTTPRequest,
    peer: AgentMeshPeerRecord,
    status: Int,
    reason: String,
    value: T
  ) throws -> AgentMeshHTTPResponse {
    let sealed = try identity.seal(value, for: peer)
    let body = try Self.encoder.encode(sealed)
    let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
    let nonce = UUID().uuidString.lowercased()
    let signature = try identity.sign(
      method: "RESPONSE-\(status)",
      path: request.target,
      timestampMilliseconds: timestamp,
      nonce: nonce,
      body: body
    )
    return AgentMeshHTTPResponse(
      status: status,
      reason: reason,
      headers: [
        "Content-Type": "application/vnd.agentm5n.mesh+json",
        "X-AgenTM5N-Protocol": String(AgentMeshProtocol.version),
        "X-AgenTM5N-Node": try identity.nodeID().uuidString.lowercased(),
        "X-AgenTM5N-Timestamp": String(timestamp),
        "X-AgenTM5N-Nonce": nonce,
        "X-AgenTM5N-Signature": signature.base64EncodedString(),
      ],
      body: body
    )
  }

  private func jsonResponse<T: Encodable>(
    status: Int,
    reason: String,
    value: T
  ) throws -> AgentMeshHTTPResponse {
    AgentMeshHTTPResponse(
      status: status,
      reason: reason,
      headers: ["Content-Type": "application/json; charset=utf-8"],
      body: try Self.encoder.encode(value)
    )
  }

  private static let encoder: JSONEncoder = {
    let value = JSONEncoder()
    value.dateEncodingStrategy = .iso8601
    value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return value
  }()

  private static let decoder: JSONDecoder = {
    let value = JSONDecoder()
    value.dateDecodingStrategy = .iso8601
    return value
  }()

  private static func genericError(_ code: String) -> Data {
    (try? JSONSerialization.data(withJSONObject: ["error": code], options: [.sortedKeys])) ?? Data()
  }

  private static func errorBody(_ error: Error) -> Data {
    genericError("transport_error")
  }

  public static let openAPIDocument = """
  {
    "openapi":"3.1.0",
    "info":{"title":"AgenTM5N Agent Mesh API","version":"1.0"},
    "paths":{
      "/v1/health":{"get":{}},
      "/v1/node":{"get":{}},
      "/v1/capabilities":{"get":{}},
      "/v1/peers/enroll":{"post":{}},
      "/v1/peers":{"get":{}},
      "/v1/tasks":{"post":{}},
      "/v1/tasks/{id}":{"get":{}},
      "/v1/tasks/{id}/cancel":{"post":{}},
      "/v1/tasks/{id}/events":{"get":{}}
    }
  }
  """
}

private extension NSLock {
  func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
