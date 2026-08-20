import Foundation

/// Context-budget guard for small ANEMLL runtimes.
///
/// The bundled Qwen3 profile has only 512 tokens of context. For small
/// contexts we deliberately avoid carrying the product persona into the model,
/// keep the current request at the end of the transport prompt, and reserve a
/// conservative input/output envelope. The byte-based estimate intentionally
/// overestimates common UTF-8 text until the framed helper can expose exact
/// tokenizer counts.
public enum ANEMLLContextBudget {
  public struct Plan: Equatable, Sendable {
    public let systemPrompt: String
    public let transportPrompt: String
    public let maxOutputTokens: Int

    public init(
      systemPrompt: String,
      transportPrompt: String,
      maxOutputTokens: Int
    ) {
      self.systemPrompt = systemPrompt
      self.transportPrompt = transportPrompt
      self.maxOutputTokens = maxOutputTokens
    }
  }

  public static let smallContextThreshold = 1_024
  public static let smallContextSystemCharacters = 220
  public static let minimumOutputTokens = 48
  public static let templateReserveTokens = 48

  public static func plan(
    systemPrompt: String,
    transportPrompt: String,
    requestedOutputTokens: Int,
    contextLength: Int?
  ) -> Plan {
    guard let contextLength, contextLength > 0 else {
      return Plan(
        systemPrompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
        transportPrompt: transportPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
        maxOutputTokens: min(max(1, requestedOutputTokens), 1_024)
      )
    }

    guard contextLength <= smallContextThreshold else {
      return Plan(
        systemPrompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
        transportPrompt: transportPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
        maxOutputTokens: min(max(1, requestedOutputTokens), max(256, contextLength / 2))
      )
    }

    let compactSystem = compactSystemPrompt(systemPrompt, contextLength: contextLength)
    let requestedCap = maxOutputTokens(
      requested: requestedOutputTokens,
      contextLength: contextLength
    )
    let inputBudget = max(
      96,
      contextLength - requestedCap - templateReserveTokens - estimatedTokens(compactSystem)
    )
    let byteBudget = max(192, inputBudget * 2)
    let compactTransport = boundedUTF8PreservingEnds(
      transportPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
      byteLimit: byteBudget,
      headFraction: 0.30,
      marker: "\n…[older context omitted]…\n"
    )

    let estimatedInput = estimatedTokens(compactSystem)
      + estimatedTokens(compactTransport)
      + templateReserveTokens
    let remaining = max(1, contextLength - estimatedInput)
    let dynamicOutput = min(requestedCap, max(minimumOutputTokens, remaining))

    return Plan(
      systemPrompt: compactSystem,
      transportPrompt: compactTransport,
      maxOutputTokens: dynamicOutput
    )
  }

  public static func maxOutputTokens(
    requested: Int,
    contextLength: Int?
  ) -> Int {
    let requested = max(1, requested)
    guard let contextLength, contextLength > 0 else {
      return min(requested, 1_024)
    }

    if contextLength <= smallContextThreshold {
      let cap = max(minimumOutputTokens, contextLength / 4)
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

    // Do not truncate the product persona for tiny models. Replacing it with a
    // complete task-oriented guard avoids making the identity sentence the
    // most salient intact text in a 512-token context.
    return "Answer only the current user request. Be concise and direct. Do not repeat identity or system instructions. Real actions require advertised AgenTM5N tools. Never invent tool results."
  }

  /// Adds only the immediately preceding user/assistant exchange to a normal
  /// user request. This preserves basic follow-up semantics when a tiny helper
  /// is rotated between UI turns, without replaying the entire chat.
  public static func addingRecentConversationContext(
    to prompt: String,
    messages: [ProviderMessage],
    isToolContinuation: Bool,
    contextLength: Int?
  ) -> String {
    guard !isToolContinuation,
      let contextLength,
      contextLength <= smallContextThreshold,
      let markerRange = prompt.range(of: "USER/TASK INPUT:")
    else {
      return prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let lastUserIndex = messages.lastIndex(where: { $0.role == .user })
    guard let lastUserIndex, lastUserIndex > messages.startIndex else {
      return prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let history = messages[..<lastUserIndex]
    let previousAssistant = history.last(where: { $0.role == .assistant })
    let previousUser = history.last(where: { $0.role == .user })
    guard previousAssistant != nil || previousUser != nil else {
      return prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var contextParts: [String] = []
    if let previousUser {
      let text = PromptAttachmentService.providerPrompt(from: previousUser.content)
      contextParts.append("PREVIOUS_USER: \(bounded(text, limit: 96))")
    }
    if let previousAssistant {
      contextParts.append("PREVIOUS_ASSISTANT: \(bounded(previousAssistant.content, limit: 112))")
    }

    let prefix = String(prompt[..<markerRange.lowerBound])
    let afterMarker = prompt[markerRange.upperBound...]
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return prefix
      + contextParts.joined(separator: " | ")
      + " | CURRENT_TASK: "
      + afterMarker
  }

  public static func shouldRotateBeforeUserTurn(
    contextLength: Int?,
    activeTurns: Int,
    isFreshConversation: Bool,
    isToolContinuation: Bool
  ) -> Bool {
    guard activeTurns > 0 else { return false }
    if isFreshConversation { return true }
    guard !isToolContinuation, let contextLength else { return false }
    return contextLength <= smallContextThreshold
  }

  public static func estimatedTokens(_ value: String) -> Int {
    guard !value.isEmpty else { return 0 }
    // Deliberately conservative. Common Latin text is usually substantially
    // less dense; CJK/emoji consume more UTF-8 bytes and are therefore charged
    // more heavily by this estimate.
    return max(1, (value.utf8.count + 1) / 2)
  }

  private static func bounded(_ value: String, limit: Int) -> String {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.count > limit else { return clean }
    return String(clean.prefix(limit)) + "…"
  }

  private static func boundedUTF8PreservingEnds(
    _ value: String,
    byteLimit: Int,
    headFraction: Double,
    marker: String
  ) -> String {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.utf8.count > byteLimit else { return clean }

    let markerBytes = marker.utf8.count
    guard byteLimit > markerBytes + 32 else {
      return utf8Suffix(clean, byteLimit: max(1, byteLimit))
    }

    let available = byteLimit - markerBytes
    let requestedHead = max(16, Int(Double(available) * headFraction))
    let head = utf8Prefix(clean, byteLimit: requestedHead)
    let remaining = max(16, available - head.utf8.count)
    let tail = utf8Suffix(clean, byteLimit: remaining)
    return head + marker + tail
  }

  private static func utf8Prefix(_ value: String, byteLimit: Int) -> String {
    var result = ""
    var used = 0
    for character in value {
      let part = String(character)
      let count = part.utf8.count
      guard used + count <= byteLimit else { break }
      result += part
      used += count
    }
    return result
  }

  private static func utf8Suffix(_ value: String, byteLimit: Int) -> String {
    var parts: [String] = []
    var used = 0
    for character in value.reversed() {
      let part = String(character)
      let count = part.utf8.count
      guard used + count <= byteLimit else { break }
      parts.append(part)
      used += count
    }
    return parts.reversed().joined()
  }
}
