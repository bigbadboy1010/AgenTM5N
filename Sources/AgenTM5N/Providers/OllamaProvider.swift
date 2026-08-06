import Foundation

public enum OllamaProviderError: LocalizedError {
  case invalidBaseURL(String)
  case invalidHTTPResponse
  case httpError(statusCode: Int, body: String)
  case malformedStreamLine(String)
  case emptyModel

  public var errorDescription: String? {
    switch self {
    case .invalidBaseURL(let value):
      "Die Ollama Base URL ist ungültig: \(value)"
    case .invalidHTTPResponse:
      "Ollama hat keine gültige HTTP-Antwort geliefert."
    case .httpError(let statusCode, let body):
      "Ollama HTTP \(statusCode): \(body)"
    case .malformedStreamLine(let line):
      "Eine Ollama-Streaming-Zeile konnte nicht verarbeitet werden: \(line)"
    case .emptyModel:
      "Es wurde kein Ollama-Modell angegeben."
    }
  }
}

public final class OllamaProvider: @unchecked Sendable {
  private struct ChatRequestBody: Encodable {
    let model: String
    let messages: [ProviderMessage]
    let tools: [ProviderToolDefinition]?
    let stream: Bool
    let think: Bool
  }

  private struct ChatChunk: Decodable {
    let message: Message?
    let done: Bool
    let totalDuration: UInt64?
    let promptEvalCount: Int?
    let evalCount: Int?
    let evalDuration: UInt64?

    enum CodingKeys: String, CodingKey {
      case message
      case done
      case totalDuration = "total_duration"
      case promptEvalCount = "prompt_eval_count"
      case evalCount = "eval_count"
      case evalDuration = "eval_duration"
    }

    struct Message: Decodable {
      let content: String?
      let thinking: String?
      let toolCalls: [ProviderToolCall]?

      enum CodingKeys: String, CodingKey {
        case content
        case thinking
        case toolCalls = "tool_calls"
      }
    }
  }

  private struct TagsResponse: Decodable {
    let models: [Model]

    struct Model: Decodable {
      let name: String
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
    let url = try endpointURL(baseURL: configuration.baseURL, path: "/api/tags")
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 30
    applyAuthorization(apiKey: apiKey, to: &request)

    let (data, response) = try await session.data(for: request)
    try validate(response: response, body: data)
    let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
    return decoded.models.map(\.name).sorted()
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
          guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OllamaProviderError.emptyModel
          }

          let url = try endpointURL(baseURL: configuration.baseURL, path: "/api/chat")
          var request = URLRequest(url: url)
          request.httpMethod = "POST"
          request.timeoutInterval = 600
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
          applyAuthorization(apiKey: apiKey, to: &request)

          let requestMessages = enrichedMessages(
            messages,
            configuration: configuration,
            tools: tools
          )
          let body = ChatRequestBody(
            model: configuration.model,
            messages: requestMessages,
            tools: tools.isEmpty ? nil : tools,
            stream: true,
            think: configuration.thinkingEnabled
          )
          request.httpBody = try JSONEncoder().encode(body)

