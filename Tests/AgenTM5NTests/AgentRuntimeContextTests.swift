import Foundation
import XCTest
@testable import AgenTM5N

final class AgentRuntimeContextTests: XCTestCase {
  func testProviderInstructionIsCompactAndSilent() {
    let instruction = AgentRuntimeContext.providerInstruction()

    XCTAssertTrue(instruction.contains("Answer the latest user request naturally"))
    XCTAssertTrue(instruction.contains("Apply this guidance silently"))
    XCTAssertFalse(instruction.contains("authoritative current task"))
    XCTAssertFalse(instruction.contains("RUNTIME GROUNDING — mandatory"))
    XCTAssertFalse(instruction.contains("If a tool returns success"))
  }

  func testTemporalContextIsCompactAndCarriesClockAndTimeZone() {
    let timeZone = TimeZone(identifier: "Europe/Vienna")!
    let now = Date(timeIntervalSince1970: 1_787_245_200)
    let context = AgentRuntimeContext.currentTemporalContext(
      now: now,
      timeZone: timeZone
    )

    XCTAssertTrue(context.contains("Current local Mac time:"))
    XCTAssertTrue(context.contains("Europe/Vienna"))
    XCTAssertTrue(context.contains("+02:00"))
    XCTAssertTrue(context.contains("Use this silently"))
    XCTAssertEqual(context.split(separator: "\n").count, 1)
    XCTAssertFalse(context.contains("CURRENT MAC DATE AND TIME"))
    XCTAssertFalse(context.contains("Temporal rules:"))
  }
}
