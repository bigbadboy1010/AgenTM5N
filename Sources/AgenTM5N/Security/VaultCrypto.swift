import CCommonCrypto
import CryptoKit
import Foundation
import Security

public enum VaultCryptoError: LocalizedError {
  case emptyPassword
  case randomGenerationFailed(OSStatus)
  case keyDerivationFailed(Int32)
  case invalidSealedPayload

  public var errorDescription: String? {
    switch self {
    case .emptyPassword:
      "Das Master-Passwort darf nicht leer sein."
    case .randomGenerationFailed(let status):
      "Sichere Zufallsdaten konnten nicht erzeugt werden. Security-Status: \(status)."
    case .keyDerivationFailed(let status):
      "Der Vault-Schlüssel konnte nicht abgeleitet werden. CommonCrypto-Status: \(status)."
    case .invalidSealedPayload:
      "Der verschlüsselte Vault-Inhalt ist ungültig oder beschädigt."
    }
  }
}

public enum VaultCrypto {
  public static let saltLength = 32
  public static let keyLength = 32
  public static let defaultIterations: UInt32 = 600_000

  public static func randomData(count: Int) throws -> Data {
    var data = Data(count: count)
    let status = data.withUnsafeMutableBytes { bytes in
      guard let baseAddress = bytes.baseAddress else {
        return errSecParam
      }
      return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
    }

    guard status == errSecSuccess else {
      throw VaultCryptoError.randomGenerationFailed(status)
    }
    return data
  }

  public static func deriveKey(
    password: String,
    salt: Data,
    iterations: UInt32
  ) throws -> SymmetricKey {
    guard let passwordData = password.data(using: .utf8), !passwordData.isEmpty else {
      throw VaultCryptoError.emptyPassword
    }

    var derivedKey = Data(count: keyLength)
    let status: Int32 = derivedKey.withUnsafeMutableBytes { keyBytes in
      salt.withUnsafeBytes { saltBytes in
        passwordData.withUnsafeBytes { passwordBytes in
          guard
            let keyBase = keyBytes.bindMemory(to: UInt8.self).baseAddress,
            let saltBase = saltBytes.bindMemory(to: UInt8.self).baseAddress,
            let passwordBase = passwordBytes.bindMemory(to: Int8.self).baseAddress
          else {
            return Int32(kCCParamError)
          }

          return CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordBase,
            passwordData.count,
            saltBase,
            salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            iterations,
            keyBase,
            keyLength
          )
        }
      }
    }

    guard status == kCCSuccess else {
      throw VaultCryptoError.keyDerivationFailed(status)
    }
    return SymmetricKey(data: derivedKey)
  }

  public static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
    let box = try AES.GCM.seal(plaintext, using: key)
    guard let combined = box.combined else {
      throw VaultCryptoError.invalidSealedPayload
    }
    return combined
  }

  public static func open(_ ciphertext: Data, using key: SymmetricKey) throws -> Data {
    let box = try AES.GCM.SealedBox(combined: ciphertext)
    return try AES.GCM.open(box, using: key)
  }
}
