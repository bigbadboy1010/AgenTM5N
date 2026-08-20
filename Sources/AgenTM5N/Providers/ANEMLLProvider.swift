import Foundation

// Build 38 evolves the Build 37 persistent runtime in place. This legacy
// source-policy baseline marker remains until the Build 38 release metadata is
// promoted after the target-Mac streaming gate: ANEMLL BUILD 37 RUNTIME
private final class ANEMLLThinkingDeltaSplitter: @unchecked Sendable {
  private let lock = NSLock()
  private var buffer = ""
  private var isThinking = false

  func consume(_ delta: String) -> (content: String, thinking: String) {
    lock.lock()
    defer { lock.unlock() }
    buffer += delta
    return drain(flushAll: false)
  }

  func finish() -> (content: String, thinking: String) {
    lock.lock()
    defer { lock.unlock() }
    return drain(flushAll: true)
  }

  private func drain(flushAll: Bool) -> (content: String, thinking: String) {
    var content = ""
    var thinking = ""

    while !buffer.isEmpty {
      let marker = isThinking ? "</think>" : "<think>"
      if let range = buffer.range(of: marker) {
        let segment = String(buffer[..<range.lowerBound])
        append(segment, content: &content, thinking: &thinking)
        buffer.removeSubrange(buffer.startIndex..<range.upperBound)
        isThinking.toggle()
        continue
      }

      if flushAll {
        append(buffer, content: &content, thinking: &thinking)
        buffer.removeAll(keepingCapacity: true)
        break
      }

      let retainedCount = longestSuffixMatchingPrefix(of: marker, in: buffer)
      let emitCount = buffer.count - retainedCount
      guard emitCount > 0 else { break }
      let boundary = buffer.index(buffer.startIndex, offsetBy: emitCount)
      let segment = String(buffer[..<boundary])
      append(segment, content: &content, thinking: &thinking)
      buffer.removeSubrange(buffer.startIndex..<boundary)
    }

    return (content, thinking)
  }

  private func append(
    _ value: String,
    content: inout String,
    thinking: inout String
  ) {
    guard !value.isEmpty else { return }
    if isThinking {
      thinking += value
    } else {
      content += value
    }
  }

  private func longestSuffixMatchingPrefix(of marker: String, in value: String) -> Int {
    let maximum = min(max(marker.count - 1, 0), value.count)
    guard maximum > 0 else { return 0 }
    for count in stride(from: maximum, through: 1, by: -1) {
      if marker.hasPrefix(value.suffix(count)) {
        return count
      }
    }
    return 0
  }
}

