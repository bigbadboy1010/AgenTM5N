import Foundation
import FoundationModels

public enum AppleFoundationModelsProviderError: LocalizedError {
  case unavailable(String)
  case toolsDisabled
  case capabilityDenied(String)
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
    case .capabilityDenied(let capability):
      return L10n.text(
        de: "Der gespeicherte Agent ist für die Tool-Capability \(capability) eingeschränkt.",
        en: "The saved agent is restricted from tool capability \(capability).",
        fr: "L’agent enregistré est limité pour la capacité d’outil \(capability)."
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
    let promptCapabilityScope = Self.capabilityScope(from: configuration.systemPrompt)
    let capabilityScope = AgentCapabilityExecutionContext.allowedCapabilities
      ?? promptCapabilityScope

    if selection.focused != nil, !configuration.agentEnabled {
      throw AppleFoundationModelsProviderError.toolsDisabled
    }
    if let focused = selection.focused,
      let requiredCapability = Self.capability(for: focused),
      let capabilityScope,
      !capabilityScope.contains(requiredCapability)
    {
      throw AppleFoundationModelsProviderError.capabilityDenied(
        requiredCapability.rawValue
      )
    }

    let instructions: String
    if let focused = selection.focused {
      instructions = configuration.systemPrompt
        + "\n\n"
        + Self.focusedInstructions(
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
      tools.append(
        contentsOf: Self.focusedTools(
          focused,
          latestUserPrompt: Self.latestUserPrompt(messages: messages)
        )
      )
    } else {
      tools.append(SystemCurrentDateTimeTool())
      if configuration.agentEnabled {
        if selection.macNative,
          Self.isAllowed(.macPersonal, in: capabilityScope)
        {
          tools.append(contentsOf: AppleRoutedMacNativeTools.makeTools())
        }
        if selection.persistentAgents,
          Self.isAllowed(.agents, in: capabilityScope)
        {
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

    let bridgeCapabilityScopeToken: UUID?
    if let capabilityScope {
      bridgeCapabilityScopeToken = await AgentToolExecutionBridge.shared
        .pushCapabilityScope(capabilityScope)
    } else {
      bridgeCapabilityScopeToken = nil
    }

    let clock = ContinuousClock()
    let startedAt = clock.now

    do {
      let responseContent: String
      if #available(macOS 27.0, *), Self.requiresToolCall(selection) {
        let response = try await session.respond(
          to: prompt,
          options: GenerationOptions(toolCallingMode: .required)
        )
        responseContent = response.content
      } else {
        let response = try await session.respond(to: prompt)
        responseContent = response.content
      }

      if let bridgeCapabilityScopeToken {
        await AgentToolExecutionBridge.shared.popCapabilityScope(
          bridgeCapabilityScopeToken
        )
      }

      let duration = startedAt.duration(to: clock.now)
      return ProviderStreamEvent(
        contentDelta: responseContent,
        thinkingDelta: "",
        isFinished: true,
        metrics: ChatMetrics(
          totalDurationNanoseconds: Self.nanoseconds(from: duration)
        )
      )
    } catch {
      if Self.requiresToolCall(selection),
        let toolOutput = AppleRequiredDocumentTools.completionOutput(from: error)
      {
        if let bridgeCapabilityScopeToken {
          await AgentToolExecutionBridge.shared.popCapabilityScope(
            bridgeCapabilityScopeToken
          )
        }
        let duration = startedAt.duration(to: clock.now)
        let succeeded = toolOutput.contains("ready-for-save")
        let content = succeeded
          ? L10n.text(
            de: "Das Dokument wurde erzeugt. AgenTM5N öffnet jetzt den macOS-Speicherdialog. Falls der Dialog nicht im Vordergrund erscheint, verwende unten rechts „Dokument bereit – Speichern…“.",
            en: "The document was generated. AgenTM5N is opening the macOS save dialog now. If the dialog does not appear in front, use ‘Document Ready – Save…’ at the bottom right.",
            fr: "Le document a été généré. AgenTM5N ouvre maintenant la boîte de dialogue d’enregistrement macOS. Si elle n’apparaît pas au premier plan, utilisez « Document prêt – Enregistrer… » en bas à droite."
          )
          : L10n.text(
            de: "Die Dokumenterstellung wurde nicht abgeschlossen: \(toolOutput)",
            en: "Document generation did not complete: \(toolOutput)",
            fr: "La génération du document n’a pas abouti : \(toolOutput)"
          )
        return ProviderStreamEvent(
          contentDelta: content,
          thinkingDelta: "",
          isFinished: true,
          metrics: ChatMetrics(
            totalDurationNanoseconds: Self.nanoseconds(from: duration)
          )
        )
      }

      if let bridgeCapabilityScopeToken {
        await AgentToolExecutionBridge.shared.popCapabilityScope(
          bridgeCapabilityScopeToken
        )
      }

      switch model.availability {
      case .available:
        break
      case .unavailable(let reason):
        throw AppleFoundationModelsProviderError.unavailable(
          String(describing: reason)
        )
      }

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
    case edge
    case browser
    case ssh(SSHMode)
    case http
    case system
    case clipboardRead
    case macUtilities
    case reminders
    case delegation
    case workflows
    case toolsmith
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

  private static func focusedTools(
    _ pack: FocusedToolPack,
    latestUserPrompt: String
  ) -> [any Tool] {
    switch pack {
    case .edge:
      AppleRoutedEdgeTools.makeTools()
    case .browser:
      containsExplicitWebURL(latestUserPrompt)
        ? AppleRoutedBrowserTools.makeTools()
        : AppleRoutedBrowserTools.makeExistingPageTools()
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
    case .clipboardRead:
      AppleRequiredClipboardTools.makeReadTools()
    case .macUtilities:
      AppleRoutedPlatformExpansionTools.makeMacUtilityTools()
    case .reminders:
      [SystemCurrentDateTimeTool()]
        + AppleRoutedPlatformExpansionTools.makeReminderTools()
    case .delegation:
      AppleRoutedPlatformExpansionTools.makeDelegationTools()
    case .workflows:
      AppleRoutedPlatformExpansionTools.makeWorkflowTools()
    case .toolsmith:
      AppleRoutedToolsmithTools.makeTools()
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
      AppleRequiredDocumentTools.makeTools()
    case .coreML:
      AppleRoutedKnowledgeMemoryTools.makeCoreMLTools()
    }
  }

  private static func toolSelection(for messages: [ChatMessage]) -> ToolSelection {
    let text = messages
      .last(where: { $0.role == .user })?
      .content
      .lowercased() ?? ""

    let recentUserText = messages
      .filter { $0.role == .user }
      .suffix(6)
      .map(\.content)
      .joined(separator: "\n")
      .lowercased()

    // Delegation intent must win before inspecting the delegated task itself.
    // Otherwise a request such as "Delegiere ... öffne Microsoft Edge" would
    // incorrectly expose the browser pack to the main agent instead of calling
    // agent_delegate and enforcing the saved specialist's capability sandbox.
    if containsAny(text, [
      "agent_delegate",
      "delegiere",
      "delegieren",
      "delegate",
      "übertrage an den agent",
      "uebertrage an den agent",
      "lass den agent",
      "spezialist übernehmen",
      "spezialist uebernehmen",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .delegation)
    }

    if text.hasPrefix("custom_") || containsAny(text, [
      "toolsmith", "toolsmith_create", "toolsmith_run", "toolsmith_list",
      "toolsmith_get", "toolsmith_delete", "eigenes tool", "eigenes werkzeug",
      "tool erstellen", "tool bauen", "tool generieren", "runtime-tool", "runtime tool",
      "selbst gebautes tool", "selbst erstelltes tool", "custom_",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .toolsmith)
    }

    if containsAny(text, [
      "browser_batch",
      "browser_action",
      "browser_read",
      "browser_open",
      "browser_tabs",
      "browser_session",
    ]) {
      return .init(
        macNative: false,
        persistentAgents: false,
        focused: .browser
      )
    }

    if containsAny(text, [
      "document studio", "dokument erstellen", "dokument generieren", "dokument erzeugen",
      "datei erstellen", "datei generieren", "datei erzeugen", "zum download",
      "docx", "xlsx", "pptx", "powerpoint", "word dokument", "word-datei", "word datei",
      "excel dokument", "excel-datei", "excel datei", "als pdf", "pdf erstellen",
      "pdf generieren", "generiertes dokument",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .documents)
    }

    let browserFollowUp = containsAny(
      recentUserText,
      [
        "microsoft edge",
        "edge browser",
        "edge-browser",
        "browser_open",
        "browser_read",
        "browser_action",
        "browser_batch",
        "browser_tabs",
      ]
    ) && containsAny(
      text,
      [
        "trage",
        "eingeben",
        "eingabe",
        "fülle",
        "fuelle",
        "klicke",
        "wähle",
        "waehle",
        "aktiviere",
        "deaktiviere",
        "checkbox",
        "feld",
        "button",
        "speichern",
        "scroll",
        "lies",
        "lese",
        "zurück",
        "zurueck",
        "vorwärts",
        "vorwaerts",
        "neu laden",
        "reload",
      ]
    )

    if browserFollowUp || containsAny(text, [
      "microsoft edge", "edge browser", "edge-browser", "im browser", "in meinem browser",
      "browser öffnen", "browser oeffnen", "browser steuern", "browser automatisieren",
      "browser automation", "webseite öffnen", "webseite oeffnen", "website öffnen",
      "website oeffnen", "im edge", "in edge", "edge öffnen", "edge oeffnen",
      "klicke im browser", "im browser klicken", "formular im browser", "browser tab",
      "browser-tab", "browse website", "browse webseite",
    ]) {
      return .init(macNative: false, persistentAgents: false, focused: .browser)
    }

    if containsAny(text, [
      "/data/edge", " edge ", "edge-", "edge host", "edge-host", "edge node",
      "edge-node", "edge system", "edge-system", "edge umgebung", "edge-umgebung",
      "edge server", "edge-server", "edge lesen", "edge schreiben", "edge steuern",
      "edge control", "edge read", "edge write",
    ]) || text.hasPrefix("edge ") {
      return .init(macNative: false, persistentAgents: false, focused: .edge)
    }

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

    if containsAny(text, ["zwischenablage", "clipboard"]),
      containsAny(text, [
        "lies", "lese", "lesen", "inhalt", "zeige", "was ist", "read", "show", "inspect",
      ])
    {
      return .init(macNative: false, persistentAgents: false, focused: .clipboardRead)
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
      return .init(macNative: false, persistentAgents: false, focused: nil)
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

  private static func capabilityScope(
    from systemPrompt: String
  ) -> Set<AgentToolCapability>? {
    let marker = "- Tool capabilities:"
    guard let line = systemPrompt
      .split(whereSeparator: \.isNewline)
      .map({ String($0).trimmingCharacters(in: .whitespaces) })
      .last(where: { $0.hasPrefix(marker) })
    else {
      return nil
    }

    let raw = String(line.dropFirst(marker.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.caseInsensitiveCompare("all") == .orderedSame || raw.isEmpty {
      return nil
    }

    let values = raw
      .split(separator: ",")
      .compactMap { piece -> AgentToolCapability? in
        let value = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        return AgentToolCapability.allCases.first {
          $0.rawValue.caseInsensitiveCompare(value) == .orderedSame
        }
      }
    return Set(values)
  }

  private static func capability(
    for pack: FocusedToolPack
  ) -> AgentToolCapability? {
    switch pack {
    case .edge: .edge
    case .browser: .browser
    case .ssh: .ssh
    case .http: .http
    case .system, .clipboardRead, .macUtilities: .system
    case .reminders: .reminders
    case .delegation: .agents
    case .workflows: .workflows
    case .toolsmith: .terminal
    case .updates: .updates
    case .git: .git
    case .workspaceRead, .workspaceEdit: .workspace
    case .localCommand: .terminal
    case .memory, .context: .memory
    case .knowledge: .knowledge
    case .attachments: .attachments
    case .documents: .documents
    case .coreML: .coreML
    }
  }

  private static func isAllowed(
    _ capability: AgentToolCapability,
    in scope: Set<AgentToolCapability>?
  ) -> Bool {
    scope?.contains(capability) ?? true
  }

  private static func requiresToolCall(_ selection: ToolSelection) -> Bool {
    guard let focused = selection.focused else { return false }
    if case .documents = focused { return true }
    if case .clipboardRead = focused { return true }
    if case .edge = focused { return true }
    return false
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
    case .edge:
      lines.append("This is AgenTM5N Edge Control mode. Edge access uses the existing saved SSH profiles and encrypted Vault credentials; do not ask the user for SSH passwords or keys when a saved profile exists.")
      lines.append("Use edge_list_nodes to discover saved Edge-capable hosts, edge_list_directory and edge_read_file for bounded remote reads, edge_write_file for explicit atomic text writes, and edge_control for status, commands, Docker containers, systemd services, and logs.")
      lines.append("For writes, inspect important targets first. edge_write_file creates a backup by default and preserves mode/ownership when possible. Never invent Edge hostnames, paths, container names, service names, or file contents.")
    case .browser:
      lines.append("This is Microsoft Edge Browser Control mode. AgenTM5N controls a visible persistent Microsoft Edge automation profile through the local DevTools Protocol.")
      lines.append("Use browser_open for navigation, browser_read to inspect the actual page and obtain temporary element refs, browser_batch for ordered multi-step interactions, and browser_action only when a single action is sufficient.")
      lines.append("When page structure is not already known from a fresh browser_read result, read the page before clicking or filling. Re-read after navigation or major DOM changes because temporary refs may change.")
      lines.append("When browser_read returns element refs such as b1, b2, or b3, use those refs instead of inventing generic CSS selectors. For a follow-up request without an explicit http:// or https:// URL, stay on the currently selected tab and do not navigate to another website.")
      lines.append("If the user requests two or more browser interactions, use browser_batch and put every requested action into its steps array in the exact requested order.")
      lines.append("Never skip earlier requested form actions and execute only the final click. For example fill + check + select + click must be four ordered browser_batch steps.")
      lines.append("Set readAfter to true when the user asks for the resulting page state or result text.")
      lines.append("Never claim that browser access is unavailable while these tools are present. Never request or expose cookies, localStorage, sessionStorage, authentication tokens, or saved browser passwords. Do not invent page text or interaction results.")
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
    case .clipboardRead:
      lines.append("The user explicitly asked AgenTM5N to read the current macOS clipboard. AgenTM5N DOES have native clipboard access through clipboard_read. You MUST call clipboard_read and base the answer only on its actual output. Do not invent a privacy restriction or claim that the clipboard interface is unavailable.")
    case .reminders:
      lines.append("The authoritative current Mac date/time is: \(temporalContext)")
      lines.append("Use ISO-8601 for reminder due dates and preserve the user's local wall-clock intent.")
    case .delegation:
      lines.append("Delegate only a bounded subtask to the requested saved specialist. Saved specialists inherit the full centrally authorized AgenTM5N tool set by default. Capability restrictions are technical execution boundaries when the saved profile explicitly defines a sandbox.")
      lines.append("The delegated task may mention browser, terminal, SSH, Edge, HTTP, Toolsmith, or other tools. Do not execute those tools as the main agent; call agent_delegate and let the specialist's capability sandbox decide what is allowed.")
    case .workflows:
      lines.append("Workflows store tool names and arguments. Never put secret values into workflow steps; use secret_ref labels only. Workflow steps remain subject to delegated capability boundaries.")
    case .toolsmith:
      lines.append("This is AgenTM5N Toolsmith mode. Use the toolsmith adapter to list, inspect, create, delete, or run persistent custom runtime tools.")
      lines.append("Never place passwords, tokens, API keys, private keys, passphrases, cookies, or other credentials in generated source. Self-built code is execute-risk and remains subject to AgenTM5N approval policy.")
      lines.append("For create, provide complete zsh or python3 source and structured parameter JSON. For run, pass only the custom tool name and non-secret arguments.")
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
      lines.append("AgenTM5N DOES have native file-generation capability. The provided document_generate tool creates the actual DOCX, PDF, XLSX, or PPTX file. You MUST use document_generate for this request. Do not answer that you cannot create files, do not merely provide copyable text, and do not recommend Word or LibreOffice instead. Put the complete requested document into the tool arguments. After the native tool finishes, AgenTM5N handles the macOS save UI.")
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
      - Tool execution remains subject to AgenTM5N permission approval, audit records, workspace boundaries, capability scopes, and macOS security controls.
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
        - New saved agents inherit the full centrally authorized AgenTM5N tool set by default. Use a restricted capability list only when the user explicitly asks for a sandbox.
        - Never place passwords, API keys, tokens, private keys, or other secrets inside saved agent instructions.
        """
      )
    }

    return sections.joined(separator: "\n\n")
  }

  private static func containsExplicitWebURL(_ text: String) -> Bool {
    let normalized = text.lowercased()
    return normalized.contains("http://")
      || normalized.contains("https://")
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
    @Guide(description: "Optional. Omit this value or use current.")
    var query: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    AgentRuntimeContext.currentTemporalContext()
  }
}
