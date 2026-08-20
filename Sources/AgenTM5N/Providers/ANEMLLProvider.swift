import Foundation

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
    let transport: ANEMLLToolTransportRequest
    let systemPrompt: String
    let runtime: ANEMLLRuntimeConfiguration
    let maxTokens: Int
    let temperature: Double
    let timeoutSeconds: Int
    let effectiveTools: [ProviderToolDefinition]
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
    let request = try makeRequest(
      configuration: configuration,
      messages: messages,
      tools: []
    )
    let runtimeTurn = await prepareRuntimeTurn(request.transport)
    let result = try await persistentRuntime.complete(
      prompt: request.transport.prompt,
      systemPrompt: request.systemPrompt,
      thinkingEnabled: configuration.thinkingEnabled,
      maxTokens: request.maxTokens,
      temperature: request.temperature,
      requestTimeoutSeconds: request.timeoutSeconds,
      userTurnCount: runtimeTurn,
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
    tools: [ProviderToolDefinition] = []
  ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let streamID = ANEMLLStreamingTelemetry.shared.begin()
      let task = Task {
        do {
          let request = try makeRequest(
            configuration: configuration,
            messages: messages,
            tools: tools
          )
          let runtimeTurn = await prepareRuntimeTurn(request.transport)
          let thinkingSplitter = ANEMLLThinkingDeltaSplitter()
          let toolFilter = ANEMLLToolEnvelopeFilter()

          let result = try await persistentRuntime.completeStreaming(
            prompt: request.transport.prompt,
            systemPrompt: request.systemPrompt,
            thinkingEnabled: configuration.thinkingEnabled,
            maxTokens: request.maxTokens,
            temperature: request.temperature,
            requestTimeoutSeconds: request.timeoutSeconds,
            userTurnCount: runtimeTurn,
            runtimeConfiguration: request.runtime,
            onAssistantDelta: { delta in
              let separated = thinkingSplitter.consume(delta)
              let visibleContent = toolFilter.consume(separated.content)
              let visibleCount = visibleContent.count + separated.thinking.count
              if visibleCount > 0 {
                ANEMLLStreamingTelemetry.shared.recordDelta(
                  streamID: streamID,
                  characterCount: visibleCount
                )
              }
              guard !visibleContent.isEmpty || !separated.thinking.isEmpty else {
                return
              }
              continuation.yield(
                ProviderStreamEvent(
                  contentDelta: visibleContent,
                  thinkingDelta: separated.thinking
                )
              )
            }
          )
          try Task.checkCancellation()

          let toolCalls = try ANEMLLToolProtocol.parseToolCalls(
            from: result.response,
            allowedTools: request.effectiveTools
          )

          let thinkingTail = thinkingSplitter.finish()
          let contentTail = toolFilter.consume(thinkingTail.content) + toolFilter.finish()
          let tailCount = contentTail.count + thinkingTail.thinking.count
          if tailCount > 0 {
            ANEMLLStreamingTelemetry.shared.recordDelta(
              streamID: streamID,
              characterCount: tailCount
            )
            continuation.yield(
              ProviderStreamEvent(
                contentDelta: contentTail,
                thinkingDelta: thinkingTail.thinking
              )
            )
          }

          if !toolCalls.isEmpty {
            continuation.yield(
              ProviderStreamEvent(toolCalls: toolCalls)
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
    messages: [ProviderMessage],
    tools: [ProviderToolDefinition]
  ) throws -> RequestParameters {
    var operating = AgentOperatingLayerStore.load()
    operating.normalize()
    let effectiveTools = ANEMLLToolProtocol.selectTools(
      tools,
      messages: messages,
      operatingConfiguration: operating
    )
    let transport = try ANEMLLToolProtocol.makeTransportRequest(
      messages: messages,
      tools: effectiveTools
    )
    let systemPrompt = build39SystemPrompt(in: messages)
    let runtime = ANEMLLRuntimeStore.load()
    let requestedMaxTokens = operating.numPredict > 0
      ? operating.numPredict
      : runtime.defaultMaxTokens
    let requestedTemperature = operating.temperature.isFinite
      ? operating.temperature
      : runtime.defaultTemperature

    return RequestParameters(
      transport: transport,
      systemPrompt: systemPrompt,
      runtime: runtime,
      maxTokens: requestedMaxTokens,
      temperature: requestedTemperature,
      timeoutSeconds: operating.requestTimeoutSeconds,
      effectiveTools: effectiveTools
    )
  }

  private func prepareRuntimeTurn(
    _ transport: ANEMLLToolTransportRequest
  ) async -> Int {
    if transport.isFreshConversation {
      await persistentRuntime.resetConversation()
    }
    let activeTurns = await persistentRuntime.activeTurns()
    return max(transport.userTurnCount, activeTurns + 1)
  }

  private func build39SystemPrompt(in messages: [ProviderMessage]) -> String {
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
        ANEMLL BUILD 39 RUNTIME:
        - Du läufst lokal über Qwen3/ANEMLL. AgenTM5N kann dir pro Runde eine kleine Liste realer Werkzeuge geben.
        - Wenn ein Werkzeug nötig ist, verwende ausschließlich das angegebene <agentm5n_tool_call>-JSON-Format und höchstens einen Aufruf pro Runde.
        - Erfinde keine Werkzeuge oder Ergebnisse. Nach einem Werkzeugaufruf erhältst du das reale Ergebnis in derselben persistenten Sitzung.
        - Die Ausführung, Freigabe, Secrets und Auditierung kontrolliert AgenTM5N außerhalb des Modells.
        """,
      en: """
        ANEMLL BUILD 39 RUNTIME:
        - You run locally through Qwen3/ANEMLL. AgenTM5N may provide a small list of real tools for each round.
        - When a tool is required, use only the supplied <agentm5n_tool_call> JSON format and request at most one tool per round.
        - Never invent tools or results. After a tool call you receive the real result in the same persistent session.
        - Execution, approvals, secrets and auditing are controlled by AgenTM5N outside the model.
        """,
      fr: """
        RUNTIME ANEMLL BUILD 39 :
        - Tu fonctionnes localement via Qwen3/ANEMLL. AgenTM5N peut fournir une petite liste d’outils réels à chaque tour.
        - Si un outil est nécessaire, utilise uniquement le format JSON <agentm5n_tool_call> fourni et au maximum un appel par tour.
        - N’invente jamais d’outil ni de résultat. Après un appel, le résultat réel revient dans la même session persistante.
        - L’exécution, les autorisations, les secrets et l’audit restent contrôlés par AgenTM5N hors du modèle.
        """
    )

    return base.isEmpty ? runtimeGuard : base + "\n\n" + runtimeGuard
  }

  private func separateThinking(_ response: String) -> (content: String, thinking: String) {
    guard
      let start = response.range(of: "<think>"),
      let end = response.range(of: "</think>", range: start.upperBound..<response.endIndex)
    else {
      return (ANEMLLToolProtocol.removeToolEnvelopes(from: response), "")
    }

    let thinking = String(response[start.upperBound..<end.lowerBound])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let before = String(response[..<start.lowerBound])
    let after = String(response[end.upperBound...])
    let content = ANEMLLToolProtocol.removeToolEnvelopes(from: before + after)

    guard !content.isEmpty else {
      return (ANEMLLToolProtocol.removeToolEnvelopes(from: response), "")
    }
    return (content, thinking)
  }
}
