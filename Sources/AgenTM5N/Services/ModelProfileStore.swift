import Foundation

public actor ModelProfileStore {
  public static let shared = ModelProfileStore()

  private let fileURL: URL
  private var document: ModelProfileDocument?

  public init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? AppPaths.applicationSupportDirectory
      .appendingPathComponent("model-profiles.json", isDirectory: false)
  }

  public func load() throws -> ModelProfileDocument {
    if let document { return document }
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      let fresh = ModelProfileDocument(profiles: [ModelProfileCatalog.appleBuiltIn])
      document = fresh
      try persist(fresh)
      return fresh
    }
    let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
    var decoded = try Self.decoder.decode(ModelProfileDocument.self, from: data)
    decoded.profiles = decoded.profiles.map { profile in
      var value = profile
      value.normalize()
      return value
    }
    if !decoded.profiles.contains(where: { $0.id == ModelProfileCatalog.appleBuiltIn.id }) {
      decoded.profiles.append(ModelProfileCatalog.appleBuiltIn)
    }
    if let active = decoded.activeProfileID,
      !decoded.profiles.contains(where: { $0.id == active })
    {
      decoded.activeProfileID = nil
    }
    document = decoded
    return decoded
  }

  public func all() throws -> [ModelProfile] {
    try load().profiles
  }

  public func activeProfile() throws -> ModelProfile? {
    let value = try load()
    guard let id = value.activeProfileID else { return nil }
    return value.profiles.first(where: { $0.id == id })
  }

  @discardableResult
  public func upsert(_ profile: ModelProfile) throws -> ModelProfile {
    var value = try load()
    var normalized = profile
    normalized.normalize()
    normalized.updatedAt = Date()
    if let index = value.profiles.firstIndex(where: { $0.id == normalized.id }) {
      value.profiles[index] = normalized
    } else {
      value.profiles.append(normalized)
    }
    document = value
    try persist(value)
    return normalized
  }

  @discardableResult
  public func mergeDiscoveredLocalOllamaProfiles(
    _ discoveredProfiles: [ModelProfile]
  ) throws -> [ModelProfile] {
    var value = try load()
    var merged: [ModelProfile] = []
    merged.reserveCapacity(discoveredProfiles.count)

    for profile in discoveredProfiles where profile.runtime == .ollamaLocal {
      var incoming = profile
      incoming.normalize()
      incoming.apiKeySecretID = nil

      if let index = value.profiles.firstIndex(where: {
        Self.sameLocalOllamaIdentity($0, incoming)
      }) {
        var existing = value.profiles[index]
        existing.capabilities = incoming.capabilities
        existing.updatedAt = Date()
        existing.normalize()
        value.profiles[index] = existing
        merged.append(existing)
      } else {
        incoming.updatedAt = Date()
        value.profiles.append(incoming)
        merged.append(incoming)
      }
    }

    document = value
    try persist(value)
    return merged
  }

  public func remove(id: UUID) throws {
    guard id != ModelProfileCatalog.appleBuiltIn.id else { return }
    var value = try load()
    value.profiles.removeAll(where: { $0.id == id })
    if value.activeProfileID == id { value.activeProfileID = nil }
    document = value
    try persist(value)
  }

  public func setActive(id: UUID?) throws {
    var value = try load()
    if let id, !value.profiles.contains(where: { $0.id == id && $0.enabled }) {
      throw ModelProfileError.profileNotFound
    }
    value.activeProfileID = id
    document = value
    try persist(value)
  }

  public func profile(id: UUID) throws -> ModelProfile? {
    try load().profiles.first(where: { $0.id == id })
  }

  public func routingCandidates(preferLocal: Bool) throws -> [ModelProfile] {
    ModelProfileCatalog.routingCandidates(from: try load().profiles, preferLocal: preferLocal)
  }

  private func persist(_ value: ModelProfileDocument) throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    let data = try Self.encoder.encode(value)
    try data.write(to: fileURL, options: [.atomic])
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }

  private static func sameLocalOllamaIdentity(
    _ lhs: ModelProfile,
    _ rhs: ModelProfile
  ) -> Bool {
    guard lhs.runtime == .ollamaLocal, rhs.runtime == .ollamaLocal else { return false }
    return canonicalBaseURL(lhs.baseURL) == canonicalBaseURL(rhs.baseURL)
      && lhs.modelIdentifier == rhs.modelIdentifier
  }

  private static func canonicalBaseURL(_ value: String) -> String {
    var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    while normalized.hasSuffix("/") {
      normalized.removeLast()
    }
    return normalized
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}
