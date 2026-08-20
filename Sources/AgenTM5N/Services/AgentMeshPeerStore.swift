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
    let existing = peersByID[descriptor.nodeID]
    let now = Date()

    if let existing, existing.status == .trusted {
      // A trusted identity may update its endpoint/name, but key rotation is a
      // deliberate trust event and therefore never happens implicitly.
      guard existing.signingPublicKey == descriptor.signingPublicKey,
        existing.agreementPublicKey == descriptor.agreementPublicKey
      else {
        throw AgentMeshSecurityError.invalidKeyMaterial
      }
      var updated = existing
      updated.name = descriptor.name
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
      name: descriptor.name,
      kind: descriptor.kind,
      endpoint: cleanEndpoint,
      signingPublicKey: descriptor.signingPublicKey,
      agreementPublicKey: descriptor.agreementPublicKey,
      fingerprint: descriptor.fingerprint,
      status: existing?.status == .revoked ? .revoked : .pending,
      allowedCapabilities: existing?.allowedCapabilities ?? [],
      protocolVersion: descriptor.protocolVersion,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      lastSeenAt: existing?.lastSeenAt
    )
    peersByID[record.id] = record
    try save()
    return record
  }

  @discardableResult
  public func trust(
    id: UUID,
    allowedCapabilities: Set<AgentToolCapability> = []
  ) throws -> AgentMeshPeerRecord {
    try loadIfNeeded()
    guard var peer = peersByID[id] else { throw AgentMeshSecurityError.peerNotTrusted }
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
    peer.lastSeenAt = Date()
    peer.updatedAt = Date()
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
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(
      peersByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    )
    try data.write(to: fileURL, options: [.atomic])
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
}
