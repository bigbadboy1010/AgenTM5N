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

  func testSmallContextSystemPromptReplacesPersonaWithCompleteGuardrail() {
    let source = "Du bist AgenTM5N, ein persönlicher Senior-Software- und DevOps-Agent. "
      + String(repeating: "lange Systemregel ", count: 40)
    let compact = ANEMLLContextBudget.compactSystemPrompt(
      source,
      contextLength: 512
    )

    XCTAssertLessThanOrEqual(
      compact.count,
      ANEMLLContextBudget.smallContextSystemCharacters
    )
    XCTAssertFalse(compact.contains("Senior-Software"))
    XCTAssertTrue(compact.contains("current user request"))
    XCTAssertTrue(compact.contains("Do not repeat identity or system instructions"))
    XCTAssertTrue(compact.contains("Never invent tool results"))
  }

  func testCtx512PlanKeepsCurrentRequestTailAndFitsConservativeEnvelope() {
    let transport = "TOOLS: "
      + String(repeating: "tool_definition_abcdefghijklmnopqrstuvwxyz ", count: 80)
      + " | CURRENT_TASK: UNIQUE-CURRENT-REQUEST-9F41"

    let plan = ANEMLLContextBudget.plan(
      systemPrompt: String(repeating: "persona ", count: 100),
      transportPrompt: transport,
      requestedOutputTokens: 4_096,
      contextLength: 512
    )

    XCTAssertTrue(plan.transportPrompt.contains("UNIQUE-CURRENT-REQUEST-9F41"))
    XCTAssertLessThanOrEqual(plan.maxOutputTokens, 128)
    XCTAssertGreaterThanOrEqual(plan.maxOutputTokens, ANEMLLContextBudget.minimumOutputTokens)

    let estimatedTotal = ANEMLLContextBudget.estimatedTokens(plan.systemPrompt)
      + ANEMLLContextBudget.estimatedTokens(plan.transportPrompt)
      + ANEMLLContextBudget.templateReserveTokens
      + plan.maxOutputTokens
    XCTAssertLessThanOrEqual(estimatedTotal, 512)
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

  func testFreshConversationDoesNotRotateColdRuntime() {
    XCTAssertFalse(
      ANEMLLContextBudget.shouldRotateBeforeUserTurn(
        contextLength: 512,
        activeTurns: 0,
        isFreshConversation: true,
        isToolContinuation: false
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
    let transport = "TOOLS: read_file(path) | USER/TASK INPUT: AKTUELLE-FRAGE-42"

    let result = ANEMLLContextBudget.addingRecentConversationContext(
      to: transport,
      messages: messages,
      isToolContinuation: false,
      contextLength: 512
    )

    XCTAssertTrue(result.contains("PREVIOUS_USER: Vorherige Benutzerfrage"))
    XCTAssertTrue(result.contains("PREVIOUS_ASSISTANT: Vorherige Agentenantwort"))
    XCTAssertTrue(result.contains("CURRENT_TASK: AKTUELLE-FRAGE-42"))
  }
}
