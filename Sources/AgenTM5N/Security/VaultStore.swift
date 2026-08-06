import CryptoKit
import Foundation

public enum VaultStoreError: LocalizedError {
  case locked
  case unsupportedVersion(Int)
  case secretNotFound(UUID)
  case invalidMasterPassword

  public var errorDescription: String? {
    switch self {
    case .locked:
      "Der Vault ist gesperrt."
    case .unsupportedVersion(let version):
      "Die Vault-Version \(version) wird nicht unterstützt."
    case .secretNotFound(let id):
      "Das Secret \(id.uuidString) wurde nicht gefunden."
    case .invalidMasterPassword:
      "Das Master-Passwort ist falsch oder der Vault wurde beschädigt."
    }
  }
}

public actor VaultStore {
  private struct UnlockedContext {
    let key: SymmetricKey
    let salt: Data
    let iterations: UInt32
    var payload: VaultPayload
  }

  private let url: URL
  private var context: UnlockedContext?

  public init(url: URL) {
    self.url = url
  }

  public var isUnlocked: Bool {
    context != nil
  }

  public func unlock(password: String) throws -> [VaultSecret] {
    if FileManager.default.fileExists(atPath: url.path) {
      let data = try Data(contentsOf: url)
      let envelope = try Self.makeDecoder().decode(VaultEnvelope.self, from: data)
      guard envelope.version == 1 else {
        throw VaultStoreError.unsupportedVersion(envelope.version)
      }

      do {
        let key = try VaultCrypto.deriveKey(
          password: password,
          salt: envelope.salt,
          iterations: envelope.iterations
        )
        let payloadData = try VaultCrypto.open(envelope.sealedPayload, using: key)
        let payload = try Self.makeDecoder().decode(VaultPayload.self, from: payloadData)
        context = UnlockedContext(
          key: key,
          salt: envelope.salt,
          iterations: envelope.iterations,
          payload: payload
        )
        return payload.secrets.sorted {
          $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
      } catch {
        AppLogger.security.error(
          "Vault unlock failed: \(error.localizedDescription, privacy: .public)")
        throw VaultStoreError.invalidMasterPassword
      }
    }

    let salt = try VaultCrypto.randomData(count: VaultCrypto.saltLength)
    let key = try VaultCrypto.deriveKey(
      password: password,
      salt: salt,
      iterations: VaultCrypto.defaultIterations
    )
    context = UnlockedContext(
      key: key,
      salt: salt,
      iterations: VaultCrypto.defaultIterations,
      payload: VaultPayload()
    )
    try persist()
    return []
  }

  public func lock() {
    context = nil
  }

  public func listSecrets() throws -> [VaultSecret] {
    guard let context else {
      throw VaultStoreError.locked
    }
    return context.payload.secrets.sorted {
      $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
    }
  }

  public func secret(id: UUID) throws -> VaultSecret {
    guard let context else {
      throw VaultStoreError.locked
    }
    guard let secret = context.payload.secrets.first(where: { $0.id == id }) else {
      throw VaultStoreError.secretNotFound(id)
    }
    return secret
  }

  public func upsert(_ secret: VaultSecret) throws -> [VaultSecret] {
    guard var context else {
      throw VaultStoreError.locked
    }

    var updatedSecret = secret
    updatedSecret.updatedAt = Date()
    if let index = context.payload.secrets.firstIndex(where: { $0.id == secret.id }) {
      context.payload.secrets[index] = updatedSecret
    } else {
      context.payload.secrets.append(updatedSecret)
    }
    self.context = context
    try persist()
    return try listSecrets()
  }

  public func delete(id: UUID) throws -> [VaultSecret] {
    guard var context else {
      throw VaultStoreError.locked
    }
    context.payload.secrets.removeAll { $0.id == id }
    self.context = context
    try persist()
    return try listSecrets()
  }

  private func persist() throws {
    guard let context else {
      throw VaultStoreError.locked
    }

    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )

    let payloadData = try Self.makeEncoder().encode(context.payload)
    let sealedPayload = try VaultCrypto.seal(payloadData, using: context.key)
    let envelope = VaultEnvelope(
      version: 1,
      salt: context.salt,
      iterations: context.iterations,
      sealedPayload: sealedPayload
    )
    let data = try Self.makeEncoder().encode(envelope)
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path
    )
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
