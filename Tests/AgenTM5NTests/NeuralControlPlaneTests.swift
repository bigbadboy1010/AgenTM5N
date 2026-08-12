import CoreML
import XCTest
@testable import AgenTM5N

final class NeuralControlPlaneTests: XCTestCase {
  func testCoreMLComputeModesMapToExpectedComputeUnits() {
    XCTAssertEqual(CoreMLComputeMode.automatic.computeUnits, .all)
    XCTAssertEqual(CoreMLComputeMode.cpuOnly.computeUnits, .cpuOnly)
    XCTAssertEqual(CoreMLComputeMode.cpuAndGPU.computeUnits, .cpuAndGPU)
    XCTAssertEqual(
      CoreMLComputeMode.neuralEnginePreferred.computeUnits,
      .cpuAndNeuralEngine
    )
  }

  func testNeuralEnginePreferredDoesNotClaimANEOnly() {
    let explanation = CoreMLComputeMode.neuralEnginePreferred.explanation.lowercased()
    XCTAssertTrue(explanation.contains("cpu"))
    XCTAssertTrue(
      explanation.contains("not ane-only")
        || explanation.contains("nicht „ane only“")
        || explanation.contains("non ane uniquement")
        || explanation.contains("nicht")
    )
  }

  func testMacControlPlaneToolNamesAreStable() {
    XCTAssertEqual(
      MacControlPlaneToolPackInstaller.toolNames,
      Set([
        "custom_mac_apps_list",
        "custom_mac_app_open",
        "custom_mac_app_focus",
        "custom_mac_windows_list",
        "custom_mac_spotlight_search",
        "custom_mac_file_metadata",
        "custom_mac_open_path",
        "custom_mac_screenshot",
        "custom_mac_shortcut_run_text",
      ])
    )
  }

  func testMacControlPlaneToolsUseSystemCapabilityAndSemanticRisk() {
    let readNames = [
      "custom_mac_apps_list",
      "custom_mac_windows_list",
      "custom_mac_spotlight_search",
      "custom_mac_file_metadata",
    ]
    for name in readNames {
      XCTAssertEqual(AgentToolRegistry.entry(named: name)?.capability, .system)
      XCTAssertEqual(AgentToolRegistry.entry(named: name)?.risk, .read)
    }

    let executeNames = [
      "custom_mac_app_open",
      "custom_mac_app_focus",
      "custom_mac_open_path",
      "custom_mac_shortcut_run_text",
    ]
    for name in executeNames {
      XCTAssertEqual(AgentToolRegistry.entry(named: name)?.capability, .system)
      XCTAssertEqual(AgentToolRegistry.entry(named: name)?.risk, .execute)
    }

    XCTAssertEqual(
      AgentToolRegistry.entry(named: "custom_mac_screenshot")?.capability,
      .system
    )
    XCTAssertEqual(
      AgentToolRegistry.entry(named: "custom_mac_screenshot")?.risk,
      .write
    )
  }

  func testWorkspaceTrustedApprovesVisibleMacMutations() {
    XCTAssertTrue(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "custom_mac_app_open",
        risk: .execute
      )
    )
    XCTAssertTrue(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "custom_mac_screenshot",
        risk: .write
      )
    )
    XCTAssertFalse(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "custom_mac_spotlight_search",
        risk: .read
      )
    )
  }
}
