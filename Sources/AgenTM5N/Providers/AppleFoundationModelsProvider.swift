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

    let temporalContext = Self.currentTemporalContext()
    let instructions = configuration.systemPrompt
      + "\n\n"
      + SystemLanguage.current.agentInstruction
      + "\n\n"
      + temporalContext
      + "\n\n"
      + """
      CALENDAR GROUNDING RULES — mandatory:
      - The CURRENT MAC DATE AND TIME above is authoritative.
      - Calendar event results are data records, not a clock. The earliest returned event does NOT indicate today's date.
      - An empty calendar interval does NOT mean that interval is in the past.
      - Prior assistant statements about the current date are untrusted if they conflict with the CURRENT MAC DATE AND TIME.
      - EventKit can store events in the past and in the future. Do not invent a rule that calendar start dates must be in the future.
      - If you are about to reject, reinterpret, or question a calendar request because of whether a date is past or future, call system_current_datetime first and use its result.
      - If the user explicitly gives a valid absolute date and time, call the requested calendar tool instead of asking for a replacement date merely because existing calendar results start later.
      """

    var tools: [any Tool] = [SystemCurrentDateTimeTool()]
    if configuration.agentEnabled {
      tools.append(contentsOf: AppleMacNativeTools.makeTools())
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

  fileprivate static func currentTemporalContext() -> String {
    let now = Date()
    let timeZone = TimeZone.current

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    isoFormatter.timeZone = timeZone

    let readableFormatter = DateFormatter()
    readableFormatter.locale = Locale(identifier: "en_US_POSIX")
    readableFormatter.calendar = Calendar(identifier: .gregorian)
    readableFormatter.timeZone = timeZone
    readableFormatter.dateFormat = "EEEE, yyyy-MM-dd HH:mm:ss ZZZZZ"

    let zoneName = timeZone.identifier
    let offsetSeconds = timeZone.secondsFromGMT(for: now)
    let sign = offsetSeconds >= 0 ? "+" : "-"
    let absoluteOffset = abs(offsetSeconds)
    let offsetHours = absoluteOffset / 3_600
    let offsetMinutes = (absoluteOffset % 3_600) / 60
    let offset = String(format: "%@%02d:%02d", sign, offsetHours, offsetMinutes)

    return """
      CURRENT MAC DATE AND TIME — authoritative runtime context:
      - Local date/time: \(readableFormatter.string(from: now))
      - ISO-8601 now: \(isoFormatter.string(from: now))
      - Time zone: \(zoneName) (UTC\(offset))

      Temporal rules:
      - Resolve words such as today, tomorrow, yesterday, next Monday, this evening, and similar relative dates against the CURRENT MAC DATE AND TIME above.
      - Never use model training dates, prior assistant statements, or calendar event dates as the current time.
      - Never claim that a requested date is in the past unless it is actually earlier than the CURRENT MAC DATE AND TIME above.
      - When calling calendar tools, convert requested local calendar times to ISO-8601 and always include the explicit current UTC offset.
      - Preserve the user's intended local wall-clock time in the current Mac time zone unless the user explicitly specifies another time zone.
      """
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
  let description = "Return the authoritative current Mac date, local time, time zone, and UTC offset. Call this before deciding whether a calendar date is in the past or future, and before resolving relative dates when there is any ambiguity. Calendar event dates must never be used as a substitute for this clock."

  @Generable
  struct Arguments {
    @Guide(description: "Use the literal value current")
    var query: String
  }

  func call(arguments: Arguments) async throws -> String {
    AppleFoundationModelsProvider.currentTemporalContext()
  }
}
