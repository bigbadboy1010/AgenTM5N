import XCTest
@testable import AgenTM5N

final class CoreMLModelLabTests: XCTestCase {
  func testBenchmarkModesAreStableAndExcludeCPUOnly() {
    XCTAssertEqual(
      CoreMLModelLab.benchmarkModes,
      [.automatic, .cpuAndGPU, .neuralEnginePreferred]
    )
  }

  func testSuccessfulHighCoverageANEPlanIsRecommended() {
    let automatic = modeResult(
      .automatic,
      report: report(
        mode: .automatic,
        total: 100,
        cpu: 5,
        gpu: 10,
        ane: 75,
        unknown: 10,
        aneSupported: 80
      )
    )
    let cpuGPU = modeResult(
      .cpuAndGPU,
      report: report(
        mode: .cpuAndGPU,
        total: 100,
        cpu: 10,
        gpu: 90,
        ane: 0,
        unknown: 0,
        aneSupported: 0
      )
    )
    let cpuANE = modeResult(
      .neuralEnginePreferred,
      report: report(
        mode: .neuralEnginePreferred,
        total: 100,
        cpu: 10,
        gpu: 0,
        ane: 80,
        unknown: 10,
        aneSupported: 85
      )
    )

    let evaluation = CoreMLModelLab.evaluate(
      modelName: "ANEModel.mlmodelc",
      results: [automatic, cpuGPU, cpuANE]
    )

    XCTAssertEqual(evaluation.aneSuitability, .high)
    XCTAssertGreaterThanOrEqual(evaluation.aneSuitabilityScore, 80)
    XCTAssertEqual(evaluation.recommendedMode, .neuralEnginePreferred)
  }

  func testFailedCPUANEWithNoAutomaticANEEvidenceIsLowSuitability() {
    let automatic = modeResult(
      .automatic,
      report: report(
        mode: .automatic,
        total: 5_952,
        cpu: 0,
        gpu: 2_694,
        ane: 0,
        unknown: 3_258,
        aneSupported: 0
      )
    )
    let cpuGPU = modeResult(
      .cpuAndGPU,
      report: report(
        mode: .cpuAndGPU,
        total: 5_952,
        cpu: 0,
        gpu: 2_694,
        ane: 0,
        unknown: 3_258,
        aneSupported: 0
      )
    )
    let cpuANE = CoreMLModelLabModeResult(
      mode: .neuralEnginePreferred,
      succeeded: false,
      durationMilliseconds: 2_000,
      report: nil,
      errorDescription: "execution plan error -14"
    )

    let evaluation = CoreMLModelLab.evaluate(
      modelName: "StatefulMistral.mlmodelc",
      results: [automatic, cpuGPU, cpuANE]
    )

    XCTAssertEqual(evaluation.aneSuitability, .low)
    XCTAssertEqual(evaluation.aneSuitabilityScore, 0)
    XCTAssertEqual(evaluation.recommendedMode, .automatic)
  }

  func testSuccessfulCPUANEWithoutResolvedANESignalStaysInconclusive() {
    let cpuANE = modeResult(
      .neuralEnginePreferred,
      report: report(
        mode: .neuralEnginePreferred,
        total: 100,
        cpu: 0,
        gpu: 0,
        ane: 0,
        unknown: 100,
        aneSupported: 0
      )
    )

    let evaluation = CoreMLModelLab.evaluate(
      modelName: "UnknownPlacement.mlmodelc",
      results: [cpuANE]
    )

    XCTAssertEqual(evaluation.aneSuitability, .inconclusive)
    XCTAssertEqual(evaluation.aneSuitabilityScore, 35)
    XCTAssertEqual(evaluation.recommendedMode, .cpuOnly)
  }

  private func modeResult(
    _ mode: CoreMLComputeMode,
    report: CoreMLComputePlanReport
  ) -> CoreMLModelLabModeResult {
    CoreMLModelLabModeResult(
      mode: mode,
      succeeded: true,
      durationMilliseconds: 100,
      report: report,
      errorDescription: nil
    )
  }

  private func report(
    mode: CoreMLComputeMode,
    total: Int,
    cpu: Int,
    gpu: Int,
    ane: Int,
    unknown: Int,
    aneSupported: Int
  ) -> CoreMLComputePlanReport {
    CoreMLComputePlanReport(
      modelType: "ML Program",
      computeMode: mode,
      totalOperations: total,
      preferredCPUOperations: cpu,
      preferredGPUOperations: gpu,
      preferredNeuralEngineOperations: ane,
      unknownPreferredOperations: unknown,
      neuralEngineSupportedOperations: aneSupported,
      cpuEstimatedWeight: 0,
      gpuEstimatedWeight: 0,
      neuralEngineEstimatedWeight: 0,
      unknownEstimatedWeight: 0,
      availableDevices: [.cpu, .gpu, .neuralEngine],
      stateful: false,
      stateFeatureNames: [],
      topOperations: []
    )
  }
}
