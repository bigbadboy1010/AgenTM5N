import CryptoKit
import Foundation
import Security

public enum AgentMeshSecurityError: LocalizedError, Equatable {
  case keychain(OSStatus)
  case invalidKeyMaterial
  case invalidSignature
  case protocolMismatch(Int)
  case wrongRecipient
  case replayDetected
  case expiredRequest
  case peerNotTrusted
  case decryptionFailed

  public var errorDescription: String? {
    switch self {
    case .keychain(let status):
      return "Agent Mesh Keychain-Fehler: \(status)"
    case .invalidKeyMaterial:
      return "Agent Mesh Schluesselmaterial ist ungueltig."
    case .invalidSignature:
      return "Agent Mesh Signatur ist ungueltig."
    case .protocolMismatch(let version):
      return "Nicht kompatible Agent-Mesh-Protokollversion: \(version)."
    case .wrongRecipient:
      return "Agent-Mesh-Nachricht ist fuer einen anderen Node bestimmt."
    case .replayDetected:
      return "Agent-Mesh-Replay wurde blockiert."
    case .expiredRequest:
      return "Agent-Mesh-Request ist abgelaufen."
    case .peerNotTrusted:
      return "Agent-Mesh-Peer ist nicht vertraut."
    case .decryptionFailed:
      return "Agent-Mesh-Payload konnte nicht entschluesselt werden."
    }
  }
}

public struct AgentMeshRequestAuthentication: Equatable, Sendable {
  public let nodeID: UUID
  public let timestampMilliseconds: Int64
  public let nonce: String
  public let signature: Data

  public init(
    nodeID: UUID,
    timestampMilliseconds: Int64,
    nonce: String,
    signature: Data
  ) {
    self.nodeID = nodeID
    self.timestampMilliseconds = timestampMilliseconds
    self.nonce = nonce
    self.signature = signature
  }
}

public final class AgentMeshIdentityStore: @unchecked Sendable {
  public static let shared = AgentMeshIdentityStore()

  private let lock = NSLock()
  private let service = "team.cloudforge.AgenTM5N.AgentMesh.Identity"
  private var cachedNodeID: UUID?
  private var cachedSigningKey: Curve25519.Signing.PrivateKey?
  private var cachedAgreementKey: Curve25519.KeyAgreement.PrivateKey?

  public init() {}

  public func nodeID() throws -> UUID {
    lock.lock()
    defer { lock.unlock() }
    if let cachedNodeID { return cachedNodeID }

    if let data = try readKeychain(account: "node-id"),
      let value = String(data: data, encoding: .utf8),
      let uuid = UUID(uuidString: value)
    {
      cachedNodeID = uuid
      return uuid
    }

    let uuid = UUID()
    try writeKeychain(Data(uuid.uuidString.utf8), account: "node-id")
    cachedNodeID = uuid
    return uuid
  }

  public func signingKey() throws -> Curve25519.Signing.PrivateKey {
    lock.lock()
    defer { lock.unlock() }
    if let cachedSigningKey { return cachedSigningKey }

    if let data = try readKeychain(account: "signing-private") {
      guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
        throw AgentMeshSecurityError.invalidKeyMaterial
      }
      cachedSigningKey = key
      return key
    }

