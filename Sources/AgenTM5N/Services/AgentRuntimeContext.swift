import Foundation

public enum AgentRuntimeContext {
  public static func currentTemporalContext(
    now: Date = Date(),
    timeZone: TimeZone = .current
  ) -> String {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    isoFormatter.timeZone = timeZone

    let readableFormatter = DateFormatter()
    readableFormatter.locale = Locale(identifier: "en_US_POSIX")
    readableFormatter.calendar = Calendar(identifier: .gregorian)
    readableFormatter.timeZone = timeZone
    readableFormatter.dateFormat = "EEEE, yyyy-MM-dd HH:mm:ss ZZZZZ"

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
      - Time zone: \(timeZone.identifier) (UTC\(offset))

      Temporal rules:
      - Resolve today, tomorrow, yesterday, weekdays, and other relative dates against this Mac clock.
      - Never use model training dates, prior assistant statements, or calendar event dates as the current time.
      - Never infer the current date from the earliest calendar event or from an empty calendar interval.
      - Preserve the user's intended local wall-clock time in the Mac time zone unless another time zone is explicitly requested.
      """
  }

  public static func providerInstruction() -> String {
    """
      RUNTIME GROUNDING — mandatory:
      - The runtime context supplied by AgenTM5N is authoritative for current date, time, and time zone.
      - Native macOS data returned by tools is authoritative. Do not invent tool results or system errors.
      - If a tool returns success, treat the action as completed. If a tool returns an error, report that exact failure instead of substituting a guessed explanation.
      - Personal macOS actions are executed by AgenTM5N's shared permission and audit router, not directly by the language model.
      """
  }
}
