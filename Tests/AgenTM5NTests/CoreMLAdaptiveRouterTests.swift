import XCTest
@testable import AgenTM5N

final class CoreMLAdaptiveRouterTests: XCTestCase {
  func testM5DistilBERTInteractiveWorkloadPrefersAutomatic() {
    let decision = CoreMLAdaptiveRouter.evaluate(
      modelLabReport: nil,
      runtimeReport: m5DistilBERTRuntimeReport(),
      expectedPredictions: 100
    )

    XCTAssertEqual(decision.coldStartMode, .automatic)
    XCTAssertEqual(decision.warmLatencyMode, .neuralEnginePreferred)
    XCTAssertEqual(decision.recommendedMode, .automatic)
    XCTAssertEqual(decision.aneBreakEvenPredictionsVersusAutomatic, 2_902)
  }

  func testM5DistilBERTSustainedWorkloadPrefersANE() {
    let decision = CoreMLAdaptiveRouter.evaluate(
      modelLabReport: nil,
      runtimeReport: m5DistilBERTRuntimeReport(),
      expectedPredictions: 5_000
    )

    XCTAssertEqual(decision.recommendedMode, .neuralEnginePreferred)
    XCTAssertEqual(decision.warmLatencyMode, .neuralEnginePreferred)
  }

  func testDifferentOutputStructuresKeepAutomaticAsSafeChoice() {
    let base = m5DistilBERTRuntimeReport()
    let report = CoreMLRuntimeBenchmarkReport(
      results: base.results,
      fastestMode: .neuralEnginePreferred,
      outputsStructurallyEquivalent: false
    )

    let decision = CoreMLAdaptiveRouter.evaluate(
      modelLabReport: nil,
      runtimeReport: report,
      expectedPredictions: 10_000
    )

    XCTAssertEqual(decision.recommendedMode, .automatic)
    XCTAssertEqual(decision.confidence, .low)
  }

  func testGPUNeverWinsWhenBothColdAndWarmLatencyAreWorse() {
    let decision = CoreMLAdaptiveRouter.evaluate(
      modelLabReport: nil,
      runtimeReport: m5DistilBERTRuntimeReport(),
      expectedPredictions: 100_000
    )

    XCTAssertNotEqual(decision.recommendedMode, .cpuAndGPU)
    let gpu = decision.estimates.first(where: { $0.mode == .cpuAndGPU })
    let ane = decision.estimates.first(where: { $0.mode == .neuralEnginePreferred })
    XCTAssertNotNil(gpu)
    XCTAssertNotNil(ane)
    XCTAssertGreaterThan(
      gpu?.estimatedTotalMilliseconds ?? 0,
      ane?.estimatedTotalMilliseconds ?? .greatestFiniteMagnitude
    )
  }

  private func m5DistilBERTRuntimeReport() -> CoreMLRuntimeBenchmarkReport {
    CoreMLRuntimeBenchmarkReport(
      results: [
        result(
          mode: .automatic,
          load: 72.08,
          first: 5.31,
          mean: 2.26,
          p50: 2.22,
          p95: 2.47
        ),
        result(
          mode: .cpuAndGPU,
          load: 437.05,
          first: 1_195.55,
          mean: 4.97,
          p50: 4.50,
          p95: 8.41
        ),
        result(
          mode: .neuralEnginePreferred,
          load: 1_554.10,
          first: 2.49,
          mean: 1.73,
          p50: 1.71,
          p95: 1.84
        ),
      ],
      fastestMode: .neuralEnginePreferred,
      outputsStructurallyEquivalent: true
    )
  }

  private func result(
    mode: CoreMLComputeMode,
    load: Double,
    first: Double,
    mean: Double,
    p50: Double,
    p95: Double
  ) -> CoreMLRuntimeBenchmarkModeResult {
    CoreMLRuntimeBenchmarkModeResult(
      mode: mode,
      succeeded: true,
      modelLoadMilliseconds: load,
      firstPredictionMilliseconds: first,
      warmMeanMilliseconds: mean,
      warmP50Milliseconds: p50,
      warmP95Milliseconds: p95,
      warmRuns: 10,
      outputSignature: "output:multiArray:[1,2]:65568",
      errorDescription: nil
    )
  }
}
