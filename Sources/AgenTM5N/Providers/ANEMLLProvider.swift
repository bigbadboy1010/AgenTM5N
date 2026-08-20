import Foundation

// Carry-forward source-policy markers while Build 39 is target-Mac gated:
// latestUserPrompt | ANEMLL BUILD 37 RUNTIME | ANEMLL BUILD 38 RUNTIME | Build 39
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
    let contextLength: Int?
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
    let runtimeTurn = await prepareRuntimeTurn(
      request.transport,
      contextLength: request.contextLength
    )
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
          let runtimeTurn = await prepareRuntimeTurn(
            request.transport,
            contextLength: request.contextLength
          )
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
    let rawTransport = try ANEMLLToolProtocol.makeTransportRequest(
      messages: messages,
      tools: effectiveTools
    )
    let runtime = ANEMLLRuntimeStore.load()
    let descriptor = try ANEMLLModelBundleInspector.inspect(metaPath: runtime.metaPath)
    let contextLength = descriptor.contextLength
    let transportPrompt = ANEMLLContextBudget.addingRecentConversationContext(
      to: rawTransport.prompt,
      messages: messages,
      isToolContinuation: rawTransport.isToolContinuation,
      contextLength: contextLength
    )
    let transport = ANEMLLToolTransportRequest(
      prompt: transportPrompt,
      userTurnCount: rawTransport.userTurnCount,
      isFreshConversation: rawTransport.isFreshConversation,
      isToolContinuation: rawTransport.isToolContinuation
    )
    let systemPrompt = ANEMLLContextBudget.compactSystemPrompt(
      build39SystemPrompt(in: messages),
      contextLength: contextLength
    )
    let requestedMaxTokens = operating.numPredict > 0
      ? operating.numPredict
      : runtime.defaultMaxTokens
    let effectiveMaxTokens = ANEMLLContextBudget.maxOutputTokens(
      requested: requestedMaxTokens,
      contextLength: contextLength
    )
    let requestedTemperature = operating.temperature.isFinite
      ? operating.temperature
      : runtime.defaultTemperature

    return RequestParameters(
      transport: transport,
      systemPrompt: systemPrompt,
      runtime: runtime,
      contextLength: contextLength,
      maxTokens: effectiveMaxTokens,
      temperature: requestedTemperature,
      timeoutSeconds: operating.requestTimeoutSeconds,
      effectiveTools: effectiveTools
    )
  }

  private func prepareRuntimeTurn(
    _ transport: ANEMLLToolTransportRequest,
    contextLength: Int?
  ) async -> Int {
    let activeTurns = await persistentRuntime.activeTurns()
    if ANEMLLContextBudget.shouldRotateBeforeUserTurn(
      contextLength: contextLength,
      activeTurns: activeTurns,
      isFreshConversation: transport.isFreshConversation,
      isToolContinuation: transport.isToolContinuation
    ) {
      await persistentRuntime.resetConversation()
      return max(1, transport.userTurnCount)
    }
    let currentTurns = await persistentRuntime.activeTurns()
    return max(transport.userTurnCount, currentTurns + 1)
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
    let boundedBase = String(base.prefix(650))

    let runtimeGuard = L10n.text(
      de: """
        ANEMLL BUILD 39 RUNTIME:
        - Lokal über Qwen3/ANEMLL. Reale Tools werden pro Runde aufgelistet.
        - Falls nötig: exakt ein <agentm5n_tool_call>-JSON und kein erfundenes Tool/Ergebnis.
        - Das reale Tool-Ergebnis kommt in dieselbe persistente Sitzung zurück.
        - Freigabe, Secrets, Ausführung und Audit kontrolliert AgenTM5N außerhalb des Modells.
        """,
      en: """
        ANEMLL BUILD 39 RUNTIME:
        - Local Qwen3/ANEMLL. Real tools are listed per round.
        - If needed, emit exactly one <agentm5n_tool_call> JSON and never invent a tool or result.
        - The real tool result returns to the same persistent session.
        - AgenTM5N controls approval, secrets, execution and audit outside the model.
        """,
      fr: """
        RUNTIME ANEMLL BUILD 39 :
        - Qwen3/ANEMLL local. Les outils réels sont listés à chaque tour.
        - Si nécessaire, émettre exactement un JSON <agentm5n_tool_call> sans inventer d’outil ni de résultat.
        - Le résultat réel revient dans la même session persistante.
        - AgenTM5N contrôle autorisation, secrets, exécution et audit hors du modèle.
        """
    )

    return boundedBase.isEmpty ? runtimeGuard : boundedBase + "\n\n" + runtimeGuard
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