    let key = Curve25519.Signing.PrivateKey()
    try writeKeychain(key.rawRepresentation, account: "signing-private")
    cachedSigningKey = key
    return key
  }

  public func agreementKey() throws -> Curve25519.KeyAgreement.PrivateKey {
    lock.lock()
    defer { lock.unlock() }
    if let cachedAgreementKey { return cachedAgreementKey }

    if let data = try readKeychain(account: "agreement-private") {
      guard let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) else {
        throw AgentMeshSecurityError.invalidKeyMaterial
      }
      cachedAgreementKey = key
      return key
    }

    let key = Curve25519.KeyAgreement.PrivateKey()
    try writeKeychain(key.rawRepresentation, account: "agreement-private")
    cachedAgreementKey = key
    return key
  }

  public func descriptor(
    name: String? = nil,
    kind: AgentMeshPeerKind = .agentM5N,
    capabilities: Set<AgentToolCapability> = Set(AgentToolCapability.allCases)
  ) throws -> AgentMeshNodeDescriptor {
    let nodeID = try nodeID()
    let signing = try signingKey().publicKey.rawRepresentation
    let agreement = try agreementKey().publicKey.rawRepresentation
    let bundle = Bundle.main
    let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    let explicitName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedName = (explicitName?.isEmpty == false ? explicitName : nil)
      ?? Host.current().localizedName
      ?? "AgenTM5N-\(nodeID.uuidString.prefix(8))"

    return AgentMeshNodeDescriptor(
      nodeID: nodeID,
      name: resolvedName,
      kind: kind,
      appVersion: version,
      appBuild: build,
      signingPublicKey: signing,
      agreementPublicKey: agreement,
      fingerprint: Self.fingerprint(signingPublicKey: signing, agreementPublicKey: agreement),
      capabilities: capabilities,
      features: [
        "signed-machine-identity",
        "recipient-bound-signatures",
        "x25519-chacha20poly1305",
        "capability-scopes",
        "task-events",
        "tool-approval-routing",
        "agentnexus-envelope",
      ]
    )
  }

  public func sign(
    method: String,
    path: String,
    recipientNodeID: UUID,
    timestampMilliseconds: Int64,
    nonce: String,
    body: Data
  ) throws -> Data {
    try signingKey().signature(
      for: Self.canonicalRequest(
        method: method,
        path: path,
        recipientNodeID: recipientNodeID,
        timestampMilliseconds: timestampMilliseconds,
        nonce: nonce,
        body: body
      )
    )
  }

  public func seal<T: Encodable & Sendable>(
    _ value: T,
    for peer: AgentMeshPeerRecord
  ) throws -> AgentMeshSealedMessage {
    guard peer.protocolVersion == AgentMeshProtocol.version else {
      throw AgentMeshSecurityError.protocolMismatch(peer.protocolVersion)
    }
    let encoder = JSONEncoder.agentMesh
    let plaintext = try encoder.encode(value)
    let key = try sharedKey(with: peer)
    let sealedBox = try ChaChaPoly.seal(plaintext, using: key)
    let combined = sealedBox.combined
    return AgentMeshSealedMessage(
      senderNodeID: try nodeID(),
      recipientNodeID: peer.id,
      sealedPayload: combined
    )
  }

  public func open<T: Decodable & Sendable>(
    _ message: AgentMeshSealedMessage,
    from peer: AgentMeshPeerRecord,
    as type: T.Type
  ) throws -> T {
    guard message.protocolVersion == AgentMeshProtocol.version else {
      throw AgentMeshSecurityError.protocolMismatch(message.protocolVersion)
    }
    guard message.senderNodeID == peer.id, message.recipientNodeID == (try nodeID()) else {
      throw AgentMeshSecurityError.wrongRecipient
    }
    guard abs(message.createdAt.timeIntervalSinceNow) <= AgentMeshProtocol.maximumClockSkewSeconds else {
      throw AgentMeshSecurityError.expiredRequest
    }

    let key = try sharedKey(with: peer)
    guard let box = try? ChaChaPoly.SealedBox(combined: message.sealedPayload),
      let plaintext = try? ChaChaPoly.open(box, using: key)
    else {
      throw AgentMeshSecurityError.decryptionFailed
    }
    return try JSONDecoder.agentMesh.decode(T.self, from: plaintext)
  }

  public func sharedKey(with peer: AgentMeshPeerRecord) throws -> SymmetricKey {
    guard let publicKey = try? Curve25519.KeyAgreement.PublicKey(
      rawRepresentation: peer.agreementPublicKey
    ) else {
      throw AgentMeshSecurityError.invalidKeyMaterial
    }
    let shared = try agreementKey().sharedSecretFromKeyAgreement(with: publicKey)
    let localID = try nodeID().uuidString.lowercased()
    let remoteID = peer.id.uuidString.lowercased()
    let identityPair = [localID, remoteID].sorted().joined(separator: "|")
    return shared.hkdfDerivedSymmetricKey(
      using: SHA256.self,
      salt: Data("AgenTM5N-AgentMesh-v1".utf8),
      sharedInfo: Data(identityPair.utf8),
      outputByteCount: 32
    )
  }

  public static func verify(
    authentication: AgentMeshRequestAuthentication,
    method: String,
    path: String,
    recipientNodeID: UUID,
    body: Data,
    peer: AgentMeshPeerRecord
  ) throws {
    guard peer.status == .trusted else { throw AgentMeshSecurityError.peerNotTrusted }
    guard peer.id == authentication.nodeID else { throw AgentMeshSecurityError.invalidSignature }
    guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: peer.signingPublicKey) else {
      throw AgentMeshSecurityError.invalidKeyMaterial
    }
    let canonical = canonicalRequest(
      method: method,
      path: path,
      recipientNodeID: recipientNodeID,
      timestampMilliseconds: authentication.timestampMilliseconds,
      nonce: authentication.nonce,
      body: body
    )
    guard publicKey.isValidSignature(authentication.signature, for: canonical) else {
      throw AgentMeshSecurityError.invalidSignature
    }
  }

  public static func fingerprint(signingPublicKey: Data, agreementPublicKey: Data) -> String {
    let digest = SHA256.hash(data: signingPublicKey + agreementPublicKey)
    return digest.prefix(16)
      .map { String(format: "%02X", $0) }
      .joined()
      .splitEvery(4)
      .joined(separator: "-")
  }

  private static func canonicalRequest(
    method: String,
    path: String,
    recipientNodeID: UUID,
    timestampMilliseconds: Int64,
    nonce: String,
    body: Data
  ) -> Data {
    let bodyHash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
    return Data(
      [
        "AGENTM5N-MESH-SIGNED-V1",
        method.uppercased(),
        path,
        recipientNodeID.uuidString.lowercased(),
        String(timestampMilliseconds),
        nonce,
        bodyHash,
      ].joined(separator: "\n").utf8
    )
  }

  private func readKeychain(account: String) throws -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw AgentMeshSecurityError.keychain(status) }
    return item as? Data
  }

  private func writeKeychain(_ data: Data, account: String) throws {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let updateStatus = SecItemUpdate(
      base as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw AgentMeshSecurityError.keychain(updateStatus)
    }
    var add = base
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(add as CFDictionary, nil)
    guard addStatus == errSecSuccess else { throw AgentMeshSecurityError.keychain(addStatus) }
  }
}