public final class ANEMLLProvider: @unchecked Sendable {
  private struct RequestParameters: Sendable {
    let prompt: String
    let systemPrompt: String
    let runtime: ANEMLLRuntimeConfiguration
    let maxTokens: Int
    let temperature: Double
    let timeoutSeconds: Int
    let userTurnCount: Int
  }

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
    let request = try makeRequest(configuration: configuration, messages: messages)
    let result = try await persistentRuntime.complete(
      prompt: request.prompt,
      systemPrompt: request.systemPrompt,
      thinkingEnabled: configuration.thinkingEnabled,
      maxTokens: request.maxTokens,
      temperature: request.temperature,
      requestTimeoutSeconds: request.timeoutSeconds,
      userTurnCount: request.userTurnCount,
      runtimeConfiguration: request.runtime
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
      let streamID = ANEMLLStreamingTelemetry.shared.begin()
      let task = Task {
        do {
          let request = try makeRequest(configuration: configuration, messages: messages)
          let splitter = ANEMLLThinkingDeltaSplitter()
          let result = try await persistentRuntime.completeStreaming(
            prompt: request.prompt,
            systemPrompt: request.systemPrompt,
            thinkingEnabled: configuration.thinkingEnabled,
            maxTokens: request.maxTokens,
            temperature: request.temperature,
            requestTimeoutSeconds: request.timeoutSeconds,
            userTurnCount: request.userTurnCount,
            runtimeConfiguration: request.runtime,
            onAssistantDelta: { delta in
              let separated = splitter.consume(delta)
              let visibleCount = separated.content.count + separated.thinking.count
              if visibleCount > 0 {
                ANEMLLStreamingTelemetry.shared.recordDelta(
                  streamID: streamID,
                  characterCount: visibleCount
                )
              }
              guard !separated.content.isEmpty || !separated.thinking.isEmpty else {
                return
              }
              continuation.yield(
                ProviderStreamEvent(
                  contentDelta: separated.content,
                  thinkingDelta: separated.thinking
                )
              )
            }
          )
          try Task.checkCancellation()

          let tail = splitter.finish()
          let tailCount = tail.content.count + tail.thinking.count
          if tailCount > 0 {
            ANEMLLStreamingTelemetry.shared.recordDelta(
              streamID: streamID,
              characterCount: tailCount
            )
            continuation.yield(
              ProviderStreamEvent(
                contentDelta: tail.content,
                thinkingDelta: tail.thinking
              )
            )
          }

          ANEMLLRuntimeTelemetry.shared.record(result)
          let activeTurns = await persistentRuntime.activeTurns()
          ANEMLLStreamingTelemetry.shared.complete(
            streamID: streamID,
            metrics: result.metrics,
            activeTurns: activeTurns
          )
          continuation.yield(
            ProviderStreamEvent(
              isFinished: true,
              metrics: result.metrics.chatMetrics
            )
          )
          continuation.finish()
        } catch is CancellationError {
          let activeTurns = await persistentRuntime.activeTurns()
          ANEMLLStreamingTelemetry.shared.cancel(
            streamID: streamID,
            activeTurns: activeTurns
          )
          continuation.finish()
        } catch {
          let activeTurns = await persistentRuntime.activeTurns()
          ANEMLLStreamingTelemetry.shared.fail(
            streamID: streamID,
            activeTurns: activeTurns
          )
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
    ANEMLLStreamingTelemetry.shared.clear()
  }

  public func shutdown() async {
    await persistentRuntime.shutdown()
    ANEMLLStreamingTelemetry.shared.clear()
  }

  private func makeRequest(
    configuration: AppConfiguration,
    messages: [ProviderMessage]
  ) throws -> RequestParameters {
    let prompt = try latestUserPrompt(in: messages)
    let systemPrompt = build38SystemPrompt(in: messages)

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

    return RequestParameters(
      prompt: prompt,
      systemPrompt: systemPrompt,
      runtime: runtime,
      maxTokens: requestedMaxTokens,
      temperature: requestedTemperature,
      timeoutSeconds: operating.requestTimeoutSeconds,
      userTurnCount: userTurnCount
    )
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

  private func build38SystemPrompt(in messages: [ProviderMessage]) -> String {
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
        ANEMLL BUILD 38 RUNTIME:
        - Du läufst lokal über Qwen3 / ANEMLL auf der Apple Neural Engine.
        - Deine Textausgabe wird vom persistenten nativen Runtime-Prozess inkrementell an die AgenTM5N-Oberfläche gestreamt.
        - AgenTM5N-Werkzeugaufrufe sind in diesem Runtime-Meilenstein noch nicht an Qwen3 angebunden; das folgt in Build 39.
        - Behaupte niemals, eine Datei, einen Kalender, Mail, Terminal, SSH, Docker oder ein anderes Werkzeug ausgeführt oder gelesen zu haben, wenn dir kein Werkzeugergebnis vorliegt.
        - Wenn eine Anfrage zwingend eine externe Aktion benötigt, erkläre knapp, dass diese Aktion in diesem Qwen3-Runtime-Meilenstein noch nicht ausgeführt wurde.
        """,
      en: """
        ANEMLL BUILD 38 RUNTIME:
        - You are running locally through Qwen3 / ANEMLL on Apple Neural Engine.
        - Your text output is streamed incrementally from the persistent native runtime process into the AgenTM5N interface.
        - AgenTM5N tool calls are not yet connected to Qwen3 in this runtime milestone; that follows in Build 39.
        - Never claim that files, Calendar, Mail, Terminal, SSH, Docker, or another tool was executed or read unless an actual tool result is present.
        - If a request requires an external action, state briefly that the action was not executed in this Qwen3 runtime milestone.
        """,
      fr: """
        RUNTIME ANEMLL BUILD 38 :
        - Tu fonctionnes localement via Qwen3 / ANEMLL sur l’Apple Neural Engine.
        - Ton texte est diffusé progressivement du processus natif persistant vers l’interface AgenTM5N.
        - Les appels d’outils AgenTM5N ne sont pas encore reliés à Qwen3 dans cette étape ; ils suivent dans le Build 39.
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
