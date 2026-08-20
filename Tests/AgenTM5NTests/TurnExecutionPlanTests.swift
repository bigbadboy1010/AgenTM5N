import XCTest
@testable import AgenTM5N

final class TurnExecutionPlanTests: XCTestCase {
  func testManualPlanCapturesConfigurationByValue() {
    var configuration = AppConfiguration.default
    configuration.providerKind = .ollamaLocal
    configuration.baseURL = "http://127.0.0.1:11434"
    configuration.model = "qwen3:8b"
    configuration.workspacePath = "/tmp/original-workspace"
    configuration.permissionMode = .workspaceTrusted
    configuration.maxToolIterations = 37

    var operatingConfiguration = AgentOperatingLayerConfiguration.default
    operatingConfiguration.localInferenceRuntime = .ollama
    operatingConfiguration.numContext = 16_384

    let turnID = UUID()
    let plan = TurnExecutionPlan.manual(
      turnID: turnID,
      configuration: configuration,
      operatingConfiguration: operatingConfiguration
    )

    configuration.model = "changed-after-plan"
    configuration.workspacePath = "/tmp/changed"
    operatingConfiguration.localInferenceRuntime = .anemll

    XCTAssertEqual(plan.turnID, turnID)
    XCTAssertEqual(plan.origin, .manualProvider)
    XCTAssertEqual(plan.configuration.model, "qwen3:8b")
    XCTAssertEqual(plan.configuration.workspacePath, "/tmp/original-workspace")
    XCTAssertEqual(plan.configuration.permissionMode, .workspaceTrusted)
    XCTAssertEqual(plan.configuration.maxToolIterations, 37)
    XCTAssertEqual(plan.operatingConfiguration.localInferenceRuntime, .ollama)
    XCTAssertEqual(plan.operatingConfiguration.numContext, 16_384)
    XCTAssertEqual(plan.heavyRuntime, .ollamaLocal)
    XCTAssertNil(plan.automaticBudget)
  }

  func testHybridApplePlanDoesNotMutatePersistedUserConfiguration() {
    let secretID = UUID()
    var configuration = AppConfiguration.default
    configuration.providerKind = .ollamaCloud
    configuration.baseURL = "https://ollama.example.invalid"
    configuration.model = "cloud-model"
    configuration.apiKeySecretID = secretID
    configuration.systemPrompt = "Persistent user prompt"
    configuration.workspacePath = "/tmp/workspace"
    configuration.permissionMode = .fullAccess
    configuration.maxToolIterations = 71

    var operatingConfiguration = AgentOperatingLayerConfiguration.default
    operatingConfiguration.numContext = 8_192

    let original = configuration
    let plan = TurnExecutionPlan.hybridAppleOnDevice(
      configuration: configuration,
      operatingConfiguration: operatingConfiguration
    )

    XCTAssertEqual(configuration, original)
    XCTAssertEqual(plan.origin, .hybridAppleOnDevice)
    XCTAssertEqual(plan.configuration.providerKind, .appleOnDevice)
    XCTAssertEqual(plan.configuration.baseURL, ProviderKind.appleOnDevice.defaultBaseURL)
    XCTAssertEqual(plan.configuration.model, "Apple System Language Model")
    XCTAssertNil(plan.configuration.apiKeySecretID)
    XCTAssertEqual(plan.configuration.systemPrompt, original.systemPrompt)
    XCTAssertEqual(plan.configuration.workspacePath, original.workspacePath)
    XCTAssertEqual(plan.configuration.permissionMode, original.permissionMode)
    XCTAssertEqual(plan.configuration.maxToolIterations, original.maxToolIterations)
    XCTAssertEqual(plan.heavyRuntime, .appleFoundationModels)
    XCTAssertEqual(
      plan.automaticBudget,
      AutomaticInferenceBudget(timeoutSeconds: 60, maximumToolRounds: 4)
    )
  }

  func testHybridAppleBudgetShrinksForSmallContext() {
    var operatingConfiguration = AgentOperatingLayerConfiguration.default
    operatingConfiguration.numContext = 512

    let plan = TurnExecutionPlan.hybridAppleOnDevice(
      configuration: .default,
      operatingConfiguration: operatingConfiguration
    )

    XCTAssertEqual(
      plan.automaticBudget,
      AutomaticInferenceBudget(timeoutSeconds: 60, maximumToolRounds: 1)
    )
  }

