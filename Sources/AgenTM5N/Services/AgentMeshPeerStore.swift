import Foundation

public actor AgentMeshPeerStore {
  public static let shared = AgentMeshPeerStore()

  private let fileURL: URL
  private var peersByID: [UUID: AgentMeshPeerRecord] = [:]
  private var loaded = false

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      let manager = FileManager.default
      let base = (try? manager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )) ?? manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
      self.fileURL = base
        .appendingPathComponent("AgenTM5N", isDirectory: true)
        .appendingPathComponent("agent-mesh-peers.json", isDirectory: false)
    }
  }

  public func all() throws -> [AgentMeshPeerRecord] {
    try loadIfNeeded()
    return peersByID.values.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  public func peer(id: UUID) throws -> AgentMeshPeerRecord? {
    try loadIfNeeded()
    return peersByID[id]
  }

  public func trustedPeer(id: UUID) throws -> AgentMeshPeerRecord? {
    try loadIfNeeded()
    guard let peer = peersByID[id], peer.status == .trusted else { return nil }
    return peer
  }

  @discardableResult
  public func registerPending(
    descriptor: AgentMeshNodeDescriptor,
    endpoint: String
  ) throws -> AgentMeshPeerRecord {
    try loadIfNeeded()
    guard descriptor.protocolVersion == AgentMeshProtocol.version else {
      throw AgentMeshSecurityError.protocolMismatch(descriptor.protocolVersion)
    }
    guard descriptor.fingerprint == AgentMeshIdentityStore.fingerprint(
      signingPublicKey: descriptor.signingPublicKey,
      agreementPublicKey: descriptor.agreementPublicKey
    ) else {
      throw AgentMeshSecurityError.invalidKeyMaterial
    }

    let cleanEndpoint = try Self.normalizedEndpoint(endpoint)
    let now = Date()
    let cleanName = Self.sanitizedPeerName(descriptor.name, nodeID: descriptor.nodeID)

    if let existing = peersByID[descriptor.nodeID] {
      // A Node ID is permanently bound to the first observed key pair. This is
      // required even while pending; otherwise unauthenticated re-enrollment
      // could replace the fingerprint between display and the user's Trust tap.
      guard existing.signingPublicKey == descriptor.signingPublicKey,
        existing.agreementPublicKey == descriptor.agreementPublicKey,
        existing.fingerprint == descriptor.fingerprint
      else {
        throw AgentMeshSecurityError.invalidKeyMaterial
      }

      var updated = existing
      updated.name = cleanName
      updated.endpoint = cleanEndpoint
      updated.kind = descriptor.kind
      updated.protocolVersion = descriptor.protocolVersion
      updated.updatedAt = now
      peersByID[updated.id] = updated
      try save()
      return updated
    }

    let record = AgentMeshPeerRecord(
      id: descriptor.nodeID,
      name: cleanName,
      kind: descriptor.kind,
      endpoint: cleanEndpoint,
      signingPublicKey: descriptor.signingPublicKey,
      agreementPublicKey: descriptor.agreementPublicKey,
      fingerprint: descriptor.fingerprint,
      status: .pending,
      allowedCapabilities: [],
      protocolVersion: descriptor.protocolVersion,
      createdAt: now,
      updatedAt: now,
      lastSeenAt: nil
    )
    peersByID[record.id] = record
    try save()
    return record
  }

  @discardableResult
  public func trust(
    id: UUID,
    expectedFingerprint: String,
    allowedCapabilities: Set<AgentToolCapability> = []
  ) throws -> AgentMeshPeerRecord {
    try loadIfNeeded()
    guard var peer = peersByID[id], peer.status == .pending else {
      throw AgentMeshSecurityError.peerNotTrusted
    }
    guard Self.normalizedFingerprint(expectedFingerprint) == Self.normalizedFingerprint(peer.fingerprint) else {
      throw AgentMeshSecurityError.invalidKeyMaterial
    }
    peer.status = .trusted
    peer.allowedCapabilities = allowedCapabilities
    peer.updatedAt = Date()
    peersByID[id] = peer
    try save()
    return peer
  }

  @discardableResult
  public func updateCapabilities(
    id: UUID,
    allowedCapabilities: Set<AgentToolCapability>
  ) throws -> AgentMeshPeerRecord {
    try loadIfNeeded()
    guard var peer = peersByID[id], peer.status == .trusted else {
      throw AgentMeshSecurityError.peerNotTrusted
    }
    peer.allowedCapabilities = allowedCapabilities
    peer.updatedAt = Date()
    peersByID[id] = peer
    try save()
    return peer
  }

  @discardableResult
  public func revoke(id: UUID) throws -> AgentMeshPeerRecord {
    try loadIfNeeded()
    guard var peer = peersByID[id] else { throw AgentMeshSecurityError.peerNotTrusted }
    peer.status = .revoked
    peer.allowedCapabilities = []
    peer.updatedAt = Date()
    peersByID[id] = peer
    try save()
    return peer
  }

  public func markSeen(id: UUID) throws {
    try loadIfNeeded()
    guard var peer = peersByID[id], peer.status == .trusted else { return }
    let now = Date()
    if let lastSeenAt = peer.lastSeenAt, now.timeIntervalSince(lastSeenAt) < 60 {
      return
    }
    peer.lastSeenAt = now
    peer.updatedAt = now
    peersByID[id] = peer
    try save()
  }

  public func remove(id: UUID) throws {
    try loadIfNeeded()
    peersByID.removeValue(forKey: id)
    try save()
  }

  private func loadIfNeeded() throws {
    guard !loaded else { return }
    loaded = true
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
    let data = try Data(contentsOf: fileURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let records = try decoder.decode([AgentMeshPeerRecord].self, from: data)
    peersByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
  }

  private func save() throws {
    let manager = FileManager.default
    let directory = fileURL.deletingLastPathComponent()
    try manager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(
      peersByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    )
    try data.write(to: fileURL, options: [.atomic])
    try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }

  private static func normalizedEndpoint(_ raw: String) throws -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while value.hasSuffix("/") { value.removeLast() }
    guard let url = URL(string: value),
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      url.host != nil
    else {
      throw URLError(.badURL)
    }
    return value
  }

  private static func sanitizedPeerName(_ raw: String, nodeID: UUID) -> String {
    let scalars = raw.unicodeScalars.filter { scalar in
      !CharacterSet.controlCharacters.contains(scalar)
        && scalar != "\n"
        && scalar != "\r"
    }
    let clean = String(String.UnicodeScalarView(scalars))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let bounded = String(clean.prefix(64))
    return bounded.isEmpty ? "Peer-\(nodeID.uuidString.prefix(8))" : bounded
  }

  private static func normalizedFingerprint(_ value: String) -> String {
    value.uppercased().filter { $0.isHexDigit }
  }
}
