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
      return L10n.text(
        de: "Die Ollama-Basis-URL ist ungültig: \(value)",
        en: "The Ollama base URL is invalid: \(value)",
        fr: "L’URL de base Ollama n’est pas valide : \(value)"
      )
    case .invalidHTTPResponse:
      return L10n.text(
        de: "Ollama hat keine gültige HTTP-Antwort geliefert.",
        en: "Ollama did not return a valid HTTP response.",
        fr: "Ollama n’a pas renvoyé de réponse HTTP valide."
      )
    case .httpError(let statusCode, let body):
      return "Ollama HTTP \(statusCode): \(body)"
    case .malformedStreamLine(let line):
      return L10n.text(
        de: "Eine Ollama-Streaming-Zeile konnte nicht verarbeitet werden: \(line)",
        en: "An Ollama streaming line could not be processed: \(line)",
        fr: "Une ligne de streaming Ollama n’a pas pu être traitée : \(line)"
      )
    case .emptyModel:
      return L10n.text(
        de: "Es wurde kein Ollama-Modell angegeben.",
        en: "No Ollama model was specified.",
        fr: "Aucun modèle Ollama n’a été indiqué."
      )
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
            let bodyText = String(data: errorData, encoding: .utf8)
              ?? L10n.text(
                de: "Keine Fehlerdetails",
                en: "No error details",
                fr: "Aucun détail d’erreur"
              )
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
            let diagnostic = L10n.text(
              de: """

                ---
                **AgenTM5N-Diagnose:** Das Modell `\(configuration.model)` hat die bereitgestellten lokalen Werkzeuge ignoriert und stattdessen fehlenden Zugriff behauptet. Wähle ein Tool-Calling-fähiges Ollama-Modell, prüfe den Agent-Status und starte eine neue Sitzung. Der konfigurierte Workspace ist `\(configuration.workspacePath)`.
                """,
              en: """

                ---
                **AgenTM5N diagnosis:** Model `\(configuration.model)` ignored the supplied local tools and claimed that access was unavailable. Select an Ollama model with tool-calling support, verify the agent status, and start a new session. The configured workspace is `\(configuration.workspacePath)`.
                """,
              fr: """

                ---
                **Diagnostic AgenTM5N :** Le modèle `\(configuration.model)` a ignoré les outils locaux fournis et a prétendu ne pas disposer d’un accès. Sélectionnez un modèle Ollama compatible avec les appels d’outils, vérifiez l’état de l’agent et démarrez une nouvelle session. L’espace de travail configuré est `\(configuration.workspacePath)`.
                """
            )
            continuation.yield(
              ProviderStreamEvent(
                contentDelta: diagnostic,
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
    let language = SystemLanguage.current
    var contextSections = [language.agentInstruction]

    if !tools.isEmpty {
      let toolNames = tools.map(\.function.name).joined(separator: ", ")
      let toolContext: String

      switch language.code {
      case "de":
        toolContext = """
          Du bist AgenTM5N und läufst in einer nativen macOS-Anwendung auf dem aktuellen Mac des Benutzers.
          Die mit diesem Request bereitgestellten Funktionswerkzeuge sind reale, lokal ausführbare Fähigkeiten und keine Beispiele.
          Aktiver Workspace: \(configuration.workspacePath)
          Verfügbare Werkzeuge: \(toolNames)
          Berechtigungsmodus: \(configuration.permissionMode.displayName)

          Verbindliches Verhalten:
          - Wenn der Benutzer Repository-Prüfung, Dateizugriff, Git-Status oder -Diff, Befehlsausführung, SSH-Aktionen oder Dateiänderungen verlangt, rufe vor der Antwort die passenden Werkzeuge auf.
          - Behaupte niemals fehlenden physischen, virtuellen, Server-, Datei-, Terminal- oder Repository-Zugriff, solange passende Werkzeuge bereitgestellt werden.
          - Erfinde keine Hostnamen, Betriebssysteme, Repository-Inhalte, Projektbeschreibungen oder Kommandoergebnisse.
          - Verwende relative Pfade gegen den aktiven Workspace, sofern kein absoluter Pfad ausdrücklich erforderlich ist.
          - Prüfe zuerst mit Werkzeugen, leite Aussagen aus den tatsächlichen Ergebnissen ab und melde Fehler exakt.
          - Beschreibe AgenTM5N nicht aus allgemeinem Modellwissen, wenn das Repository mit Werkzeugen geprüft werden kann.
          """
      case "fr":
        toolContext = """
          Tu es AgenTM5N, exécuté dans une application macOS native sur le Mac actuel de l’utilisateur.
          Les outils de fonction fournis avec cette requête sont des capacités réelles exécutables localement, et non des exemples.
          Espace de travail actif : \(configuration.workspacePath)
          Outils disponibles : \(toolNames)
          Mode d’autorisation : \(configuration.permissionMode.displayName)

          Comportement obligatoire :
          - Lorsque l’utilisateur demande une inspection du dépôt, un accès aux fichiers, un statut ou diff Git, l’exécution de commandes, une action SSH ou une modification de fichier, appelle les outils appropriés avant de répondre.
          - Ne prétends jamais manquer d’accès physique, virtuel, serveur, système de fichiers, terminal ou dépôt lorsque les outils correspondants sont fournis.
          - N’invente aucun nom d’hôte, système d’exploitation, contenu de dépôt, description de projet ou résultat de commande.
          - Utilise des chemins relatifs à l’espace de travail actif, sauf nécessité explicite d’un chemin absolu.
          - Inspecte d’abord, raisonne à partir des résultats réels et signale précisément les erreurs.
          """
      default:
        toolContext = """
          You are AgenTM5N running inside a native macOS application on the user's current Mac.
          The function tools supplied with this request are real, locally executable capabilities, not examples.
          Active workspace: \(configuration.workspacePath)
          Available tools: \(toolNames)
          Permission mode: \(configuration.permissionMode.displayName)

          Mandatory behavior:
          - When the user requests repository inspection, file access, Git status or diff, command execution, SSH actions, or file modification, call the appropriate tools before answering.
          - Never claim that physical, virtual, server, filesystem, terminal, or repository access is unavailable while relevant tools are supplied.
          - Never invent host names, operating systems, repository contents, project descriptions, or command results.
          - Use relative paths against the active workspace unless an absolute path is explicitly necessary.
          - Inspect first, reason from actual tool output, and report failures accurately.
          """
      }

      contextSections.append(toolContext)
    }

    let runtimeContext = contextSections.joined(separator: "\n\n")
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
      "je ne peux pas exécuter",
      "je n’ai pas accès",
      "je n'ai pas accès",
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
      let text = String(data: body, encoding: .utf8)
        ?? L10n.text(
          de: "Keine Fehlerdetails",
          en: "No error details",
          fr: "Aucun détail d’erreur"
        )
      throw OllamaProviderError.httpError(
        statusCode: httpResponse.statusCode,
        body: text
      )
    }
  }
}
