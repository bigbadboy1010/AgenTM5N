import Foundation
import SwiftUI

public enum AgentToolRoundMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case fixed
  case unlimited

  public var id: String { rawValue }
}

public enum AgentToolSelectionMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case all
  case adaptive
  case capabilityFiltered

  public var id: String { rawValue }
}

public enum OllamaThinkingMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case off
  case standard
  case low
  case medium
  case high
  case max

  public var id: String { rawValue }
}

public struct AgentOperatingLayerConfiguration: Codable, Equatable, Sendable {
  public var toolRoundMode: AgentToolRoundMode
  public var maxToolRounds: Int
  public var toolSelectionMode: AgentToolSelectionMode
  public var maxAdvertisedTools: Int
  public var enabledCapabilities: Set<AgentToolCapability>
  public var bundledToolsEnabled: Bool

  public var thinkingMode: OllamaThinkingMode
  public var numContext: Int
  public var numPredict: Int
  public var temperature: Double
  public var topK: Int
  public var topP: Double
  public var minP: Double
  public var repeatPenalty: Double
  public var repeatLastN: Int
  public var seed: Int?
  public var keepAlive: String
  public var requestTimeoutSeconds: Int

  public init(
    toolRoundMode: AgentToolRoundMode = .fixed,
    maxToolRounds: Int = 64,
    toolSelectionMode: AgentToolSelectionMode = .adaptive,
    maxAdvertisedTools: Int = 48,
    enabledCapabilities: Set<AgentToolCapability> = Set(AgentToolCapability.allCases),
    bundledToolsEnabled: Bool = true,
    thinkingMode: OllamaThinkingMode = .standard,
    numContext: Int = 8_192,
    numPredict: Int = 4_096,
    temperature: Double = 0.2,
    topK: Int = 40,
    topP: Double = 0.9,
    minP: Double = 0.0,
    repeatPenalty: Double = 1.1,
    repeatLastN: Int = 64,
    seed: Int? = nil,
    keepAlive: String = "5m",
    requestTimeoutSeconds: Int = 600
  ) {
    self.toolRoundMode = toolRoundMode
    self.maxToolRounds = maxToolRounds
    self.toolSelectionMode = toolSelectionMode
    self.maxAdvertisedTools = maxAdvertisedTools
    self.enabledCapabilities = enabledCapabilities
    self.bundledToolsEnabled = bundledToolsEnabled
    self.thinkingMode = thinkingMode
    self.numContext = numContext
    self.numPredict = numPredict
    self.temperature = temperature
    self.topK = topK
    self.topP = topP
    self.minP = minP
    self.repeatPenalty = repeatPenalty
    self.repeatLastN = repeatLastN
    self.seed = seed
    self.keepAlive = keepAlive
    self.requestTimeoutSeconds = requestTimeoutSeconds
    normalize()
  }

  public static let `default` = AgentOperatingLayerConfiguration()

  public var effectiveToolRoundLimit: Int {
    switch toolRoundMode {
    case .fixed:
      return max(1, min(maxToolRounds, 1_000_000))
    case .unlimited:
      // The legacy AppState loop expects an Int. This sentinel is intentionally
      // far beyond a realistic session while still avoiding Int overflow in UI
      // and diagnostics. Cancellation remains available at every round.
      return 1_000_000_000
    }
  }

  public var ollamaOptions: [String: JSONValue] {
    var options: [String: JSONValue] = [
      "num_ctx": .number(Double(numContext)),
      "num_predict": .number(Double(numPredict)),
      "temperature": .number(temperature),
      "top_k": .number(Double(topK)),
      "top_p": .number(topP),
      "min_p": .number(minP),
      "repeat_penalty": .number(repeatPenalty),
      "repeat_last_n": .number(Double(repeatLastN)),
    ]
    if let seed {
      options["seed"] = .number(Double(seed))
    }
    return options
  }

  public func ollamaThinkValue(legacyThinkingEnabled: Bool) -> JSONValue {
    switch thinkingMode {
    case .off:
      return .bool(false)
    case .standard:
      return .bool(legacyThinkingEnabled || thinkingMode == .standard)
    case .low:
      return .string("low")
    case .medium:
      return .string("medium")
    case .high:
      return .string("high")
    case .max:
      return .string("max")
    }
  }

  public mutating func normalize() {
    maxToolRounds = max(1, min(maxToolRounds, 1_000_000))
    maxAdvertisedTools = max(4, min(maxAdvertisedTools, 256))
    numContext = max(512, min(numContext, 1_048_576))
    numPredict = max(-1, min(numPredict, 131_072))
    temperature = max(0, min(temperature, 2))
    topK = max(0, min(topK, 1_000))
    topP = max(0, min(topP, 1))
    minP = max(0, min(minP, 1))
    repeatPenalty = max(0, min(repeatPenalty, 4))
    repeatLastN = max(-1, min(repeatLastN, 131_072))
    requestTimeoutSeconds = max(30, min(requestTimeoutSeconds, 3_600))
    keepAlive = keepAlive.trimmingCharacters(in: .whitespacesAndNewlines)
    if keepAlive.isEmpty {
      keepAlive = "5m"
    }
  }
}

public enum AgentOperatingLayerStore {
  private static var fileURL: URL {
    AppPaths.applicationSupportDirectory
      .appendingPathComponent("agent-operating-layer.json", isDirectory: false)
  }

  public static func load() -> AgentOperatingLayerConfiguration {
    do {
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return .default
      }
      let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
      var value = try JSONDecoder().decode(AgentOperatingLayerConfiguration.self, from: data)
      value.normalize()
      return value
    } catch {
      AppLogger.app.error(
        "Operating-layer configuration load failed: \(error.localizedDescription, privacy: .public)"
      )
      return .default
    }
  }

  public static func save(_ configuration: AgentOperatingLayerConfiguration) throws {
    var normalized = configuration
    normalized.normalize()
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
    let data = try encoder.encode(normalized)
    try data.write(to: fileURL, options: [.atomic])
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fileURL.path
    )
  }

  public static func effectiveToolRoundLimit(fallback: Int) -> Int {
    let value = load()
    if !FileManager.default.fileExists(atPath: fileURL.path) {
      return max(1, fallback)
    }
    return value.effectiveToolRoundLimit
  }
}

@MainActor
public final class AgentOperatingLayerSettings: ObservableObject {
  public static let shared = AgentOperatingLayerSettings()

  @Published public var configuration: AgentOperatingLayerConfiguration

  private init() {
    configuration = AgentOperatingLayerStore.load()
  }

  public func save() throws {
    configuration.normalize()
    try AgentOperatingLayerStore.save(configuration)
  }

  public func applyRuntimeCompatibility(to appState: AppState) {
    configuration.normalize()
    appState.configuration.maxToolIterations = configuration.effectiveToolRoundLimit
    if configuration.thinkingMode == .off {
      appState.configuration.thinkingEnabled = false
    } else if configuration.thinkingMode == .standard {
      appState.configuration.thinkingEnabled = true
    }
  }

  public func saveAndApply(to appState: AppState) async {
    do {
      configuration.normalize()
      try AgentOperatingLayerStore.save(configuration)
      await appState.saveConfiguration()
      // saveConfiguration() in the 1.1 compatibility layer clamps the legacy
      // field to 24. Restore the effective 1.2 runtime value immediately; the
      // dedicated 1.2 store is authoritative on subsequent launches.
      applyRuntimeCompatibility(to: appState)
    } catch {
      appState.errorMessage = error.localizedDescription
    }
  }

  public func reset(to configuration: AgentOperatingLayerConfiguration = .default) {
    self.configuration = configuration
  }
}
