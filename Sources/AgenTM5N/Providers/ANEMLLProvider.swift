import Foundation

public final class ANEMLLProvider: @unchecked Sendable {
  private let persistentRuntime: ANEMLLPersistentRuntimeService

  public init(
    persistentRuntime: ANEMLLPersistentRuntimeService = .shared
  ) {
    self.persistentRuntime = persistentRuntime
  }

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
    let systemPrompt = build37SystemPrompt(in: messages)

    var operating = AgentOperatingLayerStore.load()
    operating.normalize()
    let runtime = ANEMLLRuntimeStore.load()
    let requestedMaxTokens = operating.numPredict > 0
      ? operating.numPredict
      : runtime.defaultMaxTokens
    let requestedTemperature = operating.temperature.isFinite
      ? operating.temperature
      : runtime.defaultTemperature
    let userTurnCount = messages.reduce(into: 0) { count, message in
      if message.role == .user { count += 1 }
    }

    let result = try await persistentRuntime.complete(
      prompt: prompt,
      systemPrompt: systemPrompt,
      thinkingEnabled: configuration.thinkingEnabled,
      maxTokens: requestedMaxTokens,
      temperature: requestedTemperature,
      requestTimeoutSeconds: operating.requestTimeoutSeconds,
      userTurnCount: userTurnCount,
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

  public func streamChat(
    configuration: AppConfiguration,
    messages: [ProviderMessage],
    tools _: [ProviderToolDefinition] = []
  ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let event = try await complete(
            configuration: configuration,
            messages: messages
          )
          try Task.checkCancellation()
          continuation.yield(event)
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  public func resetConversation() async {
    await persistentRuntime.resetConversation()
    ANEMLLRuntimeTelemetry.shared.clear()
  }

  public func shutdown() async {
    await persistentRuntime.shutdown()
  }

  private func latestUserPrompt(in messages: [ProviderMessage]) throws -> String {
    for message in messages.reversed() {
      switch message.role {
      case .user:
        let prompt = PromptAttachmentService.providerPrompt(from: message.content)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
          return prompt
        }
      case .system, .assistant, .tool:
        continue
      }
    }
    throw ANEMLLRuntimeError.missingPrompt
  }

  private func build37SystemPrompt(in messages: [ProviderMessage]) -> String {
    var base = ""
    for message in messages {
      switch message.role {
      case .system:
        base = message.content
      case .user, .assistant, .tool:
        continue
      }
      if !base.isEmpty { break }
    }

    let runtimeGuard = L10n.text(
      de: """
        ANEMLL BUILD 37 RUNTIME:
        - Du läufst lokal über Qwen3 / ANEMLL auf der Apple Neural Engine.
        - In diesem Runtime-Meilenstein sind AgenTM5N-Werkzeugaufrufe noch nicht an Qwen3 angebunden.
        - Behaupte niemals, eine Datei, einen Kalender, Mail, Terminal, SSH, Docker oder ein anderes Werkzeug ausgeführt oder gelesen zu haben, wenn dir kein Werkzeugergebnis vorliegt.
        - Wenn eine Anfrage zwingend eine externe Aktion benötigt, erkläre knapp, dass diese Aktion in diesem Qwen3-Runtime-Meilenstein noch nicht ausgeführt wurde.
        """,
      en: """
        ANEMLL BUILD 37 RUNTIME:
        - You are running locally through Qwen3 / ANEMLL on Apple Neural Engine.
        - AgenTM5N tool calls are not yet connected to Qwen3 in this runtime milestone.
        - Never claim that files, Calendar, Mail, Terminal, SSH, Docker, or another tool was executed or read unless an actual tool result is present.
        - If a request requires an external action, state briefly that the action was not executed in this Qwen3 runtime milestone.
        """,
      fr: """
        RUNTIME ANEMLL BUILD 37 :
        - Tu fonctionnes localement via Qwen3 / ANEMLL sur l’Apple Neural Engine.
        - Les appels d’outils AgenTM5N ne sont pas encore reliés à Qwen3 dans cette étape.
        - Ne prétends jamais avoir exécuté ou lu des fichiers, Calendrier, Mail, Terminal, SSH, Docker ou un autre outil sans résultat réel d’outil.
        - Si une requête exige une action externe, indique brièvement qu’elle n’a pas été exécutée dans cette étape du runtime Qwen3.
        """
    )

    return base.isEmpty ? runtimeGuard : base + "\n\n" + runtimeGuard
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
