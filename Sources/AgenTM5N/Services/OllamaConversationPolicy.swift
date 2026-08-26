import Foundation

/// Builds the persisted-conversation portion of an Ollama request without
/// leaking tool instructions into tool-disabled turns or replaying historical
/// chain-of-thought.
///
/// The UI may retain the full conversation. Inference receives only a recent,
/// bounded window so old model output cannot grow the request without limit.
public enum OllamaConversationPolicy {
  public static let maximumHistoryMessages = 24
  public static let minimumHistoryBytes = 8 * 1024
  public static let maximumHistoryBytes = 64 * 1024

  public static func executionIntegrity(agentEnabled: Bool) -> String {
    if agentEnabled {
      return """
      AGENTM5N TOOL POLICY:
      - Use AgenTM5N tools when they are relevant to the user's request.
      - Never claim a tool action succeeded, failed, or produced data unless the corresponding tool call in this turn returned that result.
      - Never request or expose password, private-key, passphrase, API-key, token, or other Vault secret values.
      - Treat secret_list results as metadata labels only; secret_ref values are resolved internally by AgenTM5N.
      - Apply this policy silently. Discuss tool execution status only when the user's request actually involves an action or tool use.
      """
    }

    return """
    AGENTM5N TOOL POLICY:
    - No AgenTM5N tools are available for this turn. Answer the user normally.
    - Never claim to have executed a command, read a local file, called a tool, or completed a system action when none occurred.
    - Apply this policy silently. Do not mention tool availability or execution status unless it is relevant to the user's request.
    """
  }

  public static func systemContent(
    baseSystemPrompt: String,
    agentEnabled: Bool,
    now: Date = Date(),
    timeZone: TimeZone = .current
  ) -> String {
    [
      baseSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
      AgentRuntimeContext.providerInstruction(),
      AgentRuntimeContext.currentTemporalContext(now: now, timeZone: timeZone),
      executionIntegrity(agentEnabled: agentEnabled),
    ]
    .filter { !$0.isEmpty }
    .joined(separator: "\n\n")
  }

  public static func historyByteBudget(numContext: Int) -> Int {
    let context = max(512, numContext)
    return max(
      minimumHistoryBytes,
      min(maximumHistoryBytes, context * 2)
    )
  }

  public static func boundedHistory(
    messages: [ChatMessage],
    excludingAssistantID: UUID,
    numContext: Int,
    allowedMessageIDs: Set<UUID>? = nil
  ) -> [ProviderMessage] {
    let candidates = messages.compactMap { message -> ProviderMessage? in
      guard message.id != excludingAssistantID, message.role != .system else {
        return nil
      }
      if let allowedMessageIDs, !allowedMessageIDs.contains(message.id) {
        return nil
      }

      // Historical thinking is intentionally never replayed. The visible
      // assistant answer remains available, but prior reasoning must not become
      // new inference context.
      return ProviderMessage(
        role: message.role == .user ? .user : .assistant,
        content: message.content,
        thinking: nil
      )
    }

    let byteBudget = historyByteBudget(numContext: numContext)
    var selected: [ProviderMessage] = []
    var usedBytes = 0

    for message in candidates.reversed() {
      guard selected.count < maximumHistoryMessages else { break }

      let estimatedBytes = message.content.utf8.count + 64

      // Always preserve at least the newest message, even if the user supplied
      // an unusually large prompt. Older history is what gets pruned.
      if !selected.isEmpty, usedBytes + estimatedBytes > byteBudget {
        break
      }

      selected.append(message)
      usedBytes += estimatedBytes
    }

    return selected.reversed()
  }
}
