import Foundation
import XCTest
@testable import AgenTM5N

final class GenerationLifecycleTests: XCTestCase {
  @MainActor
  func testStopKeepsSendGateClosedUntilOwningTurnFinishesCleanup() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgenTM5N-generation-lifecycle-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let state = AppState(
      configurationStore: JSONDocumentStore<AppConfiguration>(
        url: root.appendingPathComponent("configuration.json"),
        defaultValue: .default
      ),
      conversationStore: JSONDocumentStore<[ChatMessage]>(
        url: root.appendingPathComponent("conversation.json"),
        defaultValue: []
      ),
      sshHostStore: JSONDocumentStore<[SSHHost]>(
        url: root.appendingPathComponent("ssh-hosts.json"),
        defaultValue: []
      ),
      vaultStore: VaultStore(url: root.appendingPathComponent("vault.json"))
    )

    // Use a deliberately unreachable local endpoint. The important assertions
    // occur synchronously before the generation task is allowed to run.
    state.configuration.providerKind = .ollamaLocal
    state.configuration.baseURL = "http://127.0.0.1:1"
    state.configuration.model = "resource-safety-test"
    state.inputText = "first turn"

    state.sendMessage()

    guard case .running(let firstTurnID) = state.generationPhase else {
      return XCTFail("sendMessage must enter running synchronously")
    }
    XCTAssertTrue(state.isGenerating)

    state.stopGeneration()

    XCTAssertEqual(state.generationPhase, .cancelling(turnID: firstTurnID))
    XCTAssertTrue(
      state.isGenerating,
      "Stop must not advertise idle before the owning task has finished cleanup"
    )

    state.inputText = "second turn"
    state.sendMessage()
    XCTAssertEqual(state.generationPhase, .cancelling(turnID: firstTurnID))
    XCTAssertEqual(state.inputText, "second turn")

    // Let the cancelled generation task enter, observe cancellation, release
    // any resource lease, and become idle through the single cleanup path.
    for _ in 0..<200 where state.generationPhase != .idle {
      await Task.yield()
      try? await Task.sleep(for: .milliseconds(5))
    }

    XCTAssertEqual(state.generationPhase, .idle)
    XCTAssertFalse(state.isGenerating)
  }

  func testGenerationPhaseCarriesTurnIdentityAcrossCancellationAndCleanup() {
    let id = UUID()
    XCTAssertEqual(GenerationPhase.running(turnID: id).turnID, id)
    XCTAssertEqual(GenerationPhase.cancelling(turnID: id).turnID, id)
    XCTAssertEqual(GenerationPhase.cleaningUp(turnID: id).turnID, id)
    XCTAssertNil(GenerationPhase.idle.turnID)
    XCTAssertTrue(GenerationPhase.idle.acceptsNewTurn)
    XCTAssertFalse(GenerationPhase.running(turnID: id).acceptsNewTurn)
  }
}
