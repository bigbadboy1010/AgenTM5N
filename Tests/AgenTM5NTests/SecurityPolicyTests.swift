import XCTest
@testable import AgenTM5N

final class SecurityPolicyTests: XCTestCase {
  func testWorkspaceTrustedSensitiveExecutorsAreApprovalClassified() {
    XCTAssertTrue(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "run_command",
        risk: .execute
      )
    )
    XCTAssertTrue(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "terminal_open",
        risk: .execute
      )
    )
    XCTAssertTrue(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "shortcuts_run",
        risk: .execute
      )
    )
    XCTAssertTrue(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "toolsmith_create",
        risk: .write
      )
    )
    XCTAssertTrue(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "toolsmith_run",
        risk: .execute
      )
    )
    XCTAssertTrue(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "agent_delegate",
        risk: .execute
      )
    )
    XCTAssertTrue(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "browser_open",
        risk: .execute
      )
    )
    XCTAssertFalse(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "browser_read",
        risk: .read
      )
    )
    XCTAssertFalse(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "list_directory",
        risk: .read
      )
    )
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
    XCTAssertFalse(AgentToolRegistry.isAllowed("run_command", within: workspaceOnly))
    XCTAssertFalse(AgentToolRegistry.isAllowed("ssh_run", within: workspaceOnly))
    XCTAssertFalse(AgentToolRegistry.isAllowed("browser_open", within: workspaceOnly))
    XCTAssertFalse(AgentToolRegistry.isAllowed("toolsmith_run", within: workspaceOnly))

    let terminalOnly: Set<AgentToolCapability> = [.terminal]
    XCTAssertTrue(AgentToolRegistry.isAllowed("run_command", within: terminalOnly))
    XCTAssertTrue(AgentToolRegistry.isAllowed("toolsmith_set_enabled", within: terminalOnly))
    XCTAssertFalse(AgentToolRegistry.isAllowed("browser_open", within: terminalOnly))
  }

  func testDelegatedScopeCanOnlyReduceParentCapabilities() {
    let parent: Set<AgentToolCapability> = [.workspace, .agents]

    XCTAssertEqual(
      AgentCapabilityExecutionContext.delegatedScope(
        parent: parent,
        profile: nil
      ),
      parent
    )

    XCTAssertEqual(
      AgentCapabilityExecutionContext.delegatedScope(
        parent: parent,
        profile: [.workspace, .browser]
      ),
      [.workspace]
    )

    XCTAssertEqual(
      AgentCapabilityExecutionContext.delegatedScope(
        parent: nil,
        profile: [.workspace]
      ),
      [.workspace]
    )
  }

  func testBridgePersistsAndIntersectsCapabilityScopes() async {
    let bridge = AgentToolExecutionBridge()
    let sessionID = UUID()
    await bridge.install(sessionID: sessionID) { call in
      "EXECUTED:\(call.function.name)"
    }

    let outer = await bridge.pushCapabilityScope([.workspace, .browser])

    let allowedWorkspace = await bridge.execute(
      ProviderToolCall(
        function: .init(name: "list_directory", arguments: [:])
      )
    )
    XCTAssertEqual(allowedWorkspace, "EXECUTED:list_directory")

    let deniedTerminal = await bridge.execute(
      ProviderToolCall(
        function: .init(
          name: "run_command",
          arguments: ["command": .string("whoami")]
        )
      )
    )
    XCTAssertTrue(deniedTerminal.contains("CAPABILITY_DENIED"))

    let inner = await bridge.pushCapabilityScope([.browser, .terminal])

    let deniedWorkspaceInsideIntersection = await bridge.execute(
      ProviderToolCall(
        function: .init(name: "list_directory", arguments: [:])
      )
    )
    XCTAssertTrue(deniedWorkspaceInsideIntersection.contains("CAPABILITY_DENIED"))

    let allowedBrowser = await bridge.execute(
      ProviderToolCall(
        function: .init(
          name: "browser_open",
          arguments: ["url": .string("https://example.com")]
        )
      )
    )
    XCTAssertEqual(allowedBrowser, "EXECUTED:browser_open")

    let stillDeniedTerminal = await bridge.execute(
      ProviderToolCall(
        function: .init(
          name: "run_command",
          arguments: ["command": .string("whoami")]
        )
      )
    )
    XCTAssertTrue(stillDeniedTerminal.contains("CAPABILITY_DENIED"))

    await bridge.popCapabilityScope(inner)
    await bridge.popCapabilityScope(outer)
    await bridge.clear(sessionID: sessionID)
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
    XCTAssertFalse(names.contains("browser_open"))
  }
}
