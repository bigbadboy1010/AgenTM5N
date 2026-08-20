import XCTest
@testable import AgenTM5N

final class InferenceResourceGovernorTests: XCTestCase {
  func testSecondHeavyRuntimeIsRejectedWhileLeaseIsActive() async throws {
    let governor = InferenceResourceGovernor()
    let ownerA = UUID()
    let ownerB = UUID()
    let first = try await governor.acquire(runtime: .anemll, ownerID: ownerA)

    do {
      _ = try await governor.acquire(runtime: .mlx, ownerID: ownerB)
      XCTFail("Expected fail-closed busy error")
    } catch let error as InferenceResourceGovernorError {
      XCTAssertEqual(error, .busy(active: .anemll, requested: .mlx))
    }

    let snapshot = await governor.snapshot()
    XCTAssertEqual(snapshot.activeLease, first)
  }

  func testReleaseAllowsNextHeavyRuntime() async throws {
    let governor = InferenceResourceGovernor()
    let first = try await governor.acquire(runtime: .ollamaLocal, ownerID: UUID())
    await governor.release(first)

    let second = try await governor.acquire(runtime: .appleFoundationModels, ownerID: UUID())
    XCTAssertEqual(second.runtime, .appleFoundationModels)
    let snapshot = await governor.snapshot()
    XCTAssertTrue(snapshot.isBusy)
  }

  func testStaleLeaseCannotReleaseNewerExecution() async throws {
    let governor = InferenceResourceGovernor()
    let stale = try await governor.acquire(runtime: .anemll, ownerID: UUID())
    await governor.release(stale)

    let current = try await governor.acquire(runtime: .mlx, ownerID: UUID())
    await governor.release(stale)

    let snapshot = await governor.snapshot()
    XCTAssertEqual(snapshot.activeLease?.id, current.id)
  }

  func testCloudProfileDoesNotRequireHeavyLocalLease() {
    XCTAssertNil(HeavyInferenceRuntime(modelProfileRuntime: .ollamaCloud))
    XCTAssertEqual(HeavyInferenceRuntime(modelProfileRuntime: .anemll), .anemll)
    XCTAssertEqual(HeavyInferenceRuntime(modelProfileRuntime: .mlx), .mlx)
    XCTAssertEqual(HeavyInferenceRuntime(modelProfileRuntime: .ollamaLocal), .ollamaLocal)
    XCTAssertEqual(
      HeavyInferenceRuntime(modelProfileRuntime: .appleFoundationModels),
      .appleFoundationModels
    )
  }

  func testAutomaticBudgetDefaultsAreConservative() {
    let budget = AutomaticInferenceBudget.conservative
    XCTAssertEqual(budget.timeoutSeconds, 120)
    XCTAssertEqual(budget.maximumToolRounds, 4)
  }

  func testAutomaticBudgetClampsUnsafeValues() {
    XCTAssertEqual(
      AutomaticInferenceBudget(timeoutSeconds: 1, maximumToolRounds: 0),
      AutomaticInferenceBudget(timeoutSeconds: 30, maximumToolRounds: 1)
    )
    XCTAssertEqual(
      AutomaticInferenceBudget(timeoutSeconds: 9_999, maximumToolRounds: 99),
      AutomaticInferenceBudget(timeoutSeconds: 300, maximumToolRounds: 8)
    )
  }
}
