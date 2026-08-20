import CryptoKit
import Foundation

public enum AgentMeshClientError: LocalizedError {
  case invalidEndpoint
  case invalidResponse
  case http(Int, String)
  case remoteIdentityChanged

  public var errorDescription: String? {
    switch self {
    case .invalidEndpoint: "Ungueltiger Agent-Mesh-Peer-Endpunkt."
    case .invalidResponse: "Ungueltige Agent-Mesh-Antwort."
    case .http(let status, let code): "Agent Mesh HTTP \(status): \(code)"
    case .remoteIdentityChanged: "Die kryptografische Identitaet des Remote-Peers hat sich geaendert."
    }
  }
}

public final class AgentMeshClient: @unchecked Sendable {
  private let session: URLSession
  private let identity: AgentMeshIdentityStore
  private let peerStore: AgentMeshPeerStore
  private let replayProtector: AgentMeshReplayProtector

  public init(
    session: URLSession = .shared,
    identity: AgentMeshIdentityStore = .shared,
    peerStore: AgentMeshPeerStore = .shared,
    replayProtector: AgentMeshReplayProtector = .shared
  ) {
    self.session = session
    self.identity = identity
    self.peerStore = peerStore
    self.replayProtector = replayProtector
  }

  public func health(endpoint: String) async throws -> AgentMeshHealthResponse {
    let url = try endpointURL(endpoint, path: "/v1/health")
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 10
    let (data, response) = try await session.data(for: request)
    try validateBasic(response, data: data)
    return try Self.decoder.decode(AgentMeshHealthResponse.self, from: data)
  }

  @discardableResult
  public func enroll(
    endpoint: String,
    callbackEndpoint: String,
    kind: AgentMeshPeerKind = .agentM5N
  ) async throws -> AgentMeshPeerRecord {
    let local = try identity.descriptor(kind: kind)
    let payload = AgentMeshEnrollmentRequest(
      node: local,
      callbackEndpoint: callbackEndpoint
    )
    let body = try Self.encoder.encode(payload)
    let url = try endpointURL(endpoint, path: "/v1/peers/enroll")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    let (data, response) = try await session.data(for: request)
    try validateBasic(response, data: data, acceptedStatuses: 200...299)
    let enrollment = try Self.decoder.decode(AgentMeshEnrollmentResponse.self, from: data)
    guard enrollment.node.protocolVersion == AgentMeshProtocol.version else {
      throw AgentMeshSecurityError.protocolMismatch(enrollment.node.protocolVersion)
    }

    if let existing = try await peerStore.peer(id: enrollment.node.nodeID),
      existing.status == .trusted,
      (existing.signingPublicKey != enrollment.node.signingPublicKey
        || existing.agreementPublicKey != enrollment.node.agreementPublicKey)
    {
      throw AgentMeshClientError.remoteIdentityChanged
    }

    return try await peerStore.registerPending(
      descriptor: enrollment.node,
      endpoint: endpoint
    )
  }

  public func node(peer: AgentMeshPeerRecord) async throws -> AgentMeshNodeDescriptor {
    try await authenticatedGET(peer: peer, path: "/v1/node", as: AgentMeshNodeDescriptor.self)
  }

  public func capabilities(peer: AgentMeshPeerRecord) async throws -> AgentMeshCapabilityResponse {
    try await authenticatedGET(peer: peer, path: "/v1/capabilities", as: AgentMeshCapabilityResponse.self)
  }

  public func remotePeers(peer: AgentMeshPeerRecord) async throws -> [AgentMeshPeerSummary] {
    try await authenticatedGET(peer: peer, path: "/v1/peers", as: [AgentMeshPeerSummary].self)
  }

  public func submit(
    _ task: AgentMeshTaskRequest,
    to peer: AgentMeshPeerRecord
  ) async throws -> AgentMeshTaskSnapshot {
    try await authenticatedRequest(
      peer: peer,
      method: "POST",
      path: "/v1/tasks",
      payload: task,
      responseType: AgentMeshTaskSnapshot.self
    )
  }

  public func snapshot(
    taskID: UUID,
    peer: AgentMeshPeerRecord
  ) async throws -> AgentMeshTaskSnapshot {
    try await authenticatedGET(
      peer: peer,
      path: "/v1/tasks/\(taskID.uuidString.lowercased())",
      as: AgentMeshTaskSnapshot.self
    )
  }

  public func events(
    taskID: UUID,
    peer: AgentMeshPeerRecord,
    afterEventID: Int
  ) async throws -> AgentMeshTaskEventBatch {
    try await authenticatedGET(
      peer: peer,
      path: "/v1/tasks/\(taskID.uuidString.lowercased())/events?after=\(max(0, afterEventID))",
      as: AgentMeshTaskEventBatch.self
    )
  }

  public func cancel(
    taskID: UUID,
    peer: AgentMeshPeerRecord
  ) async throws -> AgentMeshTaskSnapshot {
    try await authenticatedRequest(
      peer: peer,
      method: "POST",
      path: "/v1/tasks/\(taskID.uuidString.lowercased())/cancel",
      payload: AgentMeshEmptyPayload(),
      responseType: AgentMeshTaskSnapshot.self
    )
  }

