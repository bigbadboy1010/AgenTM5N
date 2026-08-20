import Foundation
import XCTest
@testable import AgenTM5N

final class AgentRuntimeContextTests: XCTestCase {
  func testProviderInstructionMakesLatestUserTurnAuthoritative() {
    let instruction = AgentRuntimeContext.providerInstruction()

    XCTAssertTrue(instruction.contains("latest user message is the authoritative current task"))
    XCTAssertTrue(instruction.contains("conversation history only"))
    XCTAssertTrue(instruction.contains("exact-output request"))
    XCTAssertTrue(instruction.contains("unless the latest user message explicitly asks for it again"))
  }

  func testProviderInstructionRejectsImitationOfConflictingEarlierAnswer() {
    let instruction = AgentRuntimeContext.providerInstruction()

    XCTAssertTrue(instruction.contains("If an earlier assistant answer conflicts with the latest user request"))
    XCTAssertTrue(instruction.contains("do not imitate the earlier answer"))
  }

  func testTemporalContextStillCarriesRuntimeClockAndTimeZone() {
    let timeZone = TimeZone(identifier: "Europe/Vienna")!
    let now = Date(timeIntervalSince1970: 1_787_245_200)
    let context = AgentRuntimeContext.currentTemporalContext(
      now: now,
      timeZone: timeZone
    )

    XCTAssertTrue(context.contains("CURRENT MAC DATE AND TIME"))
    XCTAssertTrue(context.contains("Europe/Vienna"))
    XCTAssertTrue(context.contains("UTC+02:00"))
  }
}
