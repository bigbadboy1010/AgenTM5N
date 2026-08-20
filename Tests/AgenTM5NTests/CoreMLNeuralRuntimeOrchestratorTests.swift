import XCTest
@testable import AgenTM5N

final class CoreMLNeuralRuntimeOrchestratorTests: XCTestCase {
  func testWorkspaceSearchEmbeddingIsOneShot() {
    let workload = CoreMLNeuralWorkload.workspaceEmbeddingQuery

    XCTAssertEqual(workload.kind, .workspaceEmbeddingQuery)
    XCTAssertEqual(workload.expectedPredictions, 1)
    XCTAssertEqual(workload.itemCount, 1)
  }

  func testWorkspaceIndexEmbeddingUsesActualBatchSize() {
    let workload = CoreMLNeuralWorkload.workspaceEmbeddingBatch(count: 1_200)

    XCTAssertEqual(workload.kind, .workspaceEmbeddingBatch)
    XCTAssertEqual(workload.expectedPredictions, 1_200)
    XCTAssertEqual(workload.itemCount, 1_200)
  }

  func testWorkspaceIndexEmbeddingClampsInvalidBatchSize() {
    let workload = CoreMLNeuralWorkload.workspaceEmbeddingBatch(count: 0)

    XCTAssertEqual(workload.expectedPredictions, 1)
    XCTAssertEqual(workload.itemCount, 1)
  }

  func testManualWorkloadSizedRoutePreservesSelectedMode() {
    let route = CoreMLAdaptiveExecutionPolicy.evaluate(
      strategy: .manual,
      manualMode: .cpuAndGPU,
      expectedPredictions: 1_200,
      decision: nil
    )

    XCTAssertEqual(route.mode, .cpuAndGPU)
    XCTAssertEqual(route.source, .manual)
    XCTAssertEqual(route.expectedPredictions, 1_200)
  }

  func testAdaptiveWorkloadSizedRouteUsesDecisionPredictionCount() {
    let decision = CoreMLAdaptiveRouteDecision(
      expectedPredictions: 5_000,
      recommendedMode: .neuralEnginePreferred,
      coldStartMode: .automatic,
      warmLatencyMode: .neuralEnginePreferred,
      aneBreakEvenPredictionsVersusAutomatic: 2_902,
      confidence: .high,
      estimates: [],
      reason: "test"
    )

    let route = CoreMLAdaptiveExecutionPolicy.evaluate(
      strategy: .adaptive,
      manualMode: .automatic,
      expectedPredictions: 5_000,
      decision: decision
    )

    XCTAssertEqual(route.mode, .neuralEnginePreferred)
    XCTAssertEqual(route.source, .adaptive)
    XCTAssertEqual(route.expectedPredictions, 5_000)
    XCTAssertEqual(route.confidence, .high)
  }
}
