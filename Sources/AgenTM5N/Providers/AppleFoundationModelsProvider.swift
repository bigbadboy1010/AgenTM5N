import Foundation
import FoundationModels

public enum AppleFoundationModelsProviderError: LocalizedError {
  case unavailable(String)

  public var errorDescription: String? {
    switch self {
    case .unavailable(let reason):
      return L10n.text(
        de: "Apple Foundation Models ist nicht verfügbar: \(reason)",
        en: "Apple Foundation Models is unavailable: \(reason)",
        fr: "Apple Foundation Models n’est pas disponible : \(reason)"
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
    let instructions = configuration.systemPrompt
      + "\n\n"
      + SystemLanguage.current.agentInstruction
      + "\n\n"
      + AgentRuntimeContext.providerInstruction()
      + "\n\n"
      + temporalContext
      + "\n\n"
      + Self.toolInstructions(selection: selection)

    var tools: [any Tool] = [SystemCurrentDateTimeTool()]
    if configuration.agentEnabled {
      if selection.macNative {
        tools.append(contentsOf: AppleRoutedMacNativeTools.makeTools())
      }
      if selection.persistentAgents {
        tools.append(contentsOf: AppleRoutedPersistentAgentTools.makeTools())
      }
      if selection.operational {
        tools.append(contentsOf: AppleRoutedOperationalTools.makeTools())
      } else if selection.ssh {
        // SSH is intentionally a focused three-tool pack. Apple Foundation
        // Models counts every tool schema against its on-device context window.
        tools.append(contentsOf: AppleRoutedSSHTools.makeTools())
      }
    }

    let session = LanguageModelSession(
      model: model,
      tools: tools
    ) {
      instructions
    }
    let prompt = Self.makePrompt(messages: messages)
      + "\n\n"
      + "AUTHORITATIVE RUNTIME CONTEXT FOR THIS TURN:\n"
      + temporalContext
    let clock = ContinuousClock()
    let startedAt = clock.now
    let response = try await session.respond(to: prompt)
    let duration = startedAt.duration(to: clock.now)
    let durationNanoseconds = Self.nanoseconds(from: duration)

    return ProviderStreamEvent(
      contentDelta: response.content,
      thinkingDelta: "",
      isFinished: true,
      metrics: ChatMetrics(totalDurationNanoseconds: durationNanoseconds)
    )
  }

  private struct ToolSelection {
    var macNative: Bool
    var persistentAgents: Bool
    var ssh: Bool
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
    // Do not match the generic substring "agent": the application name
    // "AgenTM5N" itself contains it and previously loaded the persistent-agent
    // schema unnecessarily for ordinary SSH requests.
    let agentTerms = [
      "agent erstellen", "agent anlegen", "agent speichern", "agent ändern",
      "agent aktualisieren", "agent löschen", "agent auflisten", "agenten",
      "gespeicherter agent", "gespeicherte agent", "specialist", "spezialist",
    ]

    let ssh = sshTerms.contains { latestUserText.contains($0) }
    let operational = broadOperationalTerms.contains { latestUserText.contains($0) }
    let macNative = macTerms.contains { latestUserText.contains($0) }
    let persistentAgents = agentTerms.contains { latestUserText.contains($0) }

    if !ssh && !operational && !macNative && !persistentAgents {
      return ToolSelection(
        macNative: true,
        persistentAgents: true,
        ssh: false,
        operational: false
      )
    }

    return ToolSelection(
      macNative: macNative,
      persistentAgents: persistentAgents,
      ssh: ssh,
      operational: operational
    )
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

    if selection.ssh || selection.operational {
      sections.append(
        """
        SSH RULES:
        - Use ssh_list_hosts to discover configured SSH profiles instead of asking for credentials.
        - ssh_run and ssh_open_terminal resolve linked password/private-key/passphrase secrets internally from the AgenTM5N Vault.
        - Never request, echo, infer, or expose password, private-key, passphrase, or secret-ID values.
        - Use ssh_run for remote non-interactive commands and ssh_open_terminal for an interactive remote session.
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

    // Preserve the newest part of the conversation, including the current user
    // request, while keeping room for tool schemas and model output.
    return "[Earlier conversation omitted for Apple on-device context budget]\n\n"
      + String(rendered.suffix(maximumConversationCharacters))
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
