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
    let messages: [OllamaRequestMessage]
    let tools: [ProviderToolDefinition]?
    let stream: Bool
    let think: JSONValue
    let options: [String: JSONValue]
    let keepAlive: String

    private enum CodingKeys: String, CodingKey {
      case model
      case messages
      case tools
      case stream
      case think
      case options
      case keepAlive = "keep_alive"
    }
  }

  private struct OllamaRequestMessage: Encodable {
    let role: ProviderMessageRole
    let content: String
    let thinking: String?
    let toolCalls: [ProviderToolCall]?
    let toolName: String?
    let images: [String]?

    init(_ message: ProviderMessage) throws {
      role = message.role
      content = PromptAttachmentService.providerPrompt(from: message.content)
      thinking = message.thinking
      toolCalls = message.toolCalls
      toolName = message.toolName

      let references = PromptAttachmentService.imageReferences(
        from: message.content
      )
      images = references.isEmpty
        ? nil
        : try references.map { reference in
          try PromptImageAttachmentStorage.data(for: reference)
            .base64EncodedString()
        }
    }

    private enum CodingKeys: String, CodingKey {
      case role
      case content
      case thinking
      case toolCalls = "tool_calls"
      case toolName = "tool_name"
      case images
    }
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

  private struct ShowRequest: Encodable {
    let model: String
    let verbose = false
  }

  private struct ShowResponse: Decodable {
    let capabilities: [String]?
  }

  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func listModels(
    configuration: AppConfiguration,
    apiKey: String?
  ) async throws -> [String] {
    if shouldUseMLX(configuration) {
      return try await MLXProvider(session: session).listModels(
        configuration: configuration,
        apiKey: apiKey
      )
    }

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

  public func modelCapabilities(
    configuration: AppConfiguration,
    apiKey: String?
  ) async throws -> Set<String> {
    if shouldUseMLX(configuration) {
      // The MLX HTTP server is text-only at the request surface used by
      // AgenTM5N. Tool support is model/template dependent and is handled by
      // the server; returning no vision capability keeps image validation safe.
      return []
    }

    let model = configuration.model.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !model.isEmpty else {
      throw OllamaProviderError.emptyModel
    }

    let url = try endpointURL(
      baseURL: configuration.baseURL,
      path: "/api/show"
    )
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    applyAuthorization(apiKey: apiKey, to: &request)
    request.httpBody = try JSONEncoder().encode(ShowRequest(model: model))

    let (data, response) = try await session.data(for: request)
    try validate(response: response, body: data)
    let decoded = try JSONDecoder().decode(ShowResponse.self, from: data)
    return Set((decoded.capabilities ?? []).map { $0.lowercased() })
  }

  public func streamChat(
    configuration: AppConfiguration,
    apiKey: String?,
    messages: [ProviderMessage],
    tools: [ProviderToolDefinition] = []
  ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
    if shouldUseMLX(configuration) {
      return MLXProvider(session: session).streamChat(
        configuration: configuration,
        apiKey: apiKey,
        messages: messages,
        tools: tools
      )
    }

    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OllamaProviderError.emptyModel
          }

          var operatingConfiguration = AgentOperatingLayerStore.load()
          operatingConfiguration.normalize()
          if operatingConfiguration.bundledToolsEnabled {
            BundledToolPackInstaller.ensureInstalled()
          }

          let effectiveTools = scopedTools(
            tools,
            messages: messages,
            operatingConfiguration: operatingConfiguration
          )
          let url = try endpointURL(baseURL: configuration.baseURL, path: "/api/chat")
          var request = URLRequest(url: url)
          request.httpMethod = "POST"
          request.timeoutInterval = TimeInterval(operatingConfiguration.requestTimeoutSeconds)
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
          applyAuthorization(apiKey: apiKey, to: &request)

          let providerMessages = enrichedMessages(
            messages,
            configuration: configuration,
            tools: effectiveTools
          )
          let requestMessages = try providerMessages.map(
            OllamaRequestMessage.init
          )
          let body = ChatRequestBody(
            model: configuration.model,
            messages: requestMessages,
            tools: effectiveTools.isEmpty ? nil : effectiveTools,
            stream: true,
            think: operatingConfiguration.ollamaThinkValue(
              legacyThinkingEnabled: configuration.thinkingEnabled
            ),
            options: operatingConfiguration.ollamaOptions,
            keepAlive: operatingConfiguration.keepAlive
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

          if !effectiveTools.isEmpty,
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

  private func shouldUseMLX(_ configuration: AppConfiguration) -> Bool {
    configuration.providerKind == .ollamaLocal
      && AgentOperatingLayerStore.load().localInferenceRuntime == .mlxServer
  }

  private func scopedTools(
    _ tools: [ProviderToolDefinition],
    messages: [ProviderMessage],
    operatingConfiguration: AgentOperatingLayerConfiguration
  ) -> [ProviderToolDefinition] {
    guard !tools.isEmpty else { return [] }

    let configuredCapabilities = operatingConfiguration.enabledCapabilities
    let specialistCapabilities = specialistCapabilityScope(messages: messages)
    let allowedCapabilities: Set<AgentToolCapability>
    if let specialistCapabilities {
      allowedCapabilities = configuredCapabilities.intersection(specialistCapabilities)
    } else {
      allowedCapabilities = configuredCapabilities
    }

    var candidates = tools.filter { definition in
      guard let entry = AgentToolRegistry.entry(named: definition.function.name) else {
        return false
      }
      guard allowedCapabilities.contains(entry.capability) else {
        return false
      }
      if !operatingConfiguration.bundledToolsEnabled,
        BundledToolPackInstaller.isBundledToolName(definition.function.name)
      {
        return false
      }
      return true
    }

    switch operatingConfiguration.toolSelectionMode {
    case .all, .capabilityFiltered:
      return candidates

    case .adaptive:
      let prompt = latestUserPrompt(messages: messages)
      let adaptiveCapabilities = adaptiveCapabilityScope(for: prompt)
        .intersection(allowedCapabilities)
      candidates = candidates.filter { definition in
        guard let entry = AgentToolRegistry.entry(named: definition.function.name) else {
          return false
        }
        return adaptiveCapabilities.contains(entry.capability)
      }
      candidates.sort { lhs, rhs in
        let left = adaptiveToolPriority(lhs.function.name, prompt: prompt)
        let right = adaptiveToolPriority(rhs.function.name, prompt: prompt)
        if left != right { return left < right }
        return lhs.function.name.localizedCaseInsensitiveCompare(rhs.function.name)
          == .orderedAscending
      }
      return Array(candidates.prefix(operatingConfiguration.maxAdvertisedTools))
    }
  }

  private func specialistCapabilityScope(
    messages: [ProviderMessage]
  ) -> Set<AgentToolCapability>? {
    guard
      let systemContent = messages.first(where: { $0.role == .system })?.content,
      let capabilityLine = systemContent
        .split(whereSeparator: { $0.isNewline })
        .map(String.init)
        .first(where: {
          $0.trimmingCharacters(in: .whitespaces)
            .hasPrefix("- Tool capabilities:")
        })
    else {
      return nil
    }

    let marker = "- Tool capabilities:"
    guard let markerRange = capabilityLine.range(of: marker) else {
      return nil
    }
    let raw = String(capabilityLine[markerRange.upperBound...])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.isEmpty
      || raw.caseInsensitiveCompare("inherit all centrally authorized capabilities") == .orderedSame
      || raw.caseInsensitiveCompare("all") == .orderedSame
    {
      return nil
    }

    let requestedNames = raw
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    return Set(
      requestedNames.compactMap { value in
        AgentToolCapability.allCases.first {
          $0.rawValue.caseInsensitiveCompare(value) == .orderedSame
        }
      }
    )
  }

  private func latestUserPrompt(messages: [ProviderMessage]) -> String {
    messages.last(where: { $0.role == .user })?.content.lowercased() ?? ""
  }

  private func adaptiveCapabilityScope(
    for prompt: String
  ) -> Set<AgentToolCapability> {
    var capabilities: Set<AgentToolCapability> = [
      .workspace,
      .memory,
      .attachments,
      .knowledge,
    ]

    if containsAny(prompt, [
      "code", "source", "repo", "repository", "datei", "file", "patch", "build", "test",
      "swift", "xcode", "npm", "pnpm", "node", "python", "compile", "fehler", "error",
    ]) {
      capabilities.formUnion([.workspace, .git, .terminal, .memory, .documents])
    }
    if containsAny(prompt, ["git", "commit", "branch", "merge", "rebase", "pull", "push", "diff"]) {
      capabilities.formUnion([.git, .workspace, .terminal])
    }
    if containsAny(prompt, ["docker", "container", "compose"]) {
      capabilities.formUnion([.terminal, .system, .workspace, .ssh, .edge])
    }
    if containsAny(prompt, ["podman", "photon", "rhel", "red hat", "linux", "systemctl", "journalctl"]) {
      capabilities.formUnion([.terminal, .system, .ssh, .edge])
    }
    if containsAny(prompt, ["kubernetes", "kubectl", "k8s", "pod", "namespace", "deployment", "statefulset", "daemonset"]) {
      capabilities.formUnion([.terminal, .system, .ssh, .edge, .workspace])
    }
    if containsAny(prompt, ["openshift", " open shift", "oc ", "route", "project"]) {
      capabilities.formUnion([.terminal, .system, .ssh, .edge, .workspace])
    }
    if containsAny(prompt, ["ssh", "server", "remote", "host", "scp", "logfile", "log file"]) {
      capabilities.formUnion([.ssh, .edge, .terminal, .system])
    }
    if containsAny(prompt, ["browser", "webseite", "website", "edge", "tab", "seite öffnen", "open page"]) {
      capabilities.formUnion([.browser, .http])
    }
    if containsAny(prompt, ["http", "https", "api", "rest", "endpoint", "webhook"]) {
      capabilities.formUnion([.http, .secrets])
    }
    if containsAny(prompt, ["kalender", "calendar", "kontakt", "contact", "mail", "email", "e-mail"]) {
      capabilities.insert(.macPersonal)
    }
    if containsAny(prompt, ["reminder", "erinnerung", "erinnerungen"]) {
      capabilities.insert(.reminders)
    }
    if containsAny(prompt, ["core ml", "coreml", "neural engine", "ane", "embedding", "modell", "model"]) {
      capabilities.formUnion([.coreML, .memory])
    }
    if containsAny(prompt, ["pdf", "docx", "xlsx", "pptx", "dokument", "document", "excel", "powerpoint", "word"]) {
      capabilities.formUnion([.documents, .attachments, .knowledge, .memory, .workspace])
    }
    if containsAny(prompt, ["agent", "delegate", "delegiere", "spezialist", "specialist"]) {
      capabilities.formUnion([.agents, .workflows])
    }
    if containsAny(prompt, ["workflow", "ablauf", "pipeline"]) {
      capabilities.formUnion([.workflows, .agents])
    }
    if containsAny(prompt, ["tool", "werkzeug", "toolsmith", "mcp", "model context protocol"]) {
      capabilities.insert(.terminal)
    }
    if containsAny(prompt, ["prozess", "process", "cpu", "memory", "ram", "disk", "network", "netzwerk", "clipboard", "zwischenablage", "shortcut", "finder"]) {
      capabilities.insert(.system)
    }
    if containsAny(prompt, ["version", "update", "release"]) {
      capabilities.insert(.updates)
    }

    return capabilities
  }

  private func adaptiveToolPriority(_ name: String, prompt: String) -> Int {
    let lowerName = name.lowercased()

    let affinityGroups: [(keywords: [String], nameFragments: [String])] = [
      (["kubernetes", "kubectl", "k8s", "pod", "namespace"], ["kube_"]),
      (["openshift", "oc ", "route"], ["builtin_oc_"]),
      (["docker", "compose"], ["docker_"]),
      (["podman"], ["podman_"]),
      (["mcp", "model context protocol"], ["mcp_"]),
      (["dns", "ping", "traceroute", "port", "network", "netzwerk"], ["dns_", "ping", "traceroute", "port_probe"]),
      (["git", "commit", "branch", "pull", "push"], ["git_"]),
      (["archive", "zip", "copy", "move", "checksum", "sha256"], ["fs_", "archive_"]),
    ]

    for group in affinityGroups
    where containsAny(prompt, group.keywords)
      && group.nameFragments.contains(where: { lowerName.contains($0) })
    {
      return 0
    }

    if lowerName == "context_search" || lowerName == "context_read_source" {
      return 1
    }
    if ["read_file", "search_text", "glob_files", "list_directory", "git_status", "git_diff"]
      .contains(lowerName)
    {
      return 2
    }
    if BundledToolPackInstaller.isBundledToolName(lowerName) {
      return 4
    }
    return 3
  }

  private func containsAny(_ text: String, _ needles: [String]) -> Bool {
    needles.contains { text.contains($0) }
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
