import Foundation
import SwiftUI

public enum SavedAgentProviderPreference: String, Codable, CaseIterable, Identifiable, Sendable {
  case current
  case appleOnDevice
  case ollamaLocal
  case ollamaCloud

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .current: "Aktueller Provider"
    case .appleOnDevice: "Apple On-Device"
    case .ollamaLocal: "Ollama Local"
    case .ollamaCloud: "Ollama Cloud"
    }
  }

  public var providerKind: ProviderKind? {
    switch self {
    case .current: nil
    case .appleOnDevice: .appleOnDevice
    case .ollamaLocal: .ollamaLocal
    case .ollamaCloud: .ollamaCloud
    }
  }

  public static func parse(_ value: String?) -> SavedAgentProviderPreference {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    switch normalized {
    case "apple", "apple_on_device", "appleondevice", "on-device", "on_device":
      return .appleOnDevice
    case "ollama_local", "ollamalocal", "local":
      return .ollamaLocal
    case "ollama_cloud", "ollamacloud", "cloud":
      return .ollamaCloud
    default:
      return .current
    }
  }
}

public struct SavedAgentProfile: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var purpose: String
  public var instructions: String
  public var providerPreference: SavedAgentProviderPreference
  public var symbolName: String
  public var isEnabled: Bool
  /// Nil means the specialist inherits the full centrally registered AgenTM5N
  /// tool catalog on every supported provider. A non-empty list is an explicit
  /// sandbox that restricts delegated specialists to the selected capability packs.
  /// Existing V1 profiles decode with nil and therefore keep full tool parity.
  public var allowedCapabilities: [AgentToolCapability]?
  public let createdAt: Date
  public var updatedAt: Date
  public var lastUsedAt: Date?

  public init(
    id: UUID = UUID(),
    name: String,
    purpose: String,
    instructions: String,
    providerPreference: SavedAgentProviderPreference = .current,
    symbolName: String = "person.crop.circle.badge.checkmark",
    isEnabled: Bool = true,
    allowedCapabilities: [AgentToolCapability]? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    lastUsedAt: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.purpose = purpose
    self.instructions = instructions
    self.providerPreference = providerPreference
    self.symbolName = symbolName
    self.isEnabled = isEnabled
    self.allowedCapabilities = allowedCapabilities
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastUsedAt = lastUsedAt
  }

  public var systemInstruction: String {
    let capabilityText = allowedCapabilities?.map(\.rawValue).joined(separator: ", ")
      ?? "all"
    return """
    PERSISTENT SPECIALIST AGENT ACTIVE:
    - Name: \(name)
    - Purpose: \(purpose)
    - Tool capabilities: \(capabilityText)

    Specialist instructions:
    \(instructions)

    Operating rules:
    - Act as this specialist for the current conversation while retaining AgenTM5N's higher-level system, permission, audit, and security rules.
    - Use only the centrally authorized AgenTM5N tools made available to this specialist; this profile never bypasses confirmation requirements or macOS permissions.
    - Stay focused on the specialist purpose. If a request is outside that purpose, state that clearly instead of silently changing the agent's role.
    """
  }
}

public enum PersistentAgentLibraryError: LocalizedError {
  case invalidName
  case invalidPurpose
  case invalidInstructions
  case invalidCapabilities([String])
  case notFound(String)
  case ambiguous(String)

  public var errorDescription: String? {
    switch self {
    case .invalidName:
      "Der Agentenname muss zwischen 1 und 80 Zeichen lang sein."
    case .invalidPurpose:
      "Der Zweck des Agenten muss zwischen 1 und 500 Zeichen lang sein."
    case .invalidInstructions:
      "Die Agentenanweisungen müssen zwischen 1 und 12.000 Zeichen lang sein."
    case .invalidCapabilities(let values):
      "Unbekannte Agenten-Tool-Capabilities: \(values.joined(separator: ", "))"
    case .notFound(let query):
      "Kein gespeicherter Agent passt zu: \(query)"
    case .ambiguous(let query):
      "Der gespeicherte Agent ist nicht eindeutig: \(query)"
    }
  }
}

@MainActor
public final class PersistentAgentLibrary: ObservableObject {
  public static let shared = PersistentAgentLibrary()

  @Published public private(set) var profiles: [SavedAgentProfile] = []

  private let fileURL: URL

