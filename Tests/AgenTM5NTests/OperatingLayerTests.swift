import XCTest
@testable import AgenTM5N

final class OperatingLayerTests: XCTestCase {
  func testFixedToolBudgetSupportsValuesAboveLegacyLimit() {
    var configuration = AgentOperatingLayerConfiguration.default
    configuration.toolRoundMode = .fixed
    configuration.maxToolRounds = 512
    configuration.normalize()

    XCTAssertEqual(configuration.effectiveToolRoundLimit, 512)
  }

  func testUnlimitedToolBudgetHasNoFiniteOperatingLimit() {
    var configuration = AgentOperatingLayerConfiguration.default
    configuration.toolRoundMode = .unlimited
    configuration.normalize()

    XCTAssertNil(configuration.effectiveToolRoundLimit)
  }

  func testOperatingLayerDecoderBackfillsNewFields() throws {
    let data = Data(
      """
      {
        "toolRoundMode": "fixed",
        "maxToolRounds": 80,
        "toolSelectionMode": "adaptive",
        "maxAdvertisedTools": 32,
        "enabledCapabilities": ["workspace", "git"],
        "bundledToolsEnabled": true,
        "thinkingMode": "off",
        "numContext": 8192,
        "numPredict": 2048,
        "temperature": 0.2,
        "topK": 40,
        "topP": 0.9,
        "minP": 0.0,
        "repeatPenalty": 1.1,
        "repeatLastN": 64,
        "keepAlive": "5m",
        "requestTimeoutSeconds": 600
      }
      """.utf8
    )

    let decoded = try JSONDecoder().decode(
      AgentOperatingLayerConfiguration.self,
      from: data
    )

    XCTAssertEqual(decoded.localInferenceRuntime, .ollama)
    XCTAssertTrue(decoded.stagnationGuardEnabled)
    XCTAssertEqual(decoded.maxIdenticalToolRounds, 3)
    XCTAssertEqual(decoded.effectiveToolRoundLimit, 80)
    XCTAssertEqual(decoded.enabledCapabilities, [.workspace, .git])
  }

  func testOperatingLayerNormalizationBoundsExtremeValues() {
    var configuration = AgentOperatingLayerConfiguration(
      maxToolRounds: Int.max,
      maxAdvertisedTools: Int.max,
      maxIdenticalToolRounds: Int.max,
      numContext: Int.max,
      numPredict: Int.max,
      temperature: 99,
      topK: Int.max,
      topP: 99,
      minP: -10,
      repeatPenalty: 99,
      repeatLastN: Int.max,
      requestTimeoutSeconds: Int.max
    )
    configuration.normalize()

    XCTAssertEqual(configuration.maxToolRounds, 1_000_000)
    XCTAssertEqual(configuration.maxAdvertisedTools, 256)
    XCTAssertEqual(configuration.maxIdenticalToolRounds, 20)
    XCTAssertEqual(configuration.numContext, 1_048_576)
    XCTAssertEqual(configuration.numPredict, 131_072)
    XCTAssertEqual(configuration.temperature, 2)
    XCTAssertEqual(configuration.topK, 1_000)
    XCTAssertEqual(configuration.topP, 1)
    XCTAssertEqual(configuration.minP, 0)
    XCTAssertEqual(configuration.repeatPenalty, 4)
    XCTAssertEqual(configuration.repeatLastN, 131_072)
    XCTAssertEqual(configuration.requestTimeoutSeconds, 3_600)
  }

  func testBundledToolCatalogSeparatesReadAndExecuteRisk() {
    let dockerRead = BundledToolCatalog.entry(named: "custom_builtin_docker_ps")
    XCTAssertEqual(dockerRead?.capability, .system)
    XCTAssertEqual(dockerRead?.risk, .read)

    let dockerMutation = BundledToolCatalog.entry(named: "custom_builtin_docker_action")
    XCTAssertEqual(dockerMutation?.capability, .system)
    XCTAssertEqual(dockerMutation?.risk, .execute)

    let gitRead = BundledToolCatalog.entry(named: "custom_builtin_git_log")
    XCTAssertEqual(gitRead?.capability, .git)
    XCTAssertEqual(gitRead?.risk, .read)

    let gitNetwork = BundledToolCatalog.entry(named: "custom_builtin_git_push")
    XCTAssertEqual(gitNetwork?.capability, .git)
    XCTAssertEqual(gitNetwork?.risk, .execute)

    let mcp = BundledToolCatalog.entry(named: "custom_builtin_mcp_stdio_call")
    XCTAssertEqual(mcp?.capability, .terminal)
    XCTAssertEqual(mcp?.risk, .execute)
  }

  func testWorkspaceTrustedApprovalUsesBundledRiskMetadata() {
    XCTAssertFalse(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "custom_builtin_docker_ps",
        risk: .read
      )
    )
    XCTAssertTrue(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "custom_builtin_docker_action",
        risk: .execute
      )
    )
    XCTAssertTrue(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "custom_builtin_git_push",
        risk: .execute
      )
    )
    XCTAssertTrue(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "custom_builtin_mcp_stdio_call",
        risk: .execute
      )
    )
  }

  func testStagnationGuardBlocksOnlyAfterConfiguredThreshold() async {
    let guardService = ToolStagnationGuard()
    var configuration = AgentOperatingLayerConfiguration.default
    configuration.stagnationGuardEnabled = true
    configuration.maxIdenticalToolRounds = 2

    let call = ProviderToolCall(
      function: .init(
        name: "read_file",
        arguments: ["path": .string("README.md")]
      )
    )

    let first = await guardService.blockReason(
      for: call,
      configuration: configuration,
      now: Date(timeIntervalSince1970: 100)
    )
    let second = await guardService.blockReason(
      for: call,
      configuration: configuration,
      now: Date(timeIntervalSince1970: 101)
    )
    let third = await guardService.blockReason(
      for: call,
      configuration: configuration,
      now: Date(timeIntervalSince1970: 102)
    )

    XCTAssertNil(first)
    XCTAssertNil(second)
    XCTAssertNotNil(third)

    let changedCall = ProviderToolCall(
      function: .init(
        name: "read_file",
        arguments: ["path": .string("Package.swift")]
      )
    )
    let changed = await guardService.blockReason(
      for: changedCall,
      configuration: configuration,
      now: Date(timeIntervalSince1970: 103)
    )
    XCTAssertNil(changed)
  }

  func testStagnationGuardCanBeDisabled() async {
    let guardService = ToolStagnationGuard()
    var configuration = AgentOperatingLayerConfiguration.default
    configuration.stagnationGuardEnabled = false
    configuration.maxIdenticalToolRounds = 2

    let call = ProviderToolCall(
      function: .init(
        name: "run_command",
        arguments: ["command": .string("pwd")]
      )
    )

    for index in 0..<10 {
      let reason = await guardService.blockReason(
        for: call,
        configuration: configuration,
        now: Date(timeIntervalSince1970: TimeInterval(index))
      )
      XCTAssertNil(reason)
    }
  }
}
