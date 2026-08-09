import XCTest
@testable import AgenTM5N

private actor BridgeConcurrencyProbe {
  private var active = 0
  private var maximumActive = 0

  func enter() {
    active += 1
    maximumActive = max(maximumActive, active)
  }

  func leave() {
    active -= 1
  }

  func maximum() -> Int {
    maximumActive
  }
}

final class SecurityPolicyTests: XCTestCase {
  func testWorkspaceTrustedSensitiveExecutorsAreApprovalClassified() {
    let approvalRequired: [(String, ToolRisk)] = [
      ("run_command", .execute),
      ("terminal_open", .execute),
      ("shortcuts_run", .execute),
      ("toolsmith_create", .write),
      ("toolsmith_run", .execute),
      ("agent_delegate", .execute),
      ("browser_open", .execute),
      ("clipboard_write", .write),
      ("notification_send", .write),
      ("finder_reveal", .execute),
      ("agent_create", .write),
      ("agent_update", .write),
      ("agent_delete", .write),
      ("workflow_create", .write),
      ("workflow_delete", .write),
      ("workflow_run", .execute),
    ]

    for (name, risk) in approvalRequired {
      XCTAssertTrue(
        AgentToolRegistry.requiresWorkspaceTrustedApproval(name, risk: risk),
        "Workspace Trusted must require approval for \(name)"
      )
    }

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
    XCTAssertFalse(
      AgentToolRegistry.requiresWorkspaceTrustedApproval(
        "write_file",
        risk: .write
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

  func testBridgeSerializesConcurrentFoundationToolExecution() async {
    let bridge = AgentToolExecutionBridge()
    let probe = BridgeConcurrencyProbe()
    let sessionID = UUID()

    await bridge.install(sessionID: sessionID) { call in
      await probe.enter()
      try? await Task.sleep(for: .milliseconds(40))
      await probe.leave()
      return "EXECUTED:\(call.function.name)"
    }

    await withTaskGroup(of: String.self) { group in
      for _ in 0..<3 {
        group.addTask {
          await bridge.execute(
            ProviderToolCall(
              function: .init(name: "list_directory", arguments: [:])
            )
          )
        }
      }
      for await _ in group {}
    }

    let maximumConcurrentExecutions = await probe.maximum()
    XCTAssertEqual(maximumConcurrentExecutions, 1)
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

  func testDisabledToolsmithReplacementFailsClosed() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentm5n-tool-policy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let library = SelfBuiltToolLibrary(fileURL: root.appendingPathComponent("tools.json"))
    let created = try library.createOrReplace(
      name: "disabled_replace",
      description: "Disabled replacement regression",
      language: .zsh,
      parameters: [],
      source: "print -- first"
    )
    _ = try library.setEnabled(false, query: created.id.uuidString)

    let call = ProviderToolCall(
      function: .init(
        name: "toolsmith_create",
        arguments: [
          "name": .string("disabled_replace"),
          "description": .string("Replacement"),
          "language": .string("zsh"),
          "source": .string("print -- second"),
        ]
      )
    )
    let denial = SelfBuiltToolReplacementPolicy.denial(for: call, library: library)
    XCTAssertNotNil(denial)
    XCTAssertFalse(denial?.success ?? true)
    XCTAssertFalse(try library.resolve(created.id.uuidString).isEnabled)
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

  func testRegistryCatalogHasProviderDefinitionForEveryFixedTool() {
    let definitionNames = Set(AgentToolRegistry.allDefinitions.map { $0.function.name })
    for entry in AgentToolRegistry.catalog {
      XCTAssertTrue(
        definitionNames.contains(entry.name),
        "Missing provider-neutral definition for \(entry.name)"
      )
    }
  }

  func testRegistryIsSingleRiskAuthorityForWorkspaceIndexBuild() {
    XCTAssertEqual(AgentToolRegistry.entry(named: "workspace_index_build")?.risk, .write)
    XCTAssertEqual(AgentToolRegistry.entry(named: "coreml_predict")?.risk, .execute)
    XCTAssertEqual(AgentToolRegistry.entry(named: "browser_read")?.risk, .read)
  }

  func testSecretHostBindingRejectsDifferentHTTPSHost() throws {
    let secret = VaultSecret(
      kind: .apiKey,
      label: "host-bound-test",
      host: "https://api.example.com",
      value: "test-value-not-real"
    )

    XCTAssertNoThrow(
      try SecureHTTPClient.validateSecretHostBinding(
        secret,
        requestHost: "API.EXAMPLE.COM."
      )
    )
    XCTAssertThrowsError(
      try SecureHTTPClient.validateSecretHostBinding(
        secret,
        requestHost: "other.example.com"
      )
    ) { error in
      guard let brokerError = error as? SecureSecretBrokerError else {
        return XCTFail("Expected SecureSecretBrokerError, got \(error)")
      }
      guard case .secretHostMismatch = brokerError else {
        return XCTFail("Expected secretHostMismatch, got \(brokerError)")
      }
    }
  }

  func testCoreMLManagedStorageDeduplicatesIdenticalContentAcrossDifferentNames() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentm5n-coreml-dedupe-\(UUID().uuidString)", isDirectory: true)
    let sourceA = root.appendingPathComponent("A.mlpackage", isDirectory: true)
    let sourceB = root.appendingPathComponent("B.mlpackage", isDirectory: true)
    let store = root.appendingPathComponent("store", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: sourceB, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try Data("same-model-content".utf8).write(
      to: sourceA.appendingPathComponent("weights.bin")
    )
    try Data("same-model-content".utf8).write(
      to: sourceB.appendingPathComponent("weights.bin")
    )

    let digestA = try CoreMLManagedStorage.contentDigest(at: sourceA)
    let digestB = try CoreMLManagedStorage.contentDigest(at: sourceB)
    XCTAssertEqual(digestA, digestB)

    let first = try CoreMLManagedStorage.persistentCopy(
      of: sourceA,
      in: store,
      preferredExtension: "mlpackage",
      digest: digestA
    )
    let second = try CoreMLManagedStorage.persistentCopy(
      of: sourceB,
      in: store,
      preferredExtension: "mlpackage",
      digest: digestB
    )
    XCTAssertTrue(first.created)
    XCTAssertFalse(second.created)
    XCTAssertEqual(first.url, second.url)
  }

  func testCoreMLManagedStorageRemovesOnlyUnreferencedTopLevelArtifacts() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentm5n-coreml-orphans-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let keep = root.appendingPathComponent("keep.mlmodelc", isDirectory: true)
    let orphan = root.appendingPathComponent("orphan.mlmodelc", isDirectory: true)
    try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)

    try CoreMLManagedStorage.removeOrphans(in: root, referencedURLs: [keep])

    XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
  }

  @MainActor
  func testWorkflowReplacementPreservesDisabledState() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentm5n-workflow-state-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let file = root.appendingPathComponent("workflows.json")
    let original = AgentWorkflow(
      name: "disabled-workflow",
      purpose: "Original",
      steps: [AgentWorkflowStep(toolName: "list_directory", arguments: [:])],
      isEnabled: false
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode([original]).write(to: file)

    let library = AgentWorkflowLibrary(fileURL: file)
    let replaced = try library.create(
      name: original.name,
      purpose: "Replacement",
      steps: [AgentWorkflowStep(toolName: "list_directory", arguments: [:])]
    )
    XCTAssertFalse(replaced.isEnabled)
  }

  @MainActor
  func testPersistentAgentReplacementPreservesDisabledState() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentm5n-agent-state-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let library = PersistentAgentLibrary(fileURL: root.appendingPathComponent("agents.json"))
    let original = try library.create(
      name: "disabled-agent",
      purpose: "Original",
      instructions: "Stay focused on the original task.",
      providerPreference: .current,
      allowedCapabilities: [.workspace]
    )
    _ = try library.update(query: original.id.uuidString, enabled: false)

    let replaced = try library.create(
      name: original.name,
      purpose: "Replacement",
      instructions: "Stay focused on the replacement task.",
      providerPreference: .current,
      allowedCapabilities: [.workspace]
    )
    XCTAssertFalse(replaced.isEnabled)
  }

  @MainActor
  func testPersistentAgentResolveIntersectsRestrictedParentScope() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentm5n-agent-scope-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let library = PersistentAgentLibrary(fileURL: root.appendingPathComponent("agents.json"))
    let child = try library.create(
      name: "broader-child",
      purpose: "Nested scope regression",
      instructions: "Use only the tools made available by AgenTM5N.",
      providerPreference: .ollamaLocal,
      allowedCapabilities: [.workspace, .browser]
    )

    let resolved = try AgentCapabilityExecutionContext.$allowedCapabilities.withValue(
      Set<AgentToolCapability>([.workspace, .agents])
    ) {
      try library.resolve(child.id.uuidString)
    }

    XCTAssertEqual(resolved.allowedCapabilities, [.workspace])
  }
}