import XCTest
@testable import AgenTM5N

final class AutomaticRuntimeResidencyPolicyTests: XCTestCase {
  func testManualTurnPreservesUserResidencyConfiguration() {
    XCTAssertEqual(
      AutomaticRuntimeResidencyPolicy.action(
        origin: .manualProvider,
        runtime: .ollamaLocal
      ),
      .preserveUserConfiguration
    )
  }

  func testHybridAppleIsObservationOnly() {
    XCTAssertEqual(
      AutomaticRuntimeResidencyPolicy.action(
        origin: .hybridAppleOnDevice,
        runtime: .appleFoundationModels
      ),
      .observeOnly(.appleFoundationModels)
    )
  }

  func testAutomaticANEMLLIsEvictedAfterCompleteTurn() {
    XCTAssertEqual(
      AutomaticRuntimeResidencyPolicy.action(
        origin: .automaticModelProfile,
        runtime: .anemll
      ),
      .evictANEMLLAfterTurn
    )
  }

  func testAutomaticOllamaUsesShortKeepAliveWithoutPerRoundEviction() {
    let action = AutomaticRuntimeResidencyPolicy.action(
      origin: .automaticModelProfile,
      runtime: .ollamaLocal
    )
    XCTAssertEqual(action, .shortOllamaKeepAlive(seconds: 30))

    var operating = AgentOperatingLayerConfiguration.default
    operating.keepAlive = "20m"
    let adjusted = AutomaticRuntimeResidencyPolicy.applying(
      action,
      to: operating
    )

    XCTAssertEqual(adjusted.keepAlive, "30s")
    XCTAssertEqual(operating.keepAlive, "20m")
  }

  func testAutomaticMLXIsObservationOnly() {
    XCTAssertEqual(
      AutomaticRuntimeResidencyPolicy.action(
        origin: .automaticModelProfile,
        runtime: .mlx
      ),
      .observeOnly(.mlx)
    )
  }

  func testAutomaticAppleIsObservationOnly() {
    XCTAssertEqual(
      AutomaticRuntimeResidencyPolicy.action(
        origin: .automaticModelProfile,
        runtime: .appleFoundationModels
      ),
      .observeOnly(.appleFoundationModels)
    )
  }

  func testCloudHasNoLocalResidencyAction() {
    XCTAssertEqual(
      AutomaticRuntimeResidencyPolicy.action(
        origin: .automaticModelProfile,
        runtime: .ollamaCloud
      ),
      .none
    )
  }

  func testANEMLLCoordinatorSucceedsOnlyAfterConfirmedExit() async throws {
    let coordinator = AutomaticRuntimeResidencyCoordinator(
      shutdownANEMLL: { true }
    )

    try await coordinator.finalize(action: .evictANEMLLAfterTurn)
  }

  func testANEMLLCoordinatorPropagatesUnconfirmedExit() async {
    let coordinator = AutomaticRuntimeResidencyCoordinator(
      shutdownANEMLL: { false }
    )

    do {
      try await coordinator.finalize(action: .evictANEMLLAfterTurn)
      XCTFail("Expected fail-closed ANEMLL residency cleanup error")
    } catch let error as AutomaticRuntimeResidencyCleanupError {
      XCTAssertEqual(error, .anemllExitUnconfirmed)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testNonANEMLLFinalizationDoesNotInvokeANEMLLShutdown() async throws {
    actor Counter {
      private(set) var value = 0
      func increment() { value += 1 }
    }

    let counter = Counter()
    let coordinator = AutomaticRuntimeResidencyCoordinator(
      shutdownANEMLL: {
        await counter.increment()
        return true
      }
    )

    try await coordinator.finalize(action: .shortOllamaKeepAlive(seconds: 30))
    try await coordinator.finalize(action: .observeOnly(.mlx))
    try await coordinator.finalize(action: .observeOnly(.appleFoundationModels))
    try await coordinator.finalize(action: .none)

    let count = await counter.value
    XCTAssertEqual(count, 0)
  }
}
