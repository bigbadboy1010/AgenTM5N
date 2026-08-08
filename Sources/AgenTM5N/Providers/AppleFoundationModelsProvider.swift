import Foundation
import FoundationModels

public enum AppleFoundationModelsProviderError: LocalizedError {
  case unavailable(String)
  case toolsDisabled
  case generationFailure(String)

  public var errorDescription: String? {
    switch self {
    case .unavailable(let reason):
      return L10n.text(
        de: "Apple Foundation Models ist nicht verfügbar: \(reason)",
        en: "Apple Foundation Models is unavailable: \(reason)",
        fr: "Apple Foundation Models n’est pas disponible : \(reason)"
      )
    case .toolsDisabled:
      return L10n.text(
        de: "Die AgenTM5N-Werkzeuge sind deaktiviert. Aktiviere den Agent-Modus in den Einstellungen und versuche die Anfrage erneut.",
        en: "AgenTM5N tools are disabled. Enable Agent mode in Settings and retry the request.",
        fr: "Les outils AgenTM5N sont désactivés. Activez le mode Agent dans les réglages puis réessayez."
      )
    case .generationFailure(let details):
      return L10n.text(
        de: "Apple Foundation Models Fehler: \(details)",
        en: "Apple Foundation Models error: \(details)",
        fr: "Erreur Apple Foundation Models : \(details)"
      )
    }
  }
}

