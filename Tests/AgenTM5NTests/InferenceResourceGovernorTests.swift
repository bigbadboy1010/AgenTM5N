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

  func testMismatchedOwnerCannotReleaseActiveLease() async throws {
    let governor = InferenceResourceGovernor()
    let current = try await governor.acquire(runtime: .anemll, ownerID: UUID())
    let forged = InferenceResourceLease(
      id: current.id,
      runtime: current.runtime,
      ownerID: UUID(),
      startedAt: current.startedAt
    )

    await governor.release(forged)

    let snapshot = await governor.snapshot()
    XCTAssertEqual(snapshot.activeLease, current)
  }

  func testWithLeaseReleasesAfterSuccess() async throws {
    let governor = InferenceResourceGovernor()
    let result = try await governor.withLease(
      runtime: .anemll,
      ownerID: UUID()
    ) {
      "done"
    }

    XCTAssertEqual(result, "done")
    let snapshot = await governor.snapshot()
    XCTAssertFalse(snapshot.isBusy)
  }

  func testWithLeaseReleasesAfterThrow() async throws {
    enum Expected: Error { case failure }
    let governor = InferenceResourceGovernor()

    do {
      _ = try await governor.withLease(
        runtime: .mlx,
        ownerID: UUID()
      ) { () async throws -> String in
        throw Expected.failure
      }
      XCTFail("Expected operation to throw")
    } catch Expected.failure {
      // expected
    }

    let snapshot = await governor.snapshot()
    XCTAssertFalse(snapshot.isBusy)
  }

  func testANEMLLLeaseIsRetainedWhenRuntimeCleanupIsUnconfirmed() async throws {
    let governor = InferenceResourceGovernor(
      anemllRequiresRecovery: { true }
    )
    let ownerID = UUID()
    let lease = try await governor.acquire(runtime: .anemll, ownerID: ownerID)

    await governor.release(lease)

    let snapshot = await governor.snapshot()
    XCTAssertEqual(snapshot.activeLease, lease)

    do {
      _ = try await governor.acquire(runtime: .mlx, ownerID: UUID())
      XCTFail("A second heavy runtime must remain blocked after failed ANEMLL cleanup")
    } catch let error as InferenceResourceGovernorError {
      XCTAssertEqual(error, .busy(active: .anemll, requested: .mlx))
    }
  }

  func testANEMLLLeaseIsReleasedAfterConfirmedCleanup() async throws {
    let governor = InferenceResourceGovernor(
      anemllRequiresRecovery: { false }
    )
    let lease = try await governor.acquire(runtime: .anemll, ownerID: UUID())

    await governor.release(lease)

    let snapshot = await governor.snapshot()
    XCTAssertFalse(snapshot.isBusy)
  }

  func testOldLeaseFailsClosedAndRequiresRecoveryInsteadOfAutoSteal() async throws {
    let start = Date(timeIntervalSince1970: 1_000)
    final class Clock: @unchecked Sendable {
      private let lock = NSLock()
      private var value: Date
      init(_ value: Date) { self.value = value }
      func read() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
      }
      func advance(seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
      }
    }

    let clock = Clock(start)
    let governor = InferenceResourceGovernor(
      staleAfterSeconds: 30,
      now: { clock.read() }
    )
    _ = try await governor.acquire(runtime: .anemll, ownerID: UUID())
    clock.advance(seconds: 31)

    do {
      _ = try await governor.acquire(runtime: .ollamaLocal, ownerID: UUID())
      XCTFail("Expired lease must never be auto-stolen")
    } catch let error as InferenceResourceGovernorError {
      XCTAssertEqual(error, .recoveryRequired(active: .anemll, ageSeconds: 31))
    }

    let snapshot = await governor.snapshot()
    XCTAssertTrue(snapshot.isBusy)
    XCTAssertTrue(snapshot.requiresRecovery)
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

  func testActiveProviderMapsToExpectedHeavyRuntime() {
    XCTAssertNil(
      HeavyInferenceRuntime(
        providerKind: .ollamaCloud,
        localInferenceRuntime: .ollama
      )
    )
    XCTAssertEqual(
      HeavyInferenceRuntime(
        providerKind: .appleOnDevice,
        localInferenceRuntime: .ollama
      ),
      .appleFoundationModels
    )
    XCTAssertEqual(
      HeavyInferenceRuntime(
        providerKind: .ollamaLocal,
        localInferenceRuntime: .ollama
      ),
      .ollamaLocal
    )
    XCTAssertEqual(
      HeavyInferenceRuntime(
        providerKind: .ollamaLocal,
        localInferenceRuntime: .mlxServer
      ),
      .mlx
    )
    XCTAssertEqual(
      HeavyInferenceRuntime(
        providerKind: .ollamaLocal,
        localInferenceRuntime: .anemll
      ),
      .anemll
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
      AutomaticInferenceBudget(timeoutSeconds: 180, maximumToolRounds: 8)
    )
  }

  func testAutomaticBudgetIsRuntimeAndContextAware() {
    XCTAssertEqual(
      AutomaticInferenceBudget.automatic(runtime: .anemll, contextWindow: 512),
      AutomaticInferenceBudget(timeoutSeconds: 45, maximumToolRounds: 1)
    )
    XCTAssertEqual(
      AutomaticInferenceBudget.automatic(runtime: .appleFoundationModels, contextWindow: 8_192),
      AutomaticInferenceBudget(timeoutSeconds: 60, maximumToolRounds: 4)
    )
    XCTAssertEqual(
      AutomaticInferenceBudget.automatic(runtime: .ollamaLocal, contextWindow: 8_192),
      AutomaticInferenceBudget(timeoutSeconds: 120, maximumToolRounds: 4)
    )
  }
}