  public init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? Self.defaultFileURL()
    loadFromDisk()
  }

  public func resolve(_ query: String) throws -> SavedAgentProfile {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = profiles.filter { profile in
      profile.id.uuidString.caseInsensitiveCompare(normalized) == .orderedSame
        || profile.name.caseInsensitiveCompare(normalized) == .orderedSame
    }
    guard !matches.isEmpty else {
      throw PersistentAgentLibraryError.notFound(query)
    }
    guard matches.count == 1, let profile = matches.first else {
      throw PersistentAgentLibraryError.ambiguous(query)
    }
    return profile
  }

  public func profile(id: UUID) -> SavedAgentProfile? {
    profiles.first { $0.id == id }
  }

  @discardableResult
  public func create(
    name: String,
    purpose: String,
    instructions: String,
    providerPreference: SavedAgentProviderPreference,
    symbolName: String = "person.crop.circle.badge.checkmark",
    allowedCapabilities: [AgentToolCapability]? = nil
  ) throws -> SavedAgentProfile {
    let normalizedName = try validateName(name)
    let normalizedPurpose = try validatePurpose(purpose)
    let normalizedInstructions = try validateInstructions(instructions)
    let normalizedSymbol = normalizedSymbolName(symbolName)
    let normalizedCapabilities = normalizedCapabilities(allowedCapabilities)

    if let existing = profiles.first(where: {
      $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame
    }) {
      return try update(
        query: existing.id.uuidString,
        name: normalizedName,
        purpose: normalizedPurpose,
        instructions: normalizedInstructions,
        providerPreference: providerPreference,
        symbolName: normalizedSymbol,
        enabled: true,
        allowedCapabilities: normalizedCapabilities,
        replaceCapabilities: allowedCapabilities != nil
      )
    }

    let profile = SavedAgentProfile(
      name: normalizedName,
      purpose: normalizedPurpose,
      instructions: normalizedInstructions,
      providerPreference: providerPreference,
      symbolName: normalizedSymbol,
      allowedCapabilities: normalizedCapabilities
    )
    profiles.append(profile)
    sortProfiles()
    try saveToDisk()
    return profile
  }

  @discardableResult
  public func update(
    query: String,
    name: String? = nil,
    purpose: String? = nil,
    instructions: String? = nil,
    providerPreference: SavedAgentProviderPreference? = nil,
    symbolName: String? = nil,
    enabled: Bool? = nil,
    allowedCapabilities: [AgentToolCapability]? = nil,
    replaceCapabilities: Bool = false
  ) throws -> SavedAgentProfile {
    let current = try resolve(query)
    guard let index = profiles.firstIndex(where: { $0.id == current.id }) else {
      throw PersistentAgentLibraryError.notFound(query)
    }

    if let name { profiles[index].name = try validateName(name) }
    if let purpose { profiles[index].purpose = try validatePurpose(purpose) }
    if let instructions {
      profiles[index].instructions = try validateInstructions(instructions)
    }
    if let providerPreference {
      profiles[index].providerPreference = providerPreference
    }
    if let symbolName {
      profiles[index].symbolName = normalizedSymbolName(symbolName)
    }
    if let enabled { profiles[index].isEnabled = enabled }
    if replaceCapabilities {
      profiles[index].allowedCapabilities = normalizedCapabilities(allowedCapabilities)
    }
    profiles[index].updatedAt = Date()
    let updated = profiles[index]
    sortProfiles()
    try saveToDisk()
    return updated
  }

  public func delete(query: String) throws -> SavedAgentProfile {
    let profile = try resolve(query)
    profiles.removeAll { $0.id == profile.id }
    try saveToDisk()
    return profile
  }

  public func markUsed(id: UUID) throws {
    guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
    profiles[index].lastUsedAt = Date()
    profiles[index].updatedAt = Date()
    try saveToDisk()
  }

  private func loadFromDisk() {
    do {
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        profiles = []
        return
      }
      let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      profiles = try decoder.decode([SavedAgentProfile].self, from: data)
      sortProfiles()
    } catch {
      profiles = []
      AppLogger.app.error(
        "Persistent agent library load failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func saveToDisk() throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directory.path
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(profiles)
    try data.write(to: fileURL, options: [.atomic])
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fileURL.path
    )
  }

  private func sortProfiles() {
    profiles.sort {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  private func validateName(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...80).contains(normalized.count) else {
      throw PersistentAgentLibraryError.invalidName
    }
    return normalized
  }

  private func validatePurpose(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...500).contains(normalized.count) else {
      throw PersistentAgentLibraryError.invalidPurpose
    }
    return normalized
  }

  private func validateInstructions(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...12_000).contains(normalized.count) else {
      throw PersistentAgentLibraryError.invalidInstructions
    }
    return normalized
  }

  private func normalizedSymbolName(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? "person.crop.circle.badge.checkmark" : normalized
  }

  private func normalizedCapabilities(
    _ capabilities: [AgentToolCapability]?
  ) -> [AgentToolCapability]? {
    guard let capabilities else { return nil }
    let unique = Set(capabilities)
    return AgentToolCapability.allCases.filter { unique.contains($0) }
  }

  private static func defaultFileURL() -> URL {
    let base = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support", isDirectory: true)
    return base
      .appendingPathComponent("AgenTM5N", isDirectory: true)
      .appendingPathComponent("agents.json", isDirectory: false)
  }
}
