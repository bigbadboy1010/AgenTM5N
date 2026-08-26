import XCTest
@testable import AgenTM5N

final class OllamaModelCapabilityPolicyTests: XCTestCase {
  func testDolphin3OmitsThinkingField() {
    var operating = AgentOperatingLayerConfiguration()
    operating.thinkingMode = .high

    XCTAssertNil(
      OllamaModelCapabilityPolicy.thinkValue(
        model: "dolphin3",
        capabilities: ["completion"],
        operatingConfiguration: operating,
        legacyThinkingEnabled: true
      )
    )
  }

  func testUnknownNonThinkingModelOmitsThinkingFieldEvenWhenGlobalThinkingIsEnabled() {
    var operating = AgentOperatingLayerConfiguration()
    operating.thinkingMode = .max

    XCTAssertNil(
      OllamaModelCapabilityPolicy.thinkValue(
        model: "hf.co/example/custom-model-GGUF:Q4_K_M",
        capabilities: ["completion", "tools"],
        operatingConfiguration: operating,
        legacyThinkingEnabled: true
      )
    )
  }

  func testQwen3UsesBooleanThinking() {
    var operating = AgentOperatingLayerConfiguration()
    operating.thinkingMode = .max

    XCTAssertEqual(
      OllamaModelCapabilityPolicy.thinkValue(
        model: "qwen3:8b",
        capabilities: ["completion", "thinking", "tools"],
        operatingConfiguration: operating,
        legacyThinkingEnabled: true
      ),
      .bool(true)
    )

    operating.thinkingMode = .off
    XCTAssertEqual(
      OllamaModelCapabilityPolicy.thinkValue(
        model: "qwen3:8b",
        capabilities: ["completion", "thinking"],
        operatingConfiguration: operating,
        legacyThinkingEnabled: false
      ),
      .bool(false)
    )
  }

  func testGPTOssKeepsReasoningLevelsEvenIfCapabilityDiscoveryFails() {
    var operating = AgentOperatingLayerConfiguration()
    operating.thinkingMode = .max

    XCTAssertEqual(
      OllamaModelCapabilityPolicy.thinkValue(
        model: "gpt-oss:120b",
        capabilities: [],
        operatingConfiguration: operating,
        legacyThinkingEnabled: true
      ),
      .string("high")
    )
  }

  func testProfileCapabilitiesReflectOllamaMetadata() {
    let capabilities = OllamaModelCapabilityPolicy.profileCapabilities(
      model: "hf.co/example/vision-agent-GGUF:Q4_K_M",
      ollamaCapabilities: ["completion", "tools", "vision"]
    )

    XCTAssertTrue(capabilities.contains(.textGeneration))
    XCTAssertTrue(capabilities.contains(.streaming))
    XCTAssertTrue(capabilities.contains(.toolCalling))
    XCTAssertTrue(capabilities.contains(.imageInput))
    XCTAssertFalse(capabilities.contains(.thinking))
  }
}
