import Foundation

public enum OllamaModelCapabilityPolicy {
  public static func supportsThinking(
    model: String,
    capabilities: Set<String>
  ) -> Bool {
    if AgentOperatingLayerConfiguration.isGPTOssModel(model) {
      return true
    }

    let normalizedCapabilities = Set(capabilities.map { $0.lowercased() })
    if normalizedCapabilities.contains("thinking") {
      return true
    }

    // Capability discovery through /api/show is authoritative. These fallbacks
    // keep established Ollama thinking families working if metadata discovery
    // is temporarily unavailable while still leaving unknown models fail-safe.
    let normalizedModel = model
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    return normalizedModel.contains("qwen3")
      || normalizedModel.contains("deepseek-r1")
      || normalizedModel.contains("deepseek-v3.1")
  }

  public static func supportsTools(capabilities: Set<String>) -> Bool {
    let normalizedCapabilities = Set(capabilities.map { $0.lowercased() })
    return normalizedCapabilities.contains("tools")
      || normalizedCapabilities.contains("tool")
  }

  /// Returns nil when the selected model does not advertise/support Ollama's
  /// thinking protocol. A nil value must be omitted from the /api/chat body;
  /// sending even `think: false` to a non-thinking model can be rejected by
  /// Ollama.
  public static func thinkValue(
    model: String,
    capabilities: Set<String>,
    operatingConfiguration: AgentOperatingLayerConfiguration,
    legacyThinkingEnabled: Bool
  ) -> JSONValue? {
    guard supportsThinking(model: model, capabilities: capabilities) else {
      return nil
    }

    if AgentOperatingLayerConfiguration.isGPTOssModel(model) {
      return operatingConfiguration.ollamaThinkValue(
        forModel: model,
        legacyThinkingEnabled: legacyThinkingEnabled
      )
    }

    // Ollama documents boolean thinking for Qwen3, DeepSeek and most other
    // thinking-capable families. Reasoning levels are GPT-OSS-specific.
    switch operatingConfiguration.thinkingMode {
    case .off:
      return .bool(false)
    case .standard, .low, .medium, .high, .max:
      return .bool(true)
    }
  }

  public static func profileCapabilities(
    model: String,
    ollamaCapabilities: Set<String>
  ) -> Set<ModelProfileCapability> {
    let normalized = Set(ollamaCapabilities.map { $0.lowercased() })
    var result: Set<ModelProfileCapability> = [.textGeneration, .streaming]

    if supportsTools(capabilities: normalized) {
      result.insert(.toolCalling)
    }
    if supportsThinking(model: model, capabilities: normalized) {
      result.insert(.thinking)
    }
    if normalized.contains("vision") {
      result.insert(.imageInput)
    }

    return result
  }
}
