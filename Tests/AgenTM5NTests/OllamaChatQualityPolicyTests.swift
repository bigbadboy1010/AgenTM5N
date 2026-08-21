import XCTest
@testable import AgenTM5N

final class OllamaChatQualityPolicyTests: XCTestCase {
  func testToolsDisabledPromptDoesNotAdvertiseTools() {
    let prompt = OllamaConversationPolicy.executionIntegrity(agentEnabled: false)

    XCTAssertTrue(prompt.contains("Tool execution is disabled for this turn"))
    XCTAssertFalse(prompt.contains("ssh_run_batch"))
    XCTAssertFalse(prompt.contains("workspace_semantic_search"))
    XCTAssertFalse(prompt.contains("secret_list"))
    XCTAssertFalse(prompt.contains("Use the provider-neutral AgenTM5N tools"))
  }

  func testToolsEnabledPromptPreservesToolGuidance() {
    let prompt = OllamaConversationPolicy.executionIntegrity(agentEnabled: true)

    XCTAssertTrue(prompt.contains("Use the provider-neutral AgenTM5N tools"))
    XCTAssertTrue(prompt.contains("ssh_run_batch"))
    XCTAssertTrue(prompt.contains("workspace_semantic_search"))
    XCTAssertTrue(prompt.contains("secret_list"))
  }

  func testPreviousAppSessionMessagesAreExcludedFromInference() {
    let persistedUser = ChatMessage(role: .user, content: "prüfe die Tools")
    let persistedAssistant = ChatMessage(role: .assistant, content: "Alle 70 Tools sind aktiv.")
    let currentUser = ChatMessage(role: .user, content: "so wir sind wieder da")
    let excluded = UUID()

    let history = OllamaConversationPolicy.boundedHistory(
      messages: [
        persistedUser,
        persistedAssistant,
        currentUser,
        ChatMessage(id: excluded, role: .assistant, content: "")
      ],
      excludingAssistantID: excluded,
      numContext: 8_192,
      allowedMessageIDs: [currentUser.id, excluded]
    )

    XCTAssertEqual(history.count, 1)
    XCTAssertEqual(history.first?.content, "so wir sind wieder da")
    XCTAssertFalse(history.contains { $0.content.contains("70 Tools") })
  }

  func testHistoricalThinkingIsNeverReplayed() {
    let excluded = UUID()
    let messages = [
      ChatMessage(role: .user, content: "first"),
      ChatMessage(role: .assistant, content: "answer", thinking: "private old reasoning"),
      ChatMessage(role: .user, content: "latest"),
      ChatMessage(id: excluded, role: .assistant, content: "")
    ]

    let history = OllamaConversationPolicy.boundedHistory(
      messages: messages,
      excludingAssistantID: excluded,
      numContext: 8_192
    )

    XCTAssertEqual(history.count, 3)
    XCTAssertTrue(history.allSatisfy { $0.thinking == nil })
    XCTAssertEqual(history.last?.content, "latest")
  }

  func testHistoryIsBoundedAndKeepsNewestMessages() {
    let excluded = UUID()
    var messages: [ChatMessage] = []
    for index in 0..<40 {
      messages.append(
        ChatMessage(
          role: index.isMultiple(of: 2) ? .user : .assistant,
          content: "message-\(index)"
        )
      )
    }
    messages.append(ChatMessage(id: excluded, role: .assistant, content: ""))

    let history = OllamaConversationPolicy.boundedHistory(
      messages: messages,
      excludingAssistantID: excluded,
      numContext: 8_192
    )

    XCTAssertEqual(history.count, OllamaConversationPolicy.maximumHistoryMessages)
    XCTAssertEqual(history.last?.content, "message-39")
    XCTAssertEqual(history.first?.content, "message-16")
  }

  func testGPTOssReasoningLevelsAreValid() {
    var configuration = AgentOperatingLayerConfiguration()

    configuration.thinkingMode = .off
    XCTAssertEqual(
      configuration.ollamaThinkValue(
        forModel: "gpt-oss:120b",
        legacyThinkingEnabled: false
      ),
      .string("low")
    )

    configuration.thinkingMode = .standard
    XCTAssertEqual(
      configuration.ollamaThinkValue(
        forModel: "gpt-oss:120b",
        legacyThinkingEnabled: false
      ),
      .string("medium")
    )

    configuration.thinkingMode = .max
    XCTAssertEqual(
      configuration.ollamaThinkValue(
        forModel: "gpt-oss:120b",
        legacyThinkingEnabled: true
      ),
      .string("high")
    )
  }

  func testGPTOssSamplingUsesModelRecommendedBaseline() {
    var configuration = AgentOperatingLayerConfiguration()
    configuration.temperature = 0.2
    configuration.topP = 0.9
    configuration.topK = 40
    configuration.minP = 0.1
    configuration.repeatPenalty = 1.1

    let options = configuration.ollamaOptions(forModel: "gpt-oss:120b")

    XCTAssertEqual(options["temperature"], .number(1.0))
    XCTAssertEqual(options["top_p"], .number(1.0))
    XCTAssertNil(options["top_k"])
    XCTAssertNil(options["min_p"])
    XCTAssertNil(options["repeat_penalty"])
    XCTAssertNil(options["repeat_last_n"])
    XCTAssertNotNil(options["num_ctx"])
    XCTAssertNotNil(options["num_predict"])
  }

  func testNonGPTOssKeepsGenericSamplingAndThinking() {
    var configuration = AgentOperatingLayerConfiguration()
    configuration.thinkingMode = .max
    configuration.temperature = 0.2
    configuration.topP = 0.9
    configuration.topK = 40

    XCTAssertEqual(
      configuration.ollamaThinkValue(
        forModel: "qwen3:8b",
        legacyThinkingEnabled: true
      ),
      .string("max")
    )

    let options = configuration.ollamaOptions(forModel: "qwen3:8b")
    XCTAssertEqual(options["temperature"], .number(0.2))
    XCTAssertEqual(options["top_p"], .number(0.9))
    XCTAssertEqual(options["top_k"], .number(40))
  }
}
