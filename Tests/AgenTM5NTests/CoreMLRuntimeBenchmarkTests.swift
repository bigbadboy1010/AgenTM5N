import XCTest
@testable import AgenTM5N

final class CoreMLRuntimeBenchmarkTests: XCTestCase {
  func testBenchmarkModesMatchModelLabAcceleratedModes() {
    XCTAssertEqual(
      CoreMLRuntimeBenchmark.benchmarkModes,
      [.automatic, .cpuAndGPU, .neuralEnginePreferred]
    )
  }

  func testFastestWarmP50IsSelected() {
    let report = CoreMLRuntimeBenchmark.evaluate(
      results: [
        result(.automatic, p50: 8.0, signature: "out:multiArray"),
        result(.cpuAndGPU, p50: 10.0, signature: "out:multiArray"),
        result(.neuralEnginePreferred, p50: 5.0, signature: "out:multiArray"),
      ]
    )

    XCTAssertEqual(report.fastestMode, .neuralEnginePreferred)
    XCTAssertTrue(report.outputsStructurallyEquivalent)
  }

  func testFailedModeDoesNotPreventSuccessfulComparison() {
    let failed = CoreMLRuntimeBenchmarkModeResult(
      mode: .neuralEnginePreferred,
      succeeded: false,
      modelLoadMilliseconds: 25,
      firstPredictionMilliseconds: nil,
      warmMeanMilliseconds: nil,
      warmP50Milliseconds: nil,
      warmP95Milliseconds: nil,
      warmRuns: 0,
      outputSignature: nil,
      errorDescription: "plan failed"
    )

    let report = CoreMLRuntimeBenchmark.evaluate(
      results: [
        result(.automatic, p50: 7.0, signature: "out:multiArray"),
        result(.cpuAndGPU, p50: 9.0, signature: "out:multiArray"),
        failed,
      ]
    )

    XCTAssertEqual(report.fastestMode, .automatic)
    XCTAssertTrue(report.outputsStructurallyEquivalent)
  }

  func testDifferentOutputStructuresAreFlagged() {
    let report = CoreMLRuntimeBenchmark.evaluate(
      results: [
        result(.automatic, p50: 7.0, signature: "out:multiArray"),
        result(.cpuAndGPU, p50: 8.0, signature: "out:string"),
      ]
    )

    XCTAssertFalse(report.outputsStructurallyEquivalent)
  }

  private func result(
    _ mode: CoreMLComputeMode,
    p50: Double,
    signature: String
  ) -> CoreMLRuntimeBenchmarkModeResult {
    CoreMLRuntimeBenchmarkModeResult(
      mode: mode,
      succeeded: true,
      modelLoadMilliseconds: 20,
      firstPredictionMilliseconds: p50 + 2,
      warmMeanMilliseconds: p50 + 0.5,
      warmP50Milliseconds: p50,
      warmP95Milliseconds: p50 + 1,
      warmRuns: 10,
      outputSignature: signature,
      errorDescription: nil
    )
  }
}
