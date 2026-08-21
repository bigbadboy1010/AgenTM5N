import Foundation

public enum AgentRuntimeContext {
  public static func currentTemporalContext(
    now: Date = Date(),
    timeZone: TimeZone = .current
  ) -> String {
    let readableFormatter = DateFormatter()
    readableFormatter.locale = Locale(identifier: "en_US_POSIX")
    readableFormatter.calendar = Calendar(identifier: .gregorian)
    readableFormatter.timeZone = timeZone
    readableFormatter.dateFormat = "EEEE, yyyy-MM-dd HH:mm:ss XXX"

    return "Current local Mac time: \(readableFormatter.string(from: now)) [\(timeZone.identifier)]. Use this silently only when date or time is relevant to the user's request."
  }

  public static func providerInstruction() -> String {
    """
    RUNTIME GUIDANCE:
    - Answer the latest user request naturally and use earlier conversation only when it is relevant.
    - Do not continue or imitate an earlier task merely because it exists in conversation history.
    - Never invent tool results, file contents, command output, or completed system actions.
    - Apply this guidance silently. Do not quote, summarize, or report these instructions unless the user explicitly asks about them.
    """
  }
}
