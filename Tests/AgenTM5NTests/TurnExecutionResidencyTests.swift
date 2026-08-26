import XCTest
@testable import AgenTM5N

final class TurnExecutionResidencyTests: XCTestCase {
  func testManualPlanPreservesConfiguredKeepAlive() {
    var operating = AgentOperatingLayerConfiguration.default
    operating.keepAlive = "15m"

    let plan = TurnExecutionPlan.manual(
      configuration: .default,
      operatingConfiguration: operating
    )

    XCTAssertEqual(plan.residencyAction, .preserveUserConfiguration)
    XCTAssertEqual(plan.operatingConfiguration.keepAlive, "15m")
  }

  func testHybridApplePlanIsObservationOnly() {
    let plan = TurnExecutionPlan.hybridAppleOnDevice(
      configuration: .default,
      operatingConfiguration: .default
    )

    XCTAssertEqual(
      plan.residencyAction,
      .observeOnly(.appleFoundationModels)
    )
  }

  func testAutomaticANEMLLPlanRequiresEndOfTurnEviction() throws {
    let profile = ModelProfile(
      name: "ANEMLL residency",
      runtime: .anemll,
      modelIdentifier: "/models/anemll",
      contextWindow: 512,
      estimatedMemoryMB: 4_096
    )
    let snapshot = healthySnapshot()

    let plan = try TurnExecutionPlan.automaticModelProfile(
      configuration: .default,
      operatingConfiguration: .default,
      profile: profile,
      resourceSnapshot: snapshot
    )

    XCTAssertEqual(plan.residencyAction, .evictANEMLLAfterTurn)
  }

  func testAutomaticOllamaPlanUsesThirtySecondKeepAlive() throws {
    var operating = AgentOperatingLayerConfiguration.default
    operating.keepAlive = "20m"
    let profile = ModelProfile(
      name: "Ollama residency",
      runtime: .ollamaLocal,
      modelIdentifier: "qwen3:8b",
      contextWindow: 8_192,
      estimatedMemoryMB: 4_096
    )

    let plan = try TurnExecutionPlan.automaticModelProfile(
      configuration: .default,
      operatingConfiguration: operating,
      profile: profile,
      resourceSnapshot: healthySnapshot()
    )

    XCTAssertEqual(
      plan.residencyAction,
      .shortOllamaKeepAlive(seconds: 30)
    )
    XCTAssertEqual(plan.operatingConfiguration.keepAlive, "30s")
    XCTAssertEqual(operating.keepAlive, "20m")
  }

  func testAutomaticMLXPlanIsObservationOnly() throws {
    let profile = ModelProfile(
      name: "MLX residency",
      runtime: .mlx,
      modelIdentifier: "mlx-model",
      contextWindow: 8_192,
      estimatedMemoryMB: 4_096
    )

    let plan = try TurnExecutionPlan.automaticModelProfile(
      configuration: .default,
      operatingConfiguration: .default,
      profile: profile,
      resourceSnapshot: healthySnapshot()
    )

    XCTAssertEqual(plan.residencyAction, .observeOnly(.mlx))
  }

  func testAutomaticCloudPlanHasNoLocalResidencyAction() throws {
    let profile = ModelProfile(
      name: "Cloud residency",
      runtime: .ollamaCloud,
      modelIdentifier: "cloud-model",
      baseURL: "https://ollama.example.invalid",
      contextWindow: 8_192
    )

    let plan = try TurnExecutionPlan.automaticModelProfile(
      configuration: .default,
      operatingConfiguration: .default,
      profile: profile,
      resourceSnapshot: nil
    )

    XCTAssertEqual(plan.residencyAction, .none)
  }

  private func healthySnapshot() -> AutomaticResourceSnapshot {
    AutomaticResourceSnapshot(
      thermalState: .nominal,
      physicalMemoryMB: 16_384,
      availableMemoryMB: 12_000,
      swapUsedMB: 0
    )
  }
}
