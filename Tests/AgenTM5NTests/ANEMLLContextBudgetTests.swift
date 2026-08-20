import XCTest
@testable import AgenTM5N

final class ANEMLLContextBudgetTests: XCTestCase {
  func testCtx512ReservesMostWindowForCurrentInput() {
    XCTAssertEqual(
      ANEMLLContextBudget.maxOutputTokens(
        requested: 4_096,
        contextLength: 512
      ),
      128
    )
  }

  func testLargerContextDoesNotUseTinyModelCap() {
    XCTAssertEqual(
      ANEMLLContextBudget.maxOutputTokens(
        requested: 1_024,
        contextLength: 4_096
      ),
      1_024
    )
  }

  func testSmallContextSystemPromptIsCompactAndCurrentTaskFocused() {
    let prompt = String(repeating: "Du bist AgenTM5N mit langen Systemregeln. ", count: 40)
    let compact = ANEMLLContextBudget.compactSystemPrompt(
      prompt,
      contextLength: 512
    )

    XCTAssertLessThanOrEqual(
      compact.count,
      ANEMLLContextBudget.smallContextSystemCharacters
    )
    XCTAssertTrue(compact.contains("CURRENT USER/TASK"))
    XCTAssertTrue(compact.contains("do not repeat system text"))
  }

  func testTransportCompactionPreservesHeadAndCurrentRequestTail() {
    let prompt = "TOOLS:\n"
      + String(repeating: "tool definition abcdefghijklmnopqrstuvwxyz\n", count: 80)
      + "USER/TASK INPUT:\nUNIQUE-CURRENT-REQUEST-9F41"

    let compact = ANEMLLContextBudget.compactTransportPrompt(
      prompt,
      contextLength: 512
    )

    XCTAssertLessThanOrEqual(
      compact.count,
      ANEMLLContextBudget.smallContextTransportCharacters
    )
    XCTAssertTrue(compact.hasPrefix("TOOLS:"))
    XCTAssertTrue(compact.contains("UNIQUE-CURRENT-REQUEST-9F41"))
  }

  func testSmallContextRotatesBetweenUserTurnsButNotToolContinuation() {
    XCTAssertTrue(
      ANEMLLContextBudget.shouldRotateBeforeUserTurn(
        contextLength: 512,
        activeTurns: 1,
        isFreshConversation: false,
        isToolContinuation: false
      )
    )
    XCTAssertFalse(
      ANEMLLContextBudget.shouldRotateBeforeUserTurn(
        contextLength: 512,
        activeTurns: 1,
        isFreshConversation: false,
        isToolContinuation: true
      )
    )
  }

  func testLargeContextDoesNotForcePerUserTurnRotation() {
    XCTAssertFalse(
      ANEMLLContextBudget.shouldRotateBeforeUserTurn(
        contextLength: 8_192,
        activeTurns: 4,
        isFreshConversation: false,
        isToolContinuation: false
      )
    )
  }

  func testRecentContextKeepsImmediatePreviousExchangeAndCurrentRequest() {
    let messages = [
      ProviderMessage(role: .user, content: "Vorherige Benutzerfrage"),
      ProviderMessage(role: .assistant, content: "Vorherige Agentenantwort"),
      ProviderMessage(role: .user, content: "AKTUELLE-FRAGE-42"),
    ]
    let transport = """
      AGENTM5N TOOLS FOR THIS TURN:
      - read_file(path): read
      USER/TASK INPUT:
      AKTUELLE-FRAGE-42
      """

    let result = ANEMLLContextBudget.addingRecentConversationContext(
      to: transport,
      messages: messages,
      isToolContinuation: false,
      contextLength: 512
    )

    XCTAssertTrue(result.contains("Previous user: Vorherige Benutzerfrage"))
    XCTAssertTrue(result.contains("Previous assistant: Vorherige Agentenantwort"))
    XCTAssertTrue(result.contains("CURRENT USER REQUEST"))
    XCTAssertTrue(result.contains("AKTUELLE-FRAGE-42"))
  }
}
