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
      + """
      CALENDAR GROUNDING RULES — mandatory:
      - The CURRENT MAC DATE AND TIME above is authoritative.
      - Calendar event results are data records, not a clock. The earliest returned event does NOT indicate today's date.
      - An empty calendar interval does NOT mean that interval is in the past.
      - EventKit can store events in the past and in the future. Do not invent a rule that calendar start dates must be in the future.
      - If you are about to reject or reinterpret a calendar request because of whether a date is past or future, call system_current_datetime first.
      - For calendar_create_event, pass the requested local year, month, day, hour, and minute directly to the tool. Do not construct UTC values for event creation.
      - Only report that a native action failed when the corresponding tool actually returns an error.

      PERSISTENT AGENT RULES:
      - When the user explicitly asks to create, save, define, update, list, inspect, or delete a reusable specialist agent, use the agent_* tools.
      - Saved agents are persistent AgenTM5N profiles and appear in the Agenten section.
      - Never place passwords, API keys, tokens, private keys, or other secrets inside saved agent instructions.

      OPERATIONAL TOOL RULES:
      - When SSH tools are available, use ssh_list_hosts to discover configured profiles instead of asking the user for a password, private key, passphrase, or secret ID.
      - ssh_run and ssh_open_terminal resolve credentials internally from the AgenTM5N Vault through the selected SSH profile. Never request, echo, infer, or expose those secret values.
      - Use run_command only for local non-interactive work. Use ssh_run for remote non-interactive work and ssh_open_terminal for an interactive remote terminal.
      - Read files before modifying them. Prefer apply_patch over write_file for targeted edits.
      - Tool execution remains subject to AgenTM5N permission approval, audit records, workspace boundaries, and macOS security controls.
      """

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
    var operational: Bool
  }

  private static func toolSelection(for messages: [ChatMessage]) -> ToolSelection {
    let userText = messages
      .filter { $0.role == .user }
      .suffix(4)
      .map(\.content)
      .joined(separator: "\n")
      .lowercased()

    let operationalTerms = [
      "ssh", "server", "remote", "host", "terminal", "shell", "command", "kommando",
      "docker", "container", "linux", "systemctl", "journalctl", "git", "repository", "repo",
      "branch", "commit", "workspace", "datei", "file", "folder", "ordner", "log", "vm",
      "maschine", "machine", "photon", "redhat", "red hat", "ubuntu", "kubernetes", "openshift",
    ]
    let macTerms = [
      "calendar", "kalender", "termin", "event", "contact", "kontakt", "address book",
      "adressbuch", "mail", "email", "e-mail", "nachricht", "inbox", "posteingang",
    ]
    let agentTerms = ["agent", "agenten", "specialist", "spezialist"]

    let operational = operationalTerms.contains { userText.contains($0) }
    let macNative = macTerms.contains { userText.contains($0) }
    let persistentAgents = agentTerms.contains { userText.contains($0) }

    if !operational && !macNative && !persistentAgents {
      // Preserve the V1.0 default experience for normal personal-assistant prompts
      // while avoiding large operational schemas when they are not relevant.
      return ToolSelection(
        macNative: true,
        persistentAgents: true,
        operational: false
      )
    }

    return ToolSelection(
      macNative: macNative,
      persistentAgents: persistentAgents,
      operational: operational
    )
  }

  private static func makePrompt(messages: [ChatMessage]) -> String {
    messages
      .filter { $0.role != .system }
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
  let description = "Return the authoritative current Mac date, local time, time zone, and UTC offset. Call this before deciding whether a calendar date is in the past or future, and before resolving relative dates when there is any ambiguity."

  @Generable
  struct Arguments {
    @Guide(description: "Use the literal value current")
    var query: String
  }

  func call(arguments: Arguments) async throws -> String {
    AgentRuntimeContext.currentTemporalContext()
  }
}
