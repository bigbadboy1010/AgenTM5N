import XCTest
@testable import AgenTM5N

final class SecurityPolicyTests: XCTestCase {
  func testWorkspaceTrustedSensitiveExecutorsAreApprovalClassified() {
    XCTAssertTrue(AgentToolRegistry.isRemoteOrExternal("run_command"))
    XCTAssertTrue(AgentToolRegistry.isRemoteOrExternal("terminal_open"))
    XCTAssertTrue(AgentToolRegistry.isRemoteOrExternal("shortcuts_run"))
    XCTAssertTrue(AgentToolRegistry.isRemoteOrExternal("toolsmith_create"))
    XCTAssertTrue(AgentToolRegistry.isRemoteOrExternal("toolsmith_run"))
  }

  func testBrowserBatchIsProviderNeutralExecuteTool() {
    let entry = AgentToolRegistry.entry(named: "browser_batch")
    XCTAssertNotNil(entry)
    XCTAssertEqual(entry?.capability, .browser)
    XCTAssertEqual(entry?.risk, .execute)
    XCTAssertTrue(
      AgentToolRegistry.ollamaDefinitions.contains {
        $0.function.name == "browser_batch"
      }
    )
  }

  func testCapabilitySandboxFiltersToolsTechnically() {
    let workspaceOnly: Set<AgentToolCapability> = [.workspace]
    XCTAssertTrue(AgentToolRegistry.isAllowed("read_file", within: workspaceOnly))
    XCTAssertFalse(AgentToolRegistry.isAllowed("ssh_run", within: workspaceOnly))
    XCTAssertFalse(AgentToolRegistry.isAllowed("browser_open", within: workspaceOnly))
    XCTAssertFalse(AgentToolRegistry.isAllowed("toolsmith_run", within: workspaceOnly))

    let terminalOnly: Set<AgentToolCapability> = [.terminal]
    XCTAssertTrue(AgentToolRegistry.isAllowed("run_command", within: terminalOnly))
    XCTAssertTrue(AgentToolRegistry.isAllowed("toolsmith_set_enabled", within: terminalOnly))
  }

  func testToolsmithNormalizesNamesAndRejectsCredentialSource() throws {
    XCTAssertEqual(
      try SelfBuiltToolAgentTools.normalizedToolName("Hello Tool"),
      "custom_hello_tool"
    )

    XCTAssertThrowsError(
      try SelfBuiltToolAgentTools.validate(
        source: "-----BEGIN OPENSSH PRIVATE KEY-----\nsecret\n-----END OPENSSH PRIVATE KEY-----"
      )
    )
  }

  func testSelfBuiltToolCanBeDisabledAndReenabledPersistently() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentm5n-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let file = root.appendingPathComponent("tools.json")
    let library = SelfBuiltToolLibrary(fileURL: file)
    let created = try library.createOrReplace(
      name: "toggle_test",
      description: "Regression test tool",
      language: .zsh,
      parameters: [],
      source: "print -- ok"
    )
    XCTAssertTrue(created.isEnabled)

    let disabled = try library.setEnabled(false, query: created.id.uuidString)
    XCTAssertFalse(disabled.isEnabled)
    XCTAssertFalse(try library.resolve(created.id.uuidString).isEnabled)

    let enabled = try library.setEnabled(true, query: created.name)
    XCTAssertTrue(enabled.isEnabled)
    XCTAssertTrue(try library.resolve(created.id.uuidString).isEnabled)
  }

  func testTerminalCapabilityDefinitionsContainToolsmithManagement() {
    let definitions = AgentToolRegistry.definitions(capabilities: [.terminal])
    let names = Set(definitions.map { $0.function.name })
    XCTAssertTrue(names.contains("run_command"))
    XCTAssertTrue(names.contains("toolsmith_create"))
    XCTAssertTrue(names.contains("toolsmith_set_enabled"))
    XCTAssertTrue(names.contains("toolsmith_run"))
    XCTAssertFalse(names.contains("ssh_run"))
  }
}
