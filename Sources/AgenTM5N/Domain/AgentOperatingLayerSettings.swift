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

public enum LocalInferenceRuntime: String, Codable, CaseIterable, Identifiable, Sendable {
  case ollama
  case mlxServer
  case anemll

  public var id: String { rawValue }

  public var defaultBaseURL: String {
    switch self {
    case .ollama:
      "http://localhost:11434"
    case .mlxServer:
      "http://127.0.0.1:8080"
    case .anemll:
      "anemll://neural-engine"
    }
  }
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
  public var stagnationGuardEnabled: Bool
  public var maxIdenticalToolRounds: Int

  public var localInferenceRuntime: LocalInferenceRuntime
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
    stagnationGuardEnabled: Bool = true,
    maxIdenticalToolRounds: Int = 3,
    localInferenceRuntime: LocalInferenceRuntime = .ollama,
    thinkingMode: OllamaThinkingMode = .off,
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
    self.stagnationGuardEnabled = stagnationGuardEnabled
    self.maxIdenticalToolRounds = maxIdenticalToolRounds
    self.localInferenceRuntime = localInferenceRuntime
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

  private enum CodingKeys: String, CodingKey {
    case toolRoundMode
    case maxToolRounds
    case toolSelectionMode
    case maxAdvertisedTools
    case enabledCapabilities
    case bundledToolsEnabled
    case stagnationGuardEnabled
    case maxIdenticalToolRounds
    case localInferenceRuntime
    case thinkingMode
    case numContext
    case numPredict
    case temperature
    case topK
    case topP
    case minP
    case repeatPenalty
    case repeatLastN
    case seed
    case keepAlive
    case requestTimeoutSeconds
  }

  public init(from decoder: Decoder) throws {
    let defaults = Self.default
    let container = try decoder.container(keyedBy: CodingKeys.self)
    toolRoundMode = try container.decodeIfPresent(AgentToolRoundMode.self, forKey: .toolRoundMode)
      ?? defaults.toolRoundMode
    maxToolRounds = try container.decodeIfPresent(Int.self, forKey: .maxToolRounds)
      ?? defaults.maxToolRounds
    toolSelectionMode = try container.decodeIfPresent(AgentToolSelectionMode.self, forKey: .toolSelectionMode)
      ?? defaults.toolSelectionMode
    maxAdvertisedTools = try container.decodeIfPresent(Int.self, forKey: .maxAdvertisedTools)
      ?? defaults.maxAdvertisedTools
    enabledCapabilities = try container.decodeIfPresent(Set<AgentToolCapability>.self, forKey: .enabledCapabilities)
      ?? defaults.enabledCapabilities
    bundledToolsEnabled = try container.decodeIfPresent(Bool.self, forKey: .bundledToolsEnabled)
      ?? defaults.bundledToolsEnabled
    stagnationGuardEnabled = try container.decodeIfPresent(Bool.self, forKey: .stagnationGuardEnabled)
      ?? defaults.stagnationGuardEnabled
    maxIdenticalToolRounds = try container.decodeIfPresent(Int.self, forKey: .maxIdenticalToolRounds)
      ?? defaults.maxIdenticalToolRounds
    localInferenceRuntime = try container.decodeIfPresent(LocalInferenceRuntime.self, forKey: .localInferenceRuntime)
      ?? defaults.localInferenceRuntime
    thinkingMode = try container.decodeIfPresent(OllamaThinkingMode.self, forKey: .thinkingMode)
      ?? defaults.thinkingMode
    numContext = try container.decodeIfPresent(Int.self, forKey: .numContext)
      ?? defaults.numContext
    numPredict = try container.decodeIfPresent(Int.self, forKey: .numPredict)
      ?? defaults.numPredict
    temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
      ?? defaults.temperature
    topK = try container.decodeIfPresent(Int.self, forKey: .topK)
      ?? defaults.topK
    topP = try container.decodeIfPresent(Double.self, forKey: .topP)
      ?? defaults.topP
    minP = try container.decodeIfPresent(Double.self, forKey: .minP)
      ?? defaults.minP
    repeatPenalty = try container.decodeIfPresent(Double.self, forKey: .repeatPenalty)
      ?? defaults.repeatPenalty
    repeatLastN = try container.decodeIfPresent(Int.self, forKey: .repeatLastN)
      ?? defaults.repeatLastN
    seed = try container.decodeIfPresent(Int.self, forKey: .seed)
    keepAlive = try container.decodeIfPresent(String.self, forKey: .keepAlive)
      ?? defaults.keepAlive
    requestTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .requestTimeoutSeconds)
      ?? defaults.requestTimeoutSeconds
    normalize()
  }

  public var effectiveToolRoundLimit: Int? {
    switch toolRoundMode {
    case .fixed:
      return max(1, min(maxToolRounds, 1_000_000))
    case .unlimited:
      return nil
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

  public func ollamaThinkValue(legacyThinkingEnabled _: Bool) -> JSONValue {
    switch thinkingMode {
    case .off:
      return .bool(false)
    case .standard:
      return .bool(true)
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
    maxIdenticalToolRounds = max(2, min(maxIdenticalToolRounds, 20))
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

  public static func runtimeToolRoundLimit(fallback: Int) -> Int {
    load().effectiveToolRoundLimit ?? max(1_000_000_000, fallback)
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
      ?? 1_000_000_000
    appState.configuration.thinkingEnabled = configuration.thinkingMode != .off
  }

  public func saveAndApply(to appState: AppState) async {
    do {
      configuration.normalize()
      try AgentOperatingLayerStore.save(configuration)
      if configuration.bundledToolsEnabled {
        BundledToolPackInstaller.ensureInstalled()
      }
      await appState.saveConfiguration()
      // AppConfiguration still persists the legacy field for 1.1 compatibility.
      // Restore the authoritative 1.2 runtime value after that compatibility save.
      applyRuntimeCompatibility(to: appState)
    } catch {
      appState.errorMessage = error.localizedDescription
    }
  }

  public func reset(to configuration: AgentOperatingLayerConfiguration = .default) {
    self.configuration = configuration
  }
}
