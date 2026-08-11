import Foundation

public enum JSONDocumentStoreError: LocalizedError {
  case invalidParentDirectory(URL)

  public var errorDescription: String? {
    switch self {
    case .invalidParentDirectory(let url):
      "Das übergeordnete Verzeichnis für \(url.path) konnte nicht bestimmt werden."
    }
  }
}

public actor JSONDocumentStore<Value: Codable & Sendable> {
  private let url: URL
  private let defaultValue: Value

  public init(url: URL, defaultValue: Value) {
    self.url = url
    self.defaultValue = defaultValue
  }

  public func load() throws -> Value {
    let manager = FileManager.default
    guard manager.fileExists(atPath: url.path) else {
      return Self.applyOperatingLayerCompatibility(to: defaultValue)
    }

    let data = try Data(contentsOf: url)
    let decoded = try Self.makeDecoder().decode(Value.self, from: data)
    return Self.applyOperatingLayerCompatibility(to: decoded)
  }

  public func save(_ value: Value) throws {
    guard !url.deletingLastPathComponent().path.isEmpty else {
      throw JSONDocumentStoreError.invalidParentDirectory(url)
    }

    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )

    let data = try Self.makeEncoder().encode(value)
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path
    )
  }

  private static func applyOperatingLayerCompatibility(to value: Value) -> Value {
    guard var configuration = value as? AppConfiguration else {
      return value
    }

    configuration.maxToolIterations = AgentOperatingLayerStore.effectiveToolRoundLimit(
      fallback: configuration.maxToolIterations
    )

    guard let adjusted = configuration as? Value else {
      return value
    }
    return adjusted
  }

  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  private static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