public actor AppleFoundationModelsProvider {
  private let model = SystemLanguageModel.default
  private static let maximumConversationCharacters = 5_000

  public init() {}

  public func availabilityDescription() -> String {
    switch model.availability {
    case .available:
      return L10n.text(de: "Verfügbar", en: "Available", fr: "Disponible")
    case .unavailable(let reason):
      return L10n.text(
        de: "Nicht verfügbar: \(String(describing: reason))",
        en: "Unavailable: \(String(describing: reason))",
        fr: "Indisponible : \(String(describing: reason))"
      )
    }
  }

  public func complete(
    configuration: AppConfiguration,
    messages: [ChatMessage]
  ) async throws -> ProviderStreamEvent {
    switch model.availability {
    case .available:
      break
    case .unavailable(let reason):
      throw AppleFoundationModelsProviderError.unavailable(String(describing: reason))
    }

    let temporalContext = AgentRuntimeContext.currentTemporalContext()
    let selection = Self.toolSelection(for: messages)

    if selection.focused != nil, !configuration.agentEnabled {
      throw AppleFoundationModelsProviderError.toolsDisabled
    }

    let instructions: String
    if let focused = selection.focused {
      instructions = Self.focusedInstructions(
        focused,
        temporalContext: temporalContext
      )
    } else {
      instructions = configuration.systemPrompt
        + "\n\n"
        + SystemLanguage.current.agentInstruction
        + "\n\n"
        + AgentRuntimeContext.providerInstruction()
        + "\n\n"
        + temporalContext
        + "\n\n"
        + Self.toolInstructions(selection: selection)
    }

    var tools: [any Tool] = []
    if let focused = selection.focused {
      tools.append(contentsOf: Self.focusedTools(focused))
    } else {
      tools.append(SystemCurrentDateTimeTool())
      if configuration.agentEnabled {
        if selection.macNative {
          tools.append(contentsOf: AppleRoutedMacNativeTools.makeTools())
        }
        if selection.persistentAgents {
          tools.append(contentsOf: AppleRoutedPersistentAgentTools.makeTools())
        }
      }
    }

    let session = LanguageModelSession(model: model, tools: tools) {
      instructions
    }

    let prompt: String
    if selection.focused != nil {
      prompt = Self.latestUserPrompt(messages: messages)
    } else {
      prompt = Self.makePrompt(messages: messages)
        + "\n\nAUTHORITATIVE RUNTIME CONTEXT FOR THIS TURN:\n"
        + temporalContext
    }

    let clock = ContinuousClock()
    let startedAt = clock.now

    do {
      let response = try await session.respond(to: prompt)
      let duration = startedAt.duration(to: clock.now)
      return ProviderStreamEvent(
        contentDelta: response.content,
        thinkingDelta: "",
        isFinished: true,
        metrics: ChatMetrics(
          totalDurationNanoseconds: Self.nanoseconds(from: duration)
        )
      )
    } catch {
      throw AppleFoundationModelsProviderError.generationFailure(
        Self.describeFoundationModelError(error)
      )
    }
  }

  private enum SSHMode {
    case list
    case run
    case terminal
    case upload
    case download
    case tail
    case batch
  }

  private enum FocusedToolPack {
    case ssh(SSHMode)
    case http
    case system
    case macUtilities
    case reminders
    case delegation
    case workflows
    case updates
    case git
    case workspaceRead
    case workspaceEdit
    case localCommand
    case memory
    case context
    case knowledge
    case attachments
    case documents
    case coreML
  }

  private struct ToolSelection {
    var macNative: Bool
    var persistentAgents: Bool
    var focused: FocusedToolPack?
  }

  private static func focusedTools(_ pack: FocusedToolPack) -> [any Tool] {
    switch pack {
    case .ssh(let mode):
      switch mode {
      case .list: AppleRoutedSSHTools.makeListHostsTools()
      case .run: AppleRoutedSSHTools.makeRunTools()
      case .terminal: AppleRoutedSSHTools.makeOpenTerminalTools()
      case .upload: AppleRoutedSSHTools.makeUploadTools()
      case .download: AppleRoutedSSHTools.makeDownloadTools()
      case .tail: AppleRoutedSSHTools.makeTailTools()
      case .batch: AppleRoutedSSHTools.makeBatchTools()
      }
    case .http:
      AppleRoutedPlatformExpansionTools.makeHTTPTools()
    case .system:
      AppleRoutedPlatformExpansionTools.makeSystemTools()
    case .macUtilities:
      AppleRoutedPlatformExpansionTools.makeMacUtilityTools()
    case .reminders:
      [SystemCurrentDateTimeTool()]
        + AppleRoutedPlatformExpansionTools.makeReminderTools()
    case .delegation:
      AppleRoutedPlatformExpansionTools.makeDelegationTools()
    case .workflows:
      AppleRoutedPlatformExpansionTools.makeWorkflowTools()
    case .updates:
      AppleRoutedPlatformExpansionTools.makeUpdateTools()
    case .git:
      AppleRoutedOperationalTools.makeGitTools()
    case .workspaceRead:
      AppleRoutedOperationalTools.makeWorkspaceReadTools()
    case .workspaceEdit:
      AppleRoutedOperationalTools.makeWorkspaceEditTools()
    case .localCommand:
      AppleRoutedOperationalTools.makeLocalCommandTools()
    case .memory:
      AppleRoutedKnowledgeMemoryTools.makeMemoryTools()
    case .context:
      AppleRoutedKnowledgeMemoryTools.makeContextTools()
    case .knowledge:
      AppleRoutedKnowledgeMemoryTools.makeKnowledgeTools()
    case .attachments:
      AppleRoutedKnowledgeMemoryTools.makeAttachmentTools()
    case .documents:
      AppleRoutedKnowledgeMemoryTools.makeDocumentTools()
    case .coreML:
      AppleRoutedKnowledgeMemoryTools.makeCoreMLTools()
    }
  }

  private static func toolSelection(for messages: [ChatMessage]) -> ToolSelection {
    let text = messages
      .last(where: { $0.role == .user })?
      .content
      .lowercased() ?? ""

    let sshTerms = [
      "ssh", "server", "remote", "docker", "container", "systemctl", "journalctl",
      "linux", "photon", "redhat", "red hat", "ubuntu", "kubernetes", "openshift",
      "remote host", "remote-host",
    ]
    if sshTerms.contains(where: { text.contains($0) }) {
      return .init(
        macNative: false,
        persistentAgents: false,
        focused: .ssh(sshMode(for: text))
      )
    }

    if containsAny(text, [
      "http://", "https://", " api ", "rest api", "endpoint", "webhook", "bearer",
      "api key", "api-key", "secret_ref", "secret verwenden", "secret benutzen",
      "secrets anzeigen", "secret-label", "secret label",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .http)
    }

    if containsAny(text, [
      "core ml", "coreml", "mlmodel", "mlpackage", "neural-engine-modell",
      "neural engine modell", "core ml modell", "core ml vorhersage", "coreml prediction",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .coreML)
    }

    if containsAny(text, [
      "workspace memory", "workspace-gedächtnis", "workspace gedächtnis",
      "workspace-gedaechtnis", "semantic search", "semantische suche", "embedding",
      "embeddings", "vektorsuche", "vector search", "semantischer index",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .memory)
    }

    if containsAny(text, [
      "kontextsuche", "kontext suche", "context search", "context_search",
      "über alle quellen", "ueber alle quellen", "anhänge und wissen",
      "anhaenge und wissen", "attachments und knowledge",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .context)
    }

    if containsAny(text, [
      "wissensbibliothek", "knowledge library", "knowledge-base", "knowledge base",
      "knowledge_search", "wissenssammlung", "wissensdokument",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .knowledge)
    }

    if containsAny(text, [
      "anhang", "anhänge", "anhaenge", "attachment", "attachments",
      "angehängte datei", "angehaengte datei", "beigefügte datei", "beigefuegte datei",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .attachments)
    }

    if containsAny(text, [
      "document studio", "dokument erstellen", "dokument generieren", "dokument erzeugen",
      "docx", "xlsx", "pptx", "powerpoint", "word dokument", "word-datei", "word datei",
      "excel dokument", "excel-datei", "excel datei", "als pdf", "pdf erstellen",
      "pdf generieren", "generiertes dokument",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .documents)
    }

    if containsAny(text, [
      "erinnerung", "erinnerungen", "reminder", "reminders", "todo", "to-do",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .reminders)
    }

    if containsAny(text, [
      "delegiere", "delegieren", "delegate", "übertrage an den agent",
      "uebertrage an den agent", "lass den agent", "spezialist übernehmen",
      "spezialist uebernehmen",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .delegation)
    }

    if containsAny(text, [
      "workflow", "workflows", "arbeitsablauf", "ablauf speichern",
      "ablauf ausführen", "ablauf ausfuehren",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .workflows)
    }

    if containsAny(text, [
      "app update", "update prüfen", "update pruefen", "neue version", "app version",
      "version von agentm5n", "versionsnummer",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .updates)
    }

    if containsAny(text, [
      "systeminfo", "system info", "systemstatus", "prozesse", "process list",
      "cpu prozess", "festplatte", "disk info", "speicherplatz", "netzwerkinfo",
      "network info", "netzwerkschnittstelle",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .system)
    }

    if containsAny(text, [
      "zwischenablage", "clipboard", "benachrichtigung", "notification",
      "kurzbefehl", "shortcut", "shortcuts",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .macUtilities)
    }

    if containsAny(text, [
      "git status", "git diff", "git branch", "git checkout", "git commit",
      "repository", "repo status",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .git)
    }

    if containsAny(text, [
      "lokales terminal", "local terminal", "lokaler befehl", "local command",
      "shell command", "führe lokal", "fuehre lokal",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .localCommand)
    }

    if containsAny(text, [
      "datei ändern", "datei aendern", "datei bearbeiten", "datei schreiben",
      "write file", "edit file", "apply patch", "patch datei", "ersetze in der datei",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .workspaceEdit)
    }

    if containsAny(text, [
      "workspace", "datei lesen", "read file", "suche in dateien", "search files",
      "swift-dateien", "swift dateien", "ordner auflisten", "list files", "glob",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .workspaceRead)
    }

    let macTerms = [
      "calendar", "kalender", "termin", "event", "contact", "kontakt", "address book",
      "adressbuch", "mail", "email", "e-mail", "nachricht", "inbox", "posteingang",
    ]
    let agentTerms = [
      "agent erstellen", "agent anlegen", "agent speichern", "agent ändern",
      "agent aktualisieren", "agent löschen", "agent auflisten", "agenten",
      "gespeicherter agent", "gespeicherte agent", "specialist", "spezialist",
    ]

    let macNative = macTerms.contains { text.contains($0) }
    let persistentAgents = agentTerms.contains { text.contains($0) }
    if !macNative && !persistentAgents {
      return .init(macNative: true, persistentAgents: true, focused: nil)
    }
    return .init(
      macNative: macNative,
      persistentAgents: persistentAgents,
      focused: nil
    )
  }

  private static func sshMode(for text: String) -> SSHMode {
    if containsAny(text, ["hochladen", "upload", "scp upload"]) { return .upload }
    if containsAny(text, ["herunterladen", "download", "scp download"]) { return .download }
    if containsAny(text, [
      "tail -", "tail log", "logdatei", "log file", "letzten zeilen", "last lines",
    ]) { return .tail }
    if containsAny(text, [
      "batch", "health check", "healthcheck", "server check", "mehrere befehle",
      "mehrere commands", "diagnose-batch",
    ]) { return .batch }
    if containsAny(text, [
      "interaktiv", "interactive", "terminal öffnen", "terminal oeffnen",
      "open terminal", "ssh terminal", "shell öffnen", "shell oeffnen",
    ]) { return .terminal }
    let runTerms = [
      "führe", "ausführen", "ausfuehren", "befehl", "kommando", "command", "docker",
      "systemctl", "journalctl", "whoami", "hostname", "uname", "df ", "free ",
      "ps ", "top", "uptime", "kubectl", "oc ",
    ]
    return runTerms.contains(where: { text.contains($0) }) ? .run : .list
  }

  private static func focusedInstructions(
    _ pack: FocusedToolPack,
    temporalContext: String
  ) -> String {
    var lines = [
      "You are AgenTM5N running with the Apple on-device language model.",
      "Respond in the user's language.",
      "Use the small focused AgenTM5N tool set provided for this request instead of claiming that you lack access.",
      "Report success or failure only from actual tool results.",
      "Never ask for, expose, repeat, or infer passwords, private keys, passphrases, API keys, tokens, secret values, or internal secret identifiers.",
    ]

    switch pack {
    case .ssh(let mode):
      lines.append("AgenTM5N resolves SSH credentials internally from saved profiles and the encrypted Vault.")
      if mode == .run {
        lines.append("If the user requested multiple remote commands, preserve every command and pass all commands together in one ssh_run command string, in the same order.")
      }
      if mode == .batch {
        lines.append("For a diagnostic batch, put every requested remote command on its own line in the ssh_run_batch commands argument.")
      }
    case .http:
      lines.append("Use secret_list only to discover Vault labels/kinds. Use secret_ref by label with http_request; secret values remain native and model-invisible.")
    case .reminders:
      lines.append("The authoritative current Mac date/time is: \(temporalContext)")
      lines.append("Use ISO-8601 for reminder due dates and preserve the user's local wall-clock intent.")
    case .delegation:
      lines.append("Delegate only a bounded subtask to the requested saved specialist. Keep the main conversation responsible for the final synthesis.")
    case .workflows:
      lines.append("Workflows store tool names and arguments. Never put secret values into workflow steps; use secret_ref labels only.")
    case .updates:
      lines.append("Update checks are read-only checks against a user-provided HTTPS manifest and never install automatically.")
    case .workspaceEdit:
      lines.append("Read the target before modifying it. Prefer apply_patch for targeted edits.")
    case .memory:
      lines.append("Prefer workspace_semantic_search for meaning-based retrieval. If an embedding model is configured, query embeddings are computed locally through Core ML with CPU + Apple Neural Engine policy.")
    case .context:
      lines.append("Use context_search before context_read_source. Keep source IDs exact and preserve source locators in the answer.")
    case .knowledge:
      lines.append("Use knowledge_search before reading a source. Imported files must stay inside the configured workspace.")
    case .attachments:
      lines.append("Use attachment_search or attachment_list before reading a bounded attachment section. Do not invent attachment content.")
    case .documents:
      lines.append("Use document_generate for DOCX, PDF, XLSX, or PPTX requests. AgenTM5N presents a native macOS Save dialog immediately after generation so the user can choose where to save/download the file. Internal managed paths remain hidden.")
    case .coreML:
      lines.append("Use coreml_describe_model before coreml_predict when input names or shapes are not known. Core ML runs locally and may use CPU + Apple Neural Engine according to the registered model policy.")
    default:
      break
    }
    return lines.joined(separator: "\n")
  }

  private static func toolInstructions(selection: ToolSelection) -> String {
    var sections: [String] = [
      """
      TOOL RULES — mandatory:
      - Only report that a native action failed when the corresponding tool actually returns an error.
      - Tool execution remains subject to AgenTM5N permission approval, audit records, workspace boundaries, and macOS security controls.
      """
    ]

    if selection.macNative {
      sections.append(
        """
        CALENDAR GROUNDING RULES:
        - The CURRENT MAC DATE AND TIME above is authoritative.
        - Calendar event results are records, not a clock.
        - EventKit can store events in the past and in the future. Do not invent a future-only rule.
        - If date interpretation is ambiguous, call system_current_datetime first.
        - For calendar_create_event, pass requested local calendar components directly. Do not convert the user's wall-clock time to UTC yourself.
        """
      )
    }

    if selection.persistentAgents {
      sections.append(
        """
        PERSISTENT AGENT RULES:
        - Use agent_* tools when the user explicitly asks to create, save, update, list, inspect, or delete a reusable specialist agent.
        - Never place passwords, API keys, tokens, private keys, or other secrets inside saved agent instructions.
        """
      )
    }

    return sections.joined(separator: "\n\n")
  }

  private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
    terms.contains { text.contains($0) }
  }

  private static func latestUserPrompt(messages: [ChatMessage]) -> String {
    let text = messages
      .last(where: { $0.role == .user })?
      .content
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return String(text.prefix(2_500))
  }

  private static func makePrompt(messages: [ChatMessage]) -> String {
    let rendered = messages
      .filter { $0.role != .system }
      .suffix(6)
      .map { message in
        let role = switch message.role {
        case .system: "SYSTEM"
        case .user: "USER"
        case .assistant: "ASSISTANT"
        }
        return "\(role):\n\(message.content)"
      }
      .joined(separator: "\n\n")

    guard rendered.count > maximumConversationCharacters else {
      return rendered
    }
    return "[Earlier conversation omitted for Apple on-device context budget]\n\n"
      + String(rendered.suffix(maximumConversationCharacters))
  }

  private static func describeFoundationModelError(_ error: any Error) -> String {
    let nsError = error as NSError
    var parts: [String] = [
      "type=\(String(reflecting: type(of: error)))",
      "debug=\(String(reflecting: error))",
      "NSError=\(nsError.domain)(\(nsError.code))",
    ]
    if !nsError.localizedDescription.isEmpty {
      parts.append("description=\(nsError.localizedDescription)")
    }
    if let reason = nsError.localizedFailureReason, !reason.isEmpty {
      parts.append("failureReason=\(reason)")
    }
    if let suggestion = nsError.localizedRecoverySuggestion, !suggestion.isEmpty {
      parts.append("recoverySuggestion=\(suggestion)")
    }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
      parts.append(
        "underlying=\(underlying.domain)(\(underlying.code)): \(underlying.localizedDescription)"
      )
    }
    return parts.joined(separator: " | ")
  }

  private static func nanoseconds(from duration: Duration) -> UInt64 {
    let components = duration.components
    let seconds = max(components.seconds, 0)
    let attoseconds = max(components.attoseconds, 0)
    return UInt64(seconds) * 1_000_000_000
      + UInt64(attoseconds / 1_000_000_000)
  }
}

private struct SystemCurrentDateTimeTool: Tool {
  let name = "system_current_datetime"
  let description = "Return the authoritative current Mac date, local time, time zone, and UTC offset."

  @Generable
  struct Arguments {
    @Guide(description: "Use current") var query: String
  }

  func call(arguments: Arguments) async throws -> String {
    AgentRuntimeContext.currentTemporalContext()
  }
}
