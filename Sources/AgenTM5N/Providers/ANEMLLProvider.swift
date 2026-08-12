import Foundation

public final class ANEMLLProvider: @unchecked Sendable {
  public init() {}

  public func listModels() throws -> [String] {
    let runtime = ANEMLLRuntimeStore.load()
    guard !runtime.metaPath.isEmpty else { return [] }
    let descriptor = try ANEMLLModelBundleInspector.inspect(metaPath: runtime.metaPath)
    return [descriptor.modelName]
  }

  public func complete(
    configuration: AppConfiguration,
    messages: [ProviderMessage]
  ) async throws -> ProviderStreamEvent {
    let prompt = try latestUserPrompt(in: messages)
    let systemPrompt = systemPrompt(in: messages)

    var operating = AgentOperatingLayerStore.load()
    operating.normalize()
    let runtime = ANEMLLRuntimeStore.load()
    let requestedMaxTokens = operating.numPredict > 0
      ? operating.numPredict
      : runtime.defaultMaxTokens
    let requestedTemperature = operating.temperature.isFinite
      ? operating.temperature
      : runtime.defaultTemperature

    let result = try await ANEMLLNativeRuntime.complete(
      prompt: prompt,
      systemPrompt: systemPrompt,
      thinkingEnabled: configuration.thinkingEnabled,
      maxTokens: requestedMaxTokens,
      temperature: requestedTemperature,
      runtimeConfiguration: runtime
    )
    ANEMLLRuntimeTelemetry.shared.record(result)

    let separated = separateThinking(result.response)
    return ProviderStreamEvent(
      contentDelta: separated.content,
      thinkingDelta: separated.thinking,
      isFinished: true,
      metrics: result.metrics.chatMetrics
    )
  }

  private func latestUserPrompt(in messages: [ProviderMessage]) throws -> String {
    for message in messages.reversed() {
      switch message.role {
      case .user:
        let prompt = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
          return prompt
        }
      case .system, .assistant, .tool:
        continue
      }
    }
    throw ANEMLLRuntimeError.missingPrompt
  }

  private func systemPrompt(in messages: [ProviderMessage]) -> String {
    for message in messages {
      switch message.role {
      case .system:
        return message.content
      case .user, .assistant, .tool:
        continue
      }
    }
    return ""
  }

  private func separateThinking(_ response: String) -> (content: String, thinking: String) {
    guard
      let start = response.range(of: "<think>"),
      let end = response.range(of: "</think>", range: start.upperBound..<response.endIndex)
    else {
      return (response, "")
    }

    let thinking = String(response[start.upperBound..<end.lowerBound])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let before = String(response[..<start.lowerBound])
    let after = String(response[end.upperBound...])
    let content = (before + after).trimmingCharacters(in: .whitespacesAndNewlines)

    // Never hide the whole model response merely because the generation ended
    // inside a thinking block or produced no final text.
    guard !content.isEmpty else {
      return (response, "")
    }
    return (content, thinking)
  }
}
