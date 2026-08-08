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
        de: "Die AgenTM5N-Werkzeuge sind deaktiviert. Aktiviere den Agent-Modus in den Einstellungen und versuche die SSH-Anfrage erneut.",
        en: "AgenTM5N tools are disabled. Enable Agent mode in Settings and retry the SSH request.",
        fr: "Les outils AgenTM5N sont désactivés. Activez le mode Agent dans les réglages puis réessayez la requête SSH."
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
      return L10n.text(
        de: "Verfügbar",
        en: "Available",
        fr: "Disponible"
      )
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
    let focusedSSH = selection.sshMode != nil

    if focusedSSH && !configuration.agentEnabled {
      throw AppleFoundationModelsProviderError.toolsDisabled
    }

    let instructions: String
    if focusedSSH {
      instructions = Self.sshInstructions()
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
    if focusedSSH {
      switch selection.sshMode {
      case .list:
        tools.append(contentsOf: AppleRoutedSSHTools.makeListHostsTools())
      case .run:
        tools.append(contentsOf: AppleRoutedSSHTools.makeRunTools())
      case .terminal:
        tools.append(contentsOf: AppleRoutedSSHTools.makeOpenTerminalTools())
      case nil:
        break
      }
    } else {
      tools.append(SystemCurrentDateTimeTool())
      if configuration.agentEnabled {
        if selection.macNative {
          tools.append(contentsOf: AppleRoutedMacNativeTools.makeTools())
        }
        if selection.persistentAgents {
          tools.append(contentsOf: AppleRoutedPersistentAgentTools.makeTools())
        }
        if selection.operational {
          tools.append(contentsOf: AppleRoutedOperationalTools.makeTools())
        }
      }
    }

    let session = LanguageModelSession(
      model: model,
      tools: tools
    ) {
      instructions
    }

    let prompt: String
    if focusedSSH {
      prompt = Self.latestUserPrompt(messages: messages)
    } else {
      prompt = Self.makePrompt(messages: messages)
        + "\n\n"
        + "AUTHORITATIVE RUNTIME CONTEXT FOR THIS TURN:\n"
        + temporalContext
    }

    let clock = ContinuousClock()
    let startedAt = clock.now

    do {
      let response = try await session.respond(to: prompt)
      let duration = startedAt.duration(to: clock.now)
      let durationNanoseconds = Self.nanoseconds(from: duration)

      return ProviderStreamEvent(
        contentDelta: response.content,
        thinkingDelta: "",
        isFinished: true,
        metrics: ChatMetrics(totalDurationNanoseconds: durationNanoseconds)
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
  }

  private struct ToolSelection {
    var macNative: Bool
    var persistentAgents: Bool
    var sshMode: SSHMode?
    var operational: Bool
  }

  private static func toolSelection(for messages: [ChatMessage]) -> ToolSelection {
    let latestUserText = messages
      .last(where: { $0.role == .user })?
      .content
      .lowercased() ?? ""

    let sshTerms = [
      "ssh", "server", "remote", "docker", "container", "systemctl", "journalctl",
      "linux", "photon", "redhat", "red hat", "ubuntu", "kubernetes", "openshift",
      "lenovo-server", "remote host", "remote-host",
    ]
    let broadOperationalTerms = [
      "git status", "git diff", "git branch", "git commit", "repository", "repo ",
      "workspace", "datei", "file", "folder", "ordner", "lokales terminal",
      "local terminal", "lokaler befehl", "local command", "shell command",
    ]
    let macTerms = [
      "calendar", "kalender", "termin", "event", "contact", "kontakt", "address book",
      "adressbuch", "mail", "email", "e-mail", "nachricht", "inbox", "posteingang",
    ]
    let agentTerms = [
      "agent erstellen", "agent anlegen", "agent speichern", "agent ändern",
      "agent aktualisieren", "agent löschen", "agent auflisten", "agenten",
      "gespeicherter agent", "gespeicherte agent", "specialist", "spezialist",
    ]

    let isSSHRequest = sshTerms.contains { latestUserText.contains($0) }
    let operational = !isSSHRequest && broadOperationalTerms.contains {
      latestUserText.contains($0)
    }
    let macNative = !isSSHRequest && macTerms.contains { latestUserText.contains($0) }
    let persistentAgents = !isSSHRequest && agentTerms.contains {
      latestUserText.contains($0)
    }

    let sshMode: SSHMode?
    if isSSHRequest {
      let runTerms = [
        "führe", "ausführen", "ausfuehren", "befehl", "kommando", "command",
        "docker", "systemctl", "journalctl", "whoami", "hostname", "uname",
        "df ", "free ", "ps ", "top", "uptime", "kubectl", "oc ",
      ]
      let terminalTerms = [
        "interaktiv", "interactive", "terminal öffnen", "terminal oeffnen",
        "open terminal", "ssh terminal", "shell öffnen", "shell oeffnen",
      ]
      if runTerms.contains(where: { latestUserText.contains($0) }) {
        sshMode = .run
      } else if terminalTerms.contains(where: { latestUserText.contains($0) }) {
        sshMode = .terminal
      } else {
        sshMode = .list
      }
    } else {
      sshMode = nil
    }

    if sshMode == nil && !operational && !macNative && !persistentAgents {
      return ToolSelection(
        macNative: true,
        persistentAgents: true,
        sshMode: nil,
        operational: false
      )
    }

    return ToolSelection(
      macNative: macNative,
      persistentAgents: persistentAgents,
      sshMode: sshMode,
      operational: operational
    )
  }

  private static func sshInstructions() -> String {
    """
    You are AgenTM5N running with the Apple on-device language model.
    Respond in the user's language.
    Use the single SSH tool provided for this request when it is needed.
    If the user requests multiple remote commands, preserve every requested command and pass them together in the single ssh_run command argument, in the same order. Separate independent commands with semicolons or newlines. Do not silently drop commands and do not execute only the final command.
    Example: when the user asks for whoami, hostname, and uname -a, pass exactly: whoami; hostname; uname -a
    AgenTM5N resolves passwords, private keys, and passphrases internally from the encrypted Vault.
    Never ask for, expose, repeat, or infer secret values or secret identifiers.
    Report success or failure only from the tool result, and summarize all returned command outputs.
    """
  }

  private static func toolInstructions(selection: ToolSelection) -> String {
    var sections: [String] = [
      """
      TOOL RULES — mandatory:
      - The CURRENT MAC DATE AND TIME above is authoritative.
      - Only report that a native action failed when the corresponding tool actually returns an error.
      - Tool execution remains subject to AgenTM5N permission approval, audit records, workspace boundaries, and macOS security controls.
      """
    ]

    if selection.macNative {
      sections.append(
        """
        CALENDAR GROUNDING RULES:
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

    if selection.operational {
      sections.append(
        """
        WORKSPACE RULES:
        - Use run_command only for local non-interactive work.
        - Read files before modifying them. Prefer apply_patch over write_file for targeted edits.
        """
      )
    }

    return sections.joined(separator: "\n\n")
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
        let role =
          switch message.role {
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
    let secondsPart = UInt64(seconds) * 1_000_000_000
    let attosecondsPart = UInt64(attoseconds / 1_000_000_000)
    return secondsPart + attosecondsPart
  }
}

private struct SystemCurrentDateTimeTool: Tool {
  let name = "system_current_datetime"
  let description = "Return the authoritative current Mac date, local time, time zone, and UTC offset."

  @Generable
  struct Arguments {
    @Guide(description: "Use current")
    var query: String
  }

  func call(arguments: Arguments) async throws -> String {
    AgentRuntimeContext.currentTemporalContext()
  }
}