  public func follow(
    taskID: UUID,
    peer: AgentMeshPeerRecord
  ) -> AsyncThrowingStream<AgentMeshTaskEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        var lastEventID = 0
        do {
          while !Task.isCancelled {
            let batch = try await self.events(
              taskID: taskID,
              peer: peer,
              afterEventID: lastEventID
            )
            for event in batch.events {
              continuation.yield(event)
              lastEventID = max(lastEventID, event.id)
            }
            if batch.terminal {
              continuation.finish()
              return
            }
            try await Task.sleep(for: .milliseconds(350))
          }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func authenticatedGET<T: Decodable & Sendable>(
    peer: AgentMeshPeerRecord,
    path: String,
    as type: T.Type
  ) async throws -> T {
    try await authenticatedRequest(
      peer: peer,
      method: "GET",
      path: path,
      rawBody: Data(),
      responseType: type
    )
  }

  private func authenticatedRequest<Payload: Encodable & Sendable, Response: Decodable & Sendable>(
    peer: AgentMeshPeerRecord,
    method: String,
    path: String,
    payload: Payload,
    responseType: Response.Type
  ) async throws -> Response {
    let sealed = try identity.seal(payload, for: peer)
    let body = try Self.encoder.encode(sealed)
    return try await authenticatedRequest(
      peer: peer,
      method: method,
      path: path,
      rawBody: body,
      responseType: responseType
    )
  }

  private func authenticatedRequest<Response: Decodable & Sendable>(
    peer: AgentMeshPeerRecord,
    method: String,
    path: String,
    rawBody: Data,
    responseType: Response.Type
  ) async throws -> Response {
    guard peer.status == .trusted else { throw AgentMeshSecurityError.peerNotTrusted }
    guard peer.protocolVersion == AgentMeshProtocol.version else {
      throw AgentMeshSecurityError.protocolMismatch(peer.protocolVersion)
    }
    let url = try endpointURL(peer.endpoint, path: path)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 30
    request.setValue("application/vnd.agentm5n.mesh+json", forHTTPHeaderField: "Content-Type")

    let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
    let nonce = UUID().uuidString.lowercased()
    let signature = try identity.sign(
      method: method,
      path: path,
      timestampMilliseconds: timestamp,
      nonce: nonce,
      body: rawBody
    )
    request.setValue(String(AgentMeshProtocol.version), forHTTPHeaderField: "X-AgenTM5N-Protocol")
    request.setValue(try identity.nodeID().uuidString.lowercased(), forHTTPHeaderField: "X-AgenTM5N-Node")
    request.setValue(String(timestamp), forHTTPHeaderField: "X-AgenTM5N-Timestamp")
    request.setValue(nonce, forHTTPHeaderField: "X-AgenTM5N-Nonce")
    request.setValue(signature.base64EncodedString(), forHTTPHeaderField: "X-AgenTM5N-Signature")
    if !rawBody.isEmpty { request.httpBody = rawBody }

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw AgentMeshClientError.invalidResponse
    }
    guard (200...299).contains(http.statusCode) else {
      let code = Self.remoteErrorCode(data)
      throw AgentMeshClientError.http(http.statusCode, code)
    }

    try await verifyResponse(
      peer: peer,
      status: http.statusCode,
      path: path,
      data: data,
      response: http
    )
    let sealed = try Self.decoder.decode(AgentMeshSealedMessage.self, from: data)
    return try identity.open(sealed, from: peer, as: responseType)
  }

  private func verifyResponse(
    peer: AgentMeshPeerRecord,
    status: Int,
    path: String,
    data: Data,
    response: HTTPURLResponse
  ) async throws {
    guard let versionText = response.value(forHTTPHeaderField: "X-AgenTM5N-Protocol"),
      let version = Int(versionText), version == AgentMeshProtocol.version,
      let nodeText = response.value(forHTTPHeaderField: "X-AgenTM5N-Node"),
      let nodeID = UUID(uuidString: nodeText), nodeID == peer.id,
      let timestampText = response.value(forHTTPHeaderField: "X-AgenTM5N-Timestamp"),
      let timestamp = Int64(timestampText),
      let nonce = response.value(forHTTPHeaderField: "X-AgenTM5N-Nonce"),
      let signatureText = response.value(forHTTPHeaderField: "X-AgenTM5N-Signature"),
      let signature = Data(base64Encoded: signatureText)
    else {
      throw AgentMeshClientError.invalidResponse
    }

    let authentication = AgentMeshRequestAuthentication(
      nodeID: nodeID,
      timestampMilliseconds: timestamp,
      nonce: nonce,
      signature: signature
    )
    try AgentMeshIdentityStore.verify(
      authentication: authentication,
      method: "RESPONSE-\(status)",
      path: path,
      body: data,
      peer: peer
    )
    try await replayProtector.validate(
      nodeID: peer.id,
      nonce: nonce,
      timestampMilliseconds: timestamp
    )
    try await peerStore.markSeen(id: peer.id)
  }

  private func endpointURL(_ endpoint: String, path: String) throws -> URL {
    guard var components = URLComponents(string: endpoint),
      let scheme = components.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      components.host != nil
    else {
      throw AgentMeshClientError.invalidEndpoint
    }
    let target = URLComponents(string: "http://mesh.invalid\(path)")
    components.path = target?.path ?? path
    components.queryItems = target?.queryItems
    guard let url = components.url else { throw AgentMeshClientError.invalidEndpoint }
    return url
  }

  private func validateBasic(
    _ response: URLResponse,
    data: Data,
    acceptedStatuses: ClosedRange<Int> = 200...299
  ) throws {
    guard let http = response as? HTTPURLResponse else {
      throw AgentMeshClientError.invalidResponse
    }
    guard acceptedStatuses.contains(http.statusCode) else {
      throw AgentMeshClientError.http(http.statusCode, Self.remoteErrorCode(data))
    }
  }

  private static func remoteErrorCode(_ data: Data) -> String {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
      let error = object["error"]
    else { return "remote_error" }
    return error
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
}

private struct AgentMeshEmptyPayload: Codable, Equatable, Sendable {}