          let (bytes, response) = try await session.bytes(for: request)
          guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaProviderError.invalidHTTPResponse
          }
          guard (200...299).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
              errorData.append(byte)
              if errorData.count >= 64 * 1024 {
                break
              }
            }
            let bodyText = String(data: errorData, encoding: .utf8) ?? "Keine Fehlerdetails"
            throw OllamaProviderError.httpError(
              statusCode: httpResponse.statusCode,
              body: bodyText
            )
          }

          let decoder = JSONDecoder()
          var generatedContent = ""
          var receivedToolCalls = false

          for try await line in bytes.lines {
            try Task.checkCancellation()
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8) else {
              throw OllamaProviderError.malformedStreamLine(trimmed)
            }

            let chunk = try decoder.decode(ChatChunk.self, from: data)
            let contentDelta = chunk.message?.content ?? ""
            let toolCalls = chunk.message?.toolCalls ?? []
            generatedContent += contentDelta
            receivedToolCalls = receivedToolCalls || !toolCalls.isEmpty

            let metrics: ChatMetrics? =
              chunk.done
              ? ChatMetrics(
                promptTokens: chunk.promptEvalCount,
                generatedTokens: chunk.evalCount,
                totalDurationNanoseconds: chunk.totalDuration,
                evaluationDurationNanoseconds: chunk.evalDuration
              )
              : nil

            continuation.yield(
              ProviderStreamEvent(
                contentDelta: contentDelta,
                thinkingDelta: chunk.message?.thinking ?? "",
                toolCalls: toolCalls,
                isFinished: chunk.done,
                metrics: metrics
              )
            )
          }

          if !tools.isEmpty,
            !receivedToolCalls,
            looksLikeCapabilityDenial(generatedContent)
          {
            continuation.yield(
              ProviderStreamEvent(
                contentDelta: """


                  ---
                  **AgenTM5N-Diagnose:** Das Modell `\(configuration.model)` hat die bereitgestellten lokalen Werkzeuge ignoriert und stattdessen fehlenden Zugriff behauptet. Wähle einen Tool-Calling-fähigen Ollama-Provider, prüfe den Agent-Badge und starte eine neue Sitzung. Der konfigurierte Workspace ist `\(configuration.workspacePath)`.
                  """,
                isFinished: true
              )
            )
          }

          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          AppLogger.network.error(
            "Ollama request failed: \(error.localizedDescription, privacy: .public)")
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private func enrichedMessages(
    _ messages: [ProviderMessage],
    configuration: AppConfiguration,
    tools: [ProviderToolDefinition]
  ) -> [ProviderMessage] {
    guard !tools.isEmpty else { return messages }

    let toolNames = tools.map(\.function.name).joined(separator: ", ")
    let runtimeContext = """
      You are AgenTM5N running inside a native macOS application on the user's current Mac.
      The function tools supplied with this request are real, locally executable capabilities, not examples.
      Active workspace: \(configuration.workspacePath)
      Available tools: \(toolNames)
      Permission mode: \(configuration.permissionMode.displayName)

      Mandatory behavior:
      - When the user requests repository inspection, file access, Git status/diff, command execution, or file modification, call the appropriate tools before answering.
      - Never claim that you lack physical, virtual, server, filesystem, terminal, or repository access while relevant tools are supplied.
      - Never invent host names, operating systems, repository contents, project descriptions, or command results.
      - Use relative paths against the active workspace unless an absolute path is explicitly necessary.
      - Inspect first, then reason from actual tool output, and report failures accurately.
      - Do not describe AgenTM5N from generic model knowledge when its repository can be inspected with tools.
      """

    guard let first = messages.first, first.role == .system else {
      return [ProviderMessage(role: .system, content: runtimeContext)] + messages
    }

    var enriched = [
      ProviderMessage(
        role: .system,
        content: first.content + "\n\n" + runtimeContext
      )
    ]
    enriched.append(contentsOf: messages.dropFirst())
    return enriched
  }

  private func looksLikeCapabilityDenial(_ content: String) -> Bool {
    let normalized = content.lowercased()
    let indicators = [
      "keinen physischen oder virtuellen zugriff",
      "keine direkten befehle",
      "keinen zugriff darauf",
      "keine dateien auf dem server lesen",
      "keine berechtigungen",
      "keine zugriffsrechte",
      "i cannot execute",
      "i can't execute",
      "i do not have access",
      "i don't have access",
      "no physical or virtual access",
    ]
    return indicators.contains { normalized.contains($0) }
  }

  private func endpointURL(baseURL: String, path: String) throws -> URL {
    guard var components = URLComponents(string: baseURL) else {
      throw OllamaProviderError.invalidBaseURL(baseURL)
    }
    let normalizedBasePath = components.path.trimmingCharacters(
      in: CharacterSet(charactersIn: "/")
    )
    let normalizedEndpointPath = path.trimmingCharacters(
      in: CharacterSet(charactersIn: "/")
    )
    components.path =
      "/"
      + [normalizedBasePath, normalizedEndpointPath]
      .filter { !$0.isEmpty }
      .joined(separator: "/")

    guard let url = components.url else {
      throw OllamaProviderError.invalidBaseURL(baseURL)
    }
    return url
  }

  private func applyAuthorization(apiKey: String?, to request: inout URLRequest) {
    guard let apiKey, !apiKey.isEmpty else { return }
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
  }

  private func validate(response: URLResponse, body: Data) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw OllamaProviderError.invalidHTTPResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let text = String(data: body, encoding: .utf8) ?? "Keine Fehlerdetails"
      throw OllamaProviderError.httpError(
        statusCode: httpResponse.statusCode,
        body: text
      )
    }
  }
}
