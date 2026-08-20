import XCTest
@testable import AgenTM5N

final class ANEMLLPersistentProtocolHardeningTests: XCTestCase {
  func testModelGeneratedYouMarkerDoesNotEndTurnBeforeMetrics() {
    let partial = """
    Assistant: Beispiel eines Chat-Transkripts.
    You: diese Zeile stammt aus der Modellantwort
    Assistant: und die Antwort läuft weiter
    """

    XCTAssertFalse(
      ANEMLLInteractiveProtocol.containsTerminalPrompt(
        partial,
        requireCompletedTurn: true
      )
    )
  }

  func testCompletedTurnRequiresTerminalPromptAfterMetrics() {
    let completed = """
    Assistant: Fertige Antwort.
    84.7 t/s, TTFT: 14.8ms (1900.2 t/s), 12 tokens [Stop: eos] [History: 42 tokens]
    You:
    """

    XCTAssertTrue(
      ANEMLLInteractiveProtocol.containsTerminalPrompt(
        completed,
        requireCompletedTurn: true
      )
    )
  }

  func testParserKeepsModelGeneratedYouTextUntilMetricsBoundary() throws {
    let completed = """
    Assistant: Vor dem Marker.
    You: Modellinhalt, kein CLI-Prompt.
    Danach geht die Antwort weiter.
    84.7 t/s, TTFT: 14.8ms (1900.2 t/s), 16 tokens [Stop: eos] [History: 46 tokens]
    You:
    """

    let turn = try ANEMLLInteractiveProtocol.parseTurn(completed)
    XCTAssertTrue(turn.response.contains("You: Modellinhalt"))
    XCTAssertTrue(turn.response.contains("Danach geht die Antwort weiter."))
    XCTAssertFalse(turn.response.contains("84.7 t/s"))
  }

  func testIncompleteUTF8IsNotLossilyDecoded() {
    let full = Data("Grüße".utf8)

    // Remove the final ASCII "e" and the final byte of the two-byte "ß"
    // scalar. The remaining bytes genuinely end inside a UTF-8 scalar.
    let split = full.prefix(full.count - 2)

    XCTAssertNil(String(data: Data(split), encoding: .utf8))
    XCTAssertEqual(String(data: full, encoding: .utf8), "Grüße")
  }
}
