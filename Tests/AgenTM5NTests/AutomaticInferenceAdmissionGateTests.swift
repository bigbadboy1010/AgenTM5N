import Foundation
import XCTest
@testable import AgenTM5N

final class AutomaticInferenceAdmissionGateTests: XCTestCase {
  func testSeriousThermalPressureBlocksLocalAutomaticInference() {
    let profile = makeProfile(runtime: .anemll, estimatedMemoryMB: 4_096)
    let snapshot = makeSnapshot(
      thermalState: .serious,
      availableMemoryMB: 12_000,
      swapUsedMB: 0
    )

    XCTAssertThrowsError(
      try AutomaticInferenceAdmissionGate.validate(
        profile: profile,
        snapshot: snapshot
      )
    ) { error in
      XCTAssertEqual(
        error as? AutomaticInferenceAdmissionError,
        .thermalPressure(.serious)
      )
    }
  }

  func testCriticalThermalPressureBlocksLocalAutomaticInference() {
    let profile = makeProfile(runtime: .ollamaLocal, estimatedMemoryMB: 2_048)
    let snapshot = makeSnapshot(
      thermalState: .critical,
      availableMemoryMB: 12_000,
      swapUsedMB: 0
    )

    XCTAssertThrowsError(
      try AutomaticInferenceAdmissionGate.validate(
        profile: profile,
        snapshot: snapshot
      )
    ) { error in
      XCTAssertEqual(
        error as? AutomaticInferenceAdmissionError,
        .thermalPressure(.critical)
      )
    }
  }

  func testFairThermalStateIsAllowedWhenMemoryAndSwapAreHealthy() {
    let profile = makeProfile(runtime: .mlx, estimatedMemoryMB: 4_096)
    let snapshot = makeSnapshot(
      thermalState: .fair,
      availableMemoryMB: 12_000,
      swapUsedMB: 512
    )

    XCTAssertNoThrow(
      try AutomaticInferenceAdmissionGate.validate(
        profile: profile,
        snapshot: snapshot
      )
    )
  }

  func testSwapPressureBlocksAutomaticLocalInference() {
    let profile = makeProfile(runtime: .anemll, estimatedMemoryMB: 2_048)
    let snapshot = makeSnapshot(
      thermalState: .nominal,
      availableMemoryMB: 12_000,
      swapUsedMB: 2_049
    )

    XCTAssertThrowsError(
      try AutomaticInferenceAdmissionGate.validate(
        profile: profile,
        snapshot: snapshot
      )
    ) { error in
      XCTAssertEqual(
        error as? AutomaticInferenceAdmissionError,
        .swapPressure(usedMB: 2_049, limitMB: 2_048)
      )
    }
  }

  func testUnknownLiveMemoryFailsClosed() {
    let profile = makeProfile(runtime: .ollamaLocal, estimatedMemoryMB: 2_048)
    let snapshot = makeSnapshot(
      thermalState: .nominal,
      availableMemoryMB: nil,
      swapUsedMB: 0
    )

    XCTAssertThrowsError(
      try AutomaticInferenceAdmissionGate.validate(
        profile: profile,
        snapshot: snapshot
      )
    ) { error in
      XCTAssertEqual(
        error as? AutomaticInferenceAdmissionError,
        .monitoringUnavailable("available memory")
      )
    }
  }

  func testMissingMemoryEstimateFailsClosedForManagedLocalRuntime() {
    let profile = makeProfile(runtime: .anemll, estimatedMemoryMB: nil)
    let snapshot = makeSnapshot(
      thermalState: .nominal,
      availableMemoryMB: 12_000,
      swapUsedMB: 0
    )

    XCTAssertThrowsError(
      try AutomaticInferenceAdmissionGate.validate(
        profile: profile,
        snapshot: snapshot
      )
    ) { error in
      XCTAssertEqual(
        error as? AutomaticInferenceAdmissionError,
        .missingMemoryEstimate(.anemll)
      )
    }
  }

  func testInsufficientMemoryIncludesSystemReserve() {
    let profile = makeProfile(runtime: .mlx, estimatedMemoryMB: 4_096)
    let snapshot = makeSnapshot(
      thermalState: .nominal,
      availableMemoryMB: 7_000,
      swapUsedMB: 0,
      physicalMemoryMB: 16_384
    )

    XCTAssertThrowsError(
      try AutomaticInferenceAdmissionGate.validate(
        profile: profile,
        snapshot: snapshot
      )
    ) { error in
      XCTAssertEqual(
        error as? AutomaticInferenceAdmissionError,
        .insufficientMemory(
          requiredMB: 7_373,
          availableMB: 7_000,
          reserveMB: 3_277
        )
      )
    }
  }

  func testAppleFoundationModelsUsesSystemReserveWithoutFakeModelEstimate() {
    let profile = makeProfile(
      runtime: .appleFoundationModels,
      estimatedMemoryMB: nil
    )
    let snapshot = makeSnapshot(
      thermalState: .nominal,
      availableMemoryMB: 4_000,
      swapUsedMB: 0,
      physicalMemoryMB: 16_384
    )

    XCTAssertNoThrow(
      try AutomaticInferenceAdmissionGate.validate(
        profile: profile,
        snapshot: snapshot
      )
    )
  }

  func testCloudProfileDoesNotRequireLocalResourceSnapshot() {
    let profile = makeProfile(runtime: .ollamaCloud, estimatedMemoryMB: nil)

    XCTAssertNoThrow(
      try AutomaticInferenceAdmissionGate.validate(
        profile: profile,
        snapshot: nil
      )
    )
  }

  private func makeProfile(
    runtime: ModelProfileRuntime,
    estimatedMemoryMB: Int?
  ) -> ModelProfile {
    ModelProfile(
      name: "Admission test",
      runtime: runtime,
      modelIdentifier: "test-model",
      contextWindow: 8_192,
      estimatedMemoryMB: estimatedMemoryMB
    )
  }

  private func makeSnapshot(
    thermalState: AutomaticThermalState,
    availableMemoryMB: Int?,
    swapUsedMB: Int?,
    physicalMemoryMB: Int = 16_384
  ) -> AutomaticResourceSnapshot {
    AutomaticResourceSnapshot(
      thermalState: thermalState,
      physicalMemoryMB: physicalMemoryMB,
      availableMemoryMB: availableMemoryMB,
      swapUsedMB: swapUsedMB,
      capturedAt: Date(timeIntervalSince1970: 1_000)
    )
  }
}