public actor AgentMeshReplayProtector {
  public static let shared = AgentMeshReplayProtector()
  private var seen: [String: Date] = [:]

  public init() {}

  public func validate(
    nodeID: UUID,
    nonce: String,
    timestampMilliseconds: Int64,
    now: Date = Date()
  ) throws {
    let requestDate = Date(timeIntervalSince1970: Double(timestampMilliseconds) / 1_000.0)
    guard abs(requestDate.timeIntervalSince(now)) <= AgentMeshProtocol.maximumClockSkewSeconds else {
      throw AgentMeshSecurityError.expiredRequest
    }

    let expiry = now.addingTimeInterval(-AgentMeshProtocol.maximumClockSkewSeconds)
    seen = seen.filter { $0.value >= expiry }
    let key = "\(nodeID.uuidString.lowercased())|\(nonce)"
    guard seen[key] == nil else { throw AgentMeshSecurityError.replayDetected }
    seen[key] = now

    if seen.count > 8_192 {
      let oldest = seen.sorted { $0.value < $1.value }.prefix(seen.count - 8_192)
      for item in oldest { seen.removeValue(forKey: item.key) }
    }
  }
}

extension JSONEncoder {
  fileprivate static var agentMesh: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}

extension JSONDecoder {
  fileprivate static var agentMesh: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

private extension String {
  func splitEvery(_ length: Int) -> [String] {
    guard length > 0 else { return [self] }
    var result: [String] = []
    var index = startIndex
    while index < endIndex {
      let end = self.index(index, offsetBy: length, limitedBy: endIndex) ?? endIndex
      result.append(String(self[index..<end]))
      index = end
    }
    return result
  }
}
