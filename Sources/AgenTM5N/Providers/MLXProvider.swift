import Foundation

public enum MLXProviderError: LocalizedError {
  case invalidBaseURL(String)
  case invalidHTTPResponse
  case httpError(statusCode: Int, body: String)
  case emptyModel
  case malformedToolArguments(tool: String)

  public var errorDescription: String? {
    switch self {
    case .invalidBaseURL(let value):
      "Ungültige MLX-Server-URL: \(value)"
    case .invalidHTTPResponse:
      "Der MLX-Server hat keine gültige HTTP-Antwort geliefert."
    case .httpError(let statusCode, let body):
      "MLX HTTP \(statusCode): \(body)"
    case .emptyModel:
      "Für den MLX-Server wurde kein Modell angegeben."
    case .malformedToolArguments(let tool):
      "Der MLX-Server hat ungültige Tool-Argumente für \(tool) geliefert."
    }
  }
}

/// Local provider for Apple's `mlx_lm.server` OpenAI-compatible HTTP surface.
///
/// AgenTM5N deliberately keeps this transport independent from MLX Swift so
/// the existing SwiftPM release pipeline stays deterministic. The model runs
/// with MLX/Metal in the local sidecar while tool authorization and execution
/// remain inside AgenTM5N.
public final class MLXProvider: @unchecked Sendable {
  private struct ModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
      let id: String
    }
  }

  private struct ChatRequestBody: Encodable {
    let model: String
    let messages: [RequestMessage]
    let tools: [ProviderToolDefinition]?
    let stream: Bool
    let maxTokens: Int
    let temperature: Double
    let topP: Double
    let topK: Int
    let minP: Double
    let repetitionPenalty: Double
    let repetitionContextSize: Int
    let seed: Int?

    enum CodingKeys: String, CodingKey {
      case model
      case messages
      case tools
      case stream
      case maxTokens = "max_tokens"
      case temperature
      case topP = "top_p"
      case topK = "top_k"
      case minP = "min_p"
      case repetitionPenalty = "repetition_penalty"
      case repetitionContextSize = "repetition_context_size"
      case seed
    }
  }

  private struct RequestMessage: Encodable {
    let role: String
    let content: String
    let name: String?
    let toolCallID: String?
    let toolCalls: [RequestToolCall]?

    enum CodingKeys: String, CodingKey {
      case role
      case content
      case name
      case toolCallID = "tool_call_id"
      case toolCalls = "tool_calls"
    }
  }

  private struct RequestToolCall: Encodable {
    let id: String
    let type: String
    let function: Function

    struct Function: Encodable {
      let name: String
      let arguments: String
    }
  }

  private struct ChatResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
      let message: Message

      struct Message: Decodable {
        let content: String?
        let reasoning: String?
        let reasoningContent: String?
        let toolCalls: [ResponseToolCall]?

        enum CodingKeys: String, CodingKey {
          case content
          case reasoning
          case reasoningContent = "reasoning_content"
          case toolCalls = "tool_calls"
        }
      }
    }

    struct Usage: Decodable {
      let promptTokens: Int?
      let completionTokens: Int?

      enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
      }
    }
  }

  private struct ResponseToolCall: Decodable {
    let id: String?
    let function: Function

    struct Function: Decodable {
      let name: String
      let arguments: String
    }
  }

  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func listModels(
    configuration: AppConfiguration,
    apiKey: String?
  ) async throws -> [String] {
    let url = try endpointURL(baseURL: configuration.baseURL, path: "/v1/models")
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    applyAuthorization(apiKey: apiKey, to: &request)

    let (data, response) = try await session.data(for: request)
    try validate(response: response, body: data)
    let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
    return decoded.data.map(\.id).sorted()
  }

  public func streamChat(
    configuration: AppConfiguration,
    apiKey: String?,
    messages: [ProviderMessage],
    tools: [ProviderToolDefinition] = []
  ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !model.isEmpty else { throw MLXProviderError.emptyModel }

          var operatingConfiguration = AgentOperatingLayerStore.load()
          operatingConfiguration.normalize()
          let effectiveTools = scopedTools(
            tools,
            messages: messages,
            configuration: operatingConfiguration
          )
          let url = try endpointURL(
            baseURL: configuration.baseURL,
            path: "/v1/chat/completions"
          )
          var request = URLRequest(url: url)
          request.httpMethod = "POST"
          request.timeoutInterval = TimeInterval(operatingConfiguration.requestTimeoutSeconds)
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          request.setValue("application/json", forHTTPHeaderField: "Accept")
          applyAuthorization(apiKey: apiKey, to: &request)

          let requestMessages = try makeRequestMessages(
            enrichedMessages(
              messages,
              configuration: configuration,
              tools: effectiveTools
            )
          )
          let body = ChatRequestBody(
            model: model,
            messages: requestMessages,
            tools: effectiveTools.isEmpty ? nil : effectiveTools,
            stream: false,
            maxTokens: operatingConfiguration.numPredict < 0
              ? 131_072
              : operatingConfiguration.numPredict,
            temperature: operatingConfiguration.temperature,
            topP: operatingConfiguration.topP,
            topK: operatingConfiguration.topK,
            minP: operatingConfiguration.minP,
            repetitionPenalty: operatingConfiguration.repeatPenalty,
            repetitionContextSize: max(1, operatingConfiguration.repeatLastN),
            seed: operatingConfiguration.seed
          )
          request.httpBody = try JSONEncoder().encode(body)

          let clock = ContinuousClock()
          let startedAt = clock.now
          let (data, response) = try await session.data(for: request)
          try Task.checkCancellation()
          try validate(response: response, body: data)
          let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
          guard let choice = decoded.choices.first else {
            throw MLXProviderError.invalidHTTPResponse
          }

          let toolCalls = try (choice.message.toolCalls ?? []).map(parseToolCall)
          let duration = startedAt.duration(to: clock.now)
          continuation.yield(
            ProviderStreamEvent(
              contentDelta: choice.message.content ?? "",
              thinkingDelta: choice.message.reasoningContent
                ?? choice.message.reasoning
                ?? "",
              toolCalls: toolCalls,
              isFinished: true,
              metrics: ChatMetrics(
                promptTokens: decoded.usage?.promptTokens,
                generatedTokens: decoded.usage?.completionTokens,
                totalDurationNanoseconds: Self.nanoseconds(from: duration)
              )
            )
          )
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          AppLogger.network.error(
            "MLX request failed: \(error.localizedDescription, privacy: .public)"
          )
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private func makeRequestMessages(
    _ messages: [ProviderMessage]
  ) throws -> [RequestMessage] {
    var result: [RequestMessage] = []
    var pendingToolIDs: [String] = []

    for message in messages {
      let role = message.role.rawValue
      if message.role == .assistant, let calls = message.toolCalls, !calls.isEmpty {
        let converted = try calls.map { call -> RequestToolCall in
          let id = UUID().uuidString
          pendingToolIDs.append(id)
          return RequestToolCall(
            id: id,
            type: "function",
            function: .init(
              name: call.function.name,
              arguments: try jsonString(.object(call.function.arguments))
            )
          )
        }
        result.append(
          RequestMessage(
            role: role,
            content: message.content,
            name: nil,
            toolCallID: nil,
            toolCalls: converted
          )
        )
        continue
      }

      if message.role == .tool {
        let toolCallID = pendingToolIDs.isEmpty ? nil : pendingToolIDs.removeFirst()
        result.append(
          RequestMessage(
            role: role,
            content: message.content,
            name: message.toolName,
            toolCallID: toolCallID,
            toolCalls: nil
          )
        )
        continue
      }

      result.append(
        RequestMessage(
          role: role,
          content: message.content,
          name: nil,
          toolCallID: nil,
          toolCalls: nil
        )
      )
    }

    return result
  }

  private func parseToolCall(_ value: ResponseToolCall) throws -> ProviderToolCall {
    guard let data = value.function.arguments.data(using: .utf8) else {
      throw MLXProviderError.malformedToolArguments(tool: value.function.name)
    }
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    guard case .object(let arguments) = decoded else {
      throw MLXProviderError.malformedToolArguments(tool: value.function.name)
    }
    return ProviderToolCall(
      function: .init(name: value.function.name, arguments: arguments)
    )
  }

  private func scopedTools(
    _ tools: [ProviderToolDefinition],
    messages: [ProviderMessage],
    configuration: AgentOperatingLayerConfiguration
  ) -> [ProviderToolDefinition] {
    let allowed = configuration.enabledCapabilities
    var candidates = tools.filter { definition in
      guard let entry = AgentToolRegistry.entry(named: definition.function.name) else {
        return false
      }
      return allowed.contains(entry.capability)
    }

    guard configuration.toolSelectionMode == .adaptive else {
      return candidates
    }

    let prompt = messages.last(where: { $0.role == .user })?.content.lowercased() ?? ""
    let priorityTerms = prompt
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
      .map(String.init)
      .filter { $0.count >= 3 }

    candidates.sort { lhs, rhs in
      let left = relevance(of: lhs, terms: priorityTerms)
      let right = relevance(of: rhs, terms: priorityTerms)
      if left != right { return left > right }
      return lhs.function.name < rhs.function.name
    }
    return Array(candidates.prefix(configuration.maxAdvertisedTools))
  }

  private func relevance(
    of definition: ProviderToolDefinition,
    terms: [String]
  ) -> Int {
    let haystack = (definition.function.name + " " + definition.function.description).lowercased()
    let matches = terms.reduce(0) { partial, term in
      partial + (haystack.contains(term) ? 1 : 0)
    }
    if definition.function.name == "context_search" { return matches + 2 }
    if definition.function.name == "read_file" { return matches + 1 }
    return matches
  }

  private func enrichedMessages(
    _ messages: [ProviderMessage],
    configuration: AppConfiguration,
    tools: [ProviderToolDefinition]
  ) -> [ProviderMessage] {
    guard !tools.isEmpty else { return messages }
    let toolNames = tools.map(\.function.name).joined(separator: ", ")
    let context = """
      AgenTM5N LOCAL RUNTIME CONTEXT:
      You are running inside the user's native macOS AgenTM5N application.
      The supplied function tools are real executable capabilities, not examples.
      Active workspace: \(configuration.workspacePath)
      Permission mode: \(configuration.permissionMode.displayName)
      Available tools: \(toolNames)
      Use tools before claiming that local, repository, terminal, server, or macOS access is unavailable.
      """

    guard let first = messages.first, first.role == .system else {
      return [ProviderMessage(role: .system, content: context)] + messages
    }
    return [
      ProviderMessage(role: .system, content: first.content + "\n\n" + context)
    ] + Array(messages.dropFirst())
  }

  private func jsonString(_ value: JSONValue) throws -> String {
    let data = try JSONEncoder().encode(value)
    return String(decoding: data, as: UTF8.self)
  }

  private func endpointURL(baseURL: String, path: String) throws -> URL {
    guard var components = URLComponents(string: baseURL) else {
      throw MLXProviderError.invalidBaseURL(baseURL)
    }
    let base = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let endpoint = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    components.path = "/" + [base, endpoint].filter { !$0.isEmpty }.joined(separator: "/")
    guard let url = components.url else {
      throw MLXProviderError.invalidBaseURL(baseURL)
    }
    return url
  }

  private func applyAuthorization(apiKey: String?, to request: inout URLRequest) {
    guard let apiKey, !apiKey.isEmpty else { return }
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
  }

  private func validate(response: URLResponse, body: Data) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw MLXProviderError.invalidHTTPResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let bounded = Data(body.prefix(64 * 1024))
      let text = String(data: bounded, encoding: .utf8) ?? "Keine Fehlerdetails"
      throw MLXProviderError.httpError(statusCode: httpResponse.statusCode, body: text)
    }
  }

  private static func nanoseconds(from duration: Duration) -> UInt64 {
    let components = duration.components
    let seconds = max(0, components.seconds)
    let attoseconds = max(0, components.attoseconds)
    let secondsNanoseconds = UInt64(seconds) * 1_000_000_000
    let fractionalNanoseconds = UInt64(attoseconds / 1_000_000_000)
    return secondsNanoseconds + fractionalNanoseconds
  }
}
