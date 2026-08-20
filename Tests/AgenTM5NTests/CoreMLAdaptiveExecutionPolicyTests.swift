import XCTest
@testable import AgenTM5N

final class CoreMLAdaptiveExecutionPolicyTests: XCTestCase {
  func testManualStrategyPreservesSelectedComputeMode() {
    let route = CoreMLAdaptiveExecutionPolicy.evaluate(
      strategy: .manual,
      manualMode: .cpuAndGPU,
      workloadPreset: .interactive,
      decision: nil
    )

    XCTAssertEqual(route.mode, .cpuAndGPU)
    XCTAssertEqual(route.source, .manual)
    XCTAssertFalse(route.adaptiveRoutingApplied)
    XCTAssertFalse(route.allowsAutomaticFailover)
  }

  func testAdaptiveStrategyWithoutProfileFallsBackToAutomatic() {
    let route = CoreMLAdaptiveExecutionPolicy.evaluate(
      strategy: .adaptive,
      manualMode: .neuralEnginePreferred,
      workloadPreset: .interactive,
      decision: nil
    )

    XCTAssertEqual(route.mode, .automatic)
    XCTAssertEqual(route.source, .automaticFallback)
    XCTAssertEqual(route.confidence, .low)
    XCTAssertFalse(route.allowsAutomaticFailover)
  }

  func testLowConfidenceAdaptiveDecisionFallsBackToAutomatic() {
    let decision = makeDecision(
      expectedPredictions: 100,
      recommendedMode: .neuralEnginePreferred,
      confidence: .low
    )

    let route = CoreMLAdaptiveExecutionPolicy.evaluate(
      strategy: .adaptive,
      manualMode: .cpuOnly,
      workloadPreset: .interactive,
      decision: decision
    )

    XCTAssertEqual(route.mode, .automatic)
    XCTAssertEqual(route.source, .automaticFallback)
    XCTAssertFalse(route.adaptiveRoutingApplied)
  }

  func testHighConfidenceAdaptiveDecisionSelectsRecommendedMode() {
    let decision = makeDecision(
      expectedPredictions: 5_000,
      recommendedMode: .neuralEnginePreferred,
      confidence: .high
    )

    let route = CoreMLAdaptiveExecutionPolicy.evaluate(
      strategy: .adaptive,
      manualMode: .automatic,
      workloadPreset: .sustained,
      decision: decision
    )

    XCTAssertEqual(route.mode, .neuralEnginePreferred)
    XCTAssertEqual(route.source, .adaptive)
    XCTAssertEqual(route.expectedPredictions, 5_000)
    XCTAssertTrue(route.adaptiveRoutingApplied)
    XCTAssertTrue(route.allowsAutomaticFailover)
  }

  func testAdaptiveAutomaticRecommendationDoesNotNeedFailover() {
    let decision = makeDecision(
      expectedPredictions: 100,
      recommendedMode: .automatic,
      confidence: .high
    )

    let route = CoreMLAdaptiveExecutionPolicy.evaluate(
      strategy: .adaptive,
      manualMode: .neuralEnginePreferred,
      workloadPreset: .interactive,
      decision: decision
    )

    XCTAssertEqual(route.mode, .automatic)
    XCTAssertEqual(route.source, .adaptive)
    XCTAssertTrue(route.adaptiveRoutingApplied)
    XCTAssertFalse(route.allowsAutomaticFailover)
  }

  private func makeDecision(
    expectedPredictions: Int,
    recommendedMode: CoreMLComputeMode,
    confidence: CoreMLAdaptiveConfidence
  ) -> CoreMLAdaptiveRouteDecision {
    CoreMLAdaptiveRouteDecision(
      expectedPredictions: expectedPredictions,
      recommendedMode: recommendedMode,
      coldStartMode: .automatic,
      warmLatencyMode: .neuralEnginePreferred,
      aneBreakEvenPredictionsVersusAutomatic: 2_902,
      confidence: confidence,
      estimates: [],
      reason: "test"
    )
  }
}