  func testAutomaticProfilePlanIsImmutableAndAppliesAdmissionBudget() throws {
    var configuration = AppConfiguration.default
    configuration.providerKind = .ollamaCloud
    configuration.baseURL = "https://ollama.example.invalid"
    configuration.model = "cloud-before-route"
    configuration.maxToolIterations = 99

    var operatingConfiguration = AgentOperatingLayerConfiguration.default
    operatingConfiguration.localInferenceRuntime = .ollama
    operatingConfiguration.numContext = 32_768
    operatingConfiguration.requestTimeoutSeconds = 600

    let profile = ModelProfile(
      name: "Safe ANEMLL",
      runtime: .anemll,
      modelIdentifier: "/models/qwen3-anemll",
      contextWindow: 512,
      estimatedMemoryMB: 4_096
    )
    let snapshot = AutomaticResourceSnapshot(
      thermalState: .nominal,
      physicalMemoryMB: 16_384,
      availableMemoryMB: 10_000,
      swapUsedMB: 0
    )

    let originalConfiguration = configuration
    let originalOperatingConfiguration = operatingConfiguration
    let plan = try TurnExecutionPlan.automaticModelProfile(
      configuration: configuration,
      operatingConfiguration: operatingConfiguration,
      profile: profile,
      resourceSnapshot: snapshot
    )

    configuration.model = "changed-after-plan"
    operatingConfiguration.localInferenceRuntime = .mlxServer

    XCTAssertEqual(originalConfiguration.model, "cloud-before-route")
    XCTAssertEqual(originalOperatingConfiguration.localInferenceRuntime, .ollama)
    XCTAssertEqual(plan.origin, .automaticModelProfile)
    XCTAssertEqual(plan.configuration.providerKind, .ollamaLocal)
    XCTAssertEqual(plan.configuration.model, "/models/qwen3-anemll")
    XCTAssertEqual(plan.configuration.baseURL, LocalInferenceRuntime.anemll.defaultBaseURL)
    XCTAssertNil(plan.configuration.apiKeySecretID)
    XCTAssertEqual(plan.configuration.maxToolIterations, 1)
    XCTAssertEqual(plan.operatingConfiguration.localInferenceRuntime, .anemll)
    XCTAssertEqual(plan.operatingConfiguration.numContext, 512)
    XCTAssertEqual(plan.operatingConfiguration.requestTimeoutSeconds, 45)
    XCTAssertEqual(plan.heavyRuntime, .anemll)
    XCTAssertEqual(
      plan.automaticBudget,
      AutomaticInferenceBudget(timeoutSeconds: 45, maximumToolRounds: 1)
    )
  }

  func testAutomaticLocalProfilePlanFailsClosedWithoutResourceSnapshot() {
    let profile = ModelProfile(
      name: "Unsafe unknown state",
      runtime: .mlx,
      modelIdentifier: "mlx-model",
      estimatedMemoryMB: 4_096
    )

    XCTAssertThrowsError(
      try TurnExecutionPlan.automaticModelProfile(
        configuration: .default,
        operatingConfiguration: .default,
        profile: profile,
        resourceSnapshot: nil
      )
    ) { error in
      XCTAssertEqual(
        error as? AutomaticInferenceAdmissionError,
        .monitoringUnavailable("resource snapshot")
      )
    }
  }

  func testAutomaticCloudProfileDoesNotRequireLocalAdmissionSnapshot() throws {
    let profile = ModelProfile(
      name: "Cloud fallback",
      runtime: .ollamaCloud,
      modelIdentifier: "cloud-model",
      baseURL: "https://ollama.example.invalid",
      contextWindow: 16_384
    )

    let plan = try TurnExecutionPlan.automaticModelProfile(
      configuration: .default,
      operatingConfiguration: .default,
      profile: profile,
      resourceSnapshot: nil
    )

    XCTAssertEqual(plan.configuration.providerKind, .ollamaCloud)
    XCTAssertEqual(plan.configuration.model, "cloud-model")
    XCTAssertEqual(plan.configuration.baseURL, "https://ollama.example.invalid")
    XCTAssertNil(plan.heavyRuntime)
    XCTAssertNotNil(plan.automaticBudget)
  }
}
