import Foundation

/// Hard context-budget guard for the tiny ANEMLL Qwen3 runtime.
///
/// The bundled Qwen3 profile has only 512 tokens of context. The upstream
/// interactive helper keeps its own hidden history, so an unconstrained system
/// prompt + tool catalog + generated-token budget can crowd the current user
/// request out of the effective context. This policy gives the current request
/// explicit priority and rotates small-context sessions between user turns.
public enum ANEMLLContextBudget {
  public static let smallContextThreshold = 1_024
  public static let smallContextSystemCharacters = 240
  public static let smallContextTransportCharacters = 900

  public static func maxOutputTokens(
    requested: Int,
    contextLength: Int?
  ) -> Int {
    let requested = max(1, requested)
    guard let contextLength, contextLength > 0 else {
      return min(requested, 1_024)
    }

    if contextLength <= smallContextThreshold {
      // ctx512 => 128 generated tokens, leaving the majority of the window for
      // system/tool/current-user input. Never let --max-tokens consume all 512.
      let cap = max(64, contextLength / 4)
      return min(requested, cap)
    }

    return min(requested, max(256, contextLength / 2))
  }

  public static func compactSystemPrompt(
    _ base: String,
    contextLength: Int?
  ) -> String {
    guard let contextLength, contextLength <= smallContextThreshold else {
      return base.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let clean = base
      .replacingOccurrences(of: "\n", with: " ")
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
    let identity = boundedPreservingEnds(clean, limit: 92)
    let guardrail = "CURRENT USER/TASK has priority. Answer that request directly; do not repeat system text. Real actions require advertised tools; never invent tool results."
    return boundedPreservingEnds(
      [identity, guardrail].filter { !$0.isEmpty }.joined(separator: " "),
      limit: smallContextSystemCharacters
    )
  }

  public static func compactTransportPrompt(
    _ prompt: String,
    contextLength: Int?
  ) -> String {
    let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let contextLength, contextLength <= smallContextThreshold else {
      return clean
    }
    return boundedPreservingEnds(
      clean,
      limit: smallContextTransportCharacters,
      headFraction: 0.42,
      marker: "\n…[ctx budget: middle omitted; current request preserved]…\n"
    )
  }

  public static func shouldRotateBeforeUserTurn(
    contextLength: Int?,
    activeTurns: Int,
    isFreshConversation: Bool,
    isToolContinuation: Bool
  ) -> Bool {
    if isFreshConversation { return true }
    guard !isToolContinuation, activeTurns > 0 else { return false }
    guard let contextLength else { return false }
    return contextLength <= smallContextThreshold
  }

  /// Adds only the immediately preceding user/assistant exchange to a normal
  /// user request. This preserves basic follow-up semantics when the ctx512
  /// helper is rotated between UI turns, without replaying the entire chat.
  public static func addingRecentConversationContext(
    to prompt: String,
    messages: [ProviderMessage],
    isToolContinuation: Bool,
    contextLength: Int?
  ) -> String {
    guard !isToolContinuation,
      let contextLength,
      contextLength <= smallContextThreshold,
      let markerRange = prompt.range(of: "USER/TASK INPUT:\n")
    else {
      return compactTransportPrompt(prompt, contextLength: contextLength)
    }

    let lastUserIndex = messages.lastIndex(where: { $0.role == .user })
    guard let lastUserIndex, lastUserIndex > messages.startIndex else {
      return compactTransportPrompt(prompt, contextLength: contextLength)
    }

    let history = messages[..<lastUserIndex]
    let previousAssistant = history.last(where: { $0.role == .assistant })
    let previousUser = history.last(where: { $0.role == .user })
    guard previousAssistant != nil || previousUser != nil else {
      return compactTransportPrompt(prompt, contextLength: contextLength)
    }

    var contextLines: [String] = []
    if let previousUser {
      let text = PromptAttachmentService.providerPrompt(from: previousUser.content)
      contextLines.append("Previous user: \(boundedPreservingEnds(text, limit: 110))")
    }
    if let previousAssistant {
      contextLines.append(
        "Previous assistant: \(boundedPreservingEnds(previousAssistant.content, limit: 130))"
      )
    }

    let prefix = String(prompt[..<markerRange.upperBound])
    let currentRequest = String(prompt[markerRange.upperBound...])
    let contextualized = prefix
      + "RECENT CONTEXT (only for follow-up reference):\n"
      + contextLines.joined(separator: "\n")
      + "\nCURRENT USER REQUEST (highest priority):\n"
      + currentRequest

    return compactTransportPrompt(contextualized, contextLength: contextLength)
  }

  private static func boundedPreservingEnds(
    _ value: String,
    limit: Int,
    headFraction: Double = 0.65,
    marker: String = " … "
  ) -> String {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.count > limit, limit > marker.count + 8 else { return clean }

    let available = limit - marker.count
    let headCount = max(1, min(available - 1, Int(Double(available) * headFraction)))
    let tailCount = max(1, available - headCount)
    return String(clean.prefix(headCount)) + marker + String(clean.suffix(tailCount))
  }
}
