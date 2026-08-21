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
      AGENTM5N TOOL SECURITY:
      - Use the provider-neutral AgenTM5N tools when they are relevant.
      - Never claim that a tool-backed action was executed, succeeded, failed, or produced data unless the corresponding AgenTM5N tool was actually called in the current turn and returned that result. If no tool call occurred, state clearly that the action was not executed.
      - Never request or expose password, private-key, passphrase, API-key, token, or other Vault secret values.
      - secret_list returns metadata labels only. Tools that accept secret_ref resolve that label internally inside AgenTM5N.
      - Prefer workspace_semantic_search for meaning-based Workspace Memory retrieval when a semantic index is available.
      - Prefer ssh_run_batch for multi-command remote diagnostics and workflows for repeatable multi-step procedures.
      """
    }

    return """
    AGENTM5N EXECUTION INTEGRITY:
    - Tool execution is disabled for this turn. You cannot run commands or read files through AgenTM5N tools.
    - Never claim that an action was executed, succeeded, failed, or produced data unless that evidence was actually provided in the current turn.
    - If no tool call occurred, state clearly that the action was not executed.
    """
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
