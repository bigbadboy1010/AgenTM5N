import AppKit
import Foundation
import SwiftUI

public enum SSHAgentToolError: LocalizedError {
  case hostNotFound(String)
  case ambiguousHost(String, [String])
  case missingLaunchCommand

  public var errorDescription: String? {
    switch self {
    case .hostNotFound(let query):
      "Kein gespeichertes SSH-Profil passt zu: \(query)"
    case .ambiguousHost(let query, let matches):
      "Das SSH-Profil ist nicht eindeutig (\(query)): \(matches.joined(separator: ", "))"
    case .missingLaunchCommand:
      "Die SSH-Ausführung konnte keinen lokalen Startbefehl erzeugen."
    }
  }
}

private struct SSHHostToolDescriptor: Encodable {
  let id: String
  let name: String
  let hostname: String
  let port: Int
  let username: String
  let authentication: String
  let credentialConfigured: Bool
  let passphraseConfigured: Bool
}

private struct CoreMLToolModelDescriptor: Encodable {
  let id: String
  let name: String
  let active: Bool
  let inputs: [String]
  let outputs: [String]
  let computePolicy: String
  let importedAt: Date
}

private struct CoreMLToolPredictionDescriptor: Encodable {
  let modelID: String
  let modelName: String
  let computePolicy: String
  let durationMilliseconds: Double
  let values: [String: String]
}

private struct WorkspaceIndexToolStatusDescriptor: Encodable {
  let indexed: Bool
  let mode: String?
  let modelID: String?
  let modelName: String?
  let warning: String?
  let createdAt: Date?
  let fileCount: Int?
  let chunkCount: Int?
  let embeddingDimension: Int?
  let indexedCharacterCount: Int?
}

private struct WorkspaceSemanticToolMatchDescriptor: Encodable {
  let relativePath: String
  let startLine: Int
  let endLine: Int
  let score: Double
  let excerpt: String
}

@MainActor
public final class AppState: ObservableObject {
  @Published public var selectedSection: AppSection = .chat
  @Published public var configuration: AppConfiguration = .default
  @Published public var messages: [ChatMessage] = []
  @Published public var inputText = ""
  @Published public var isGenerating = false
  @Published public var isLoadingModels = false
  @Published public var availableModels: [String] = []
  @Published public var latestMetrics: ChatMetrics?
  @Published public var errorMessage: String?
  @Published public var pendingToolApproval: PendingToolApproval?

  @Published public var vaultUnlocked = false
  @Published public var secrets: [VaultSecret] = []

  @Published public var sshHosts: [SSHHost] = []
  @Published public var terminalLaunch = TerminalLaunch(
    title: "Lokales Terminal",
    initialCommand: nil
  )

  @Published public var hardwareProfile = HardwareProfile(
    chipName: "Wird ermittelt",
    memoryBytes: 0,
    operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
    appleFoundationModelStatus: "Wird geprüft"
  )
  @Published public var coreMLDescriptor: CoreMLModelDescriptor?
  @Published public var coreMLModels: [CoreMLRegisteredModel] = []
  @Published public var activeCoreMLModelID: UUID?
  @Published public var coreMLPredictionInput = "{\n  \"input\": 1.0\n}"
  @Published public var coreMLPredictionResult: CoreMLPredictionResult?
  @Published public var isRunningCoreML = false

  @Published public var workspaceIndexStatus: WorkspaceIndexStatus?
  @Published public var workspaceEmbeddingModelID: UUID?
  @Published public var workspaceSemanticQuery = ""
  @Published public var workspaceSemanticResults: [WorkspaceSemanticMatch] = []
  @Published public var isBuildingWorkspaceIndex = false
  @Published public var workspaceIndexProgress: WorkspaceIndexBuildProgress?

  private let configurationStore: JSONDocumentStore<AppConfiguration>
  private let conversationStore: JSONDocumentStore<[ChatMessage]>
  private let sshHostStore: JSONDocumentStore<[SSHHost]>
  private let vaultStore: VaultStore
  private let ollamaProvider: OllamaProvider
  private let appleProvider: AppleFoundationModelsProvider
  private let coreMLService: CoreMLService
  private let workspaceIndexService: WorkspaceIndexService
  private let sshLaunchService: SSHLaunchService
  private let agentRuntime: AgentRuntime
  private var generationTask: Task<Void, Never>?
  private var approvalContinuation: CheckedContinuation<Bool, Never>?

  public init(
    configurationStore: JSONDocumentStore<AppConfiguration> = JSONDocumentStore(
      url: AppPaths.configurationFile,
      defaultValue: .default
    ),
    conversationStore: JSONDocumentStore<[ChatMessage]> = JSONDocumentStore(
      url: AppPaths.conversationFile,
      defaultValue: []
    ),
    sshHostStore: JSONDocumentStore<[SSHHost]> = JSONDocumentStore(
      url: AppPaths.sshHostsFile,
      defaultValue: []
    ),
    vaultStore: VaultStore = VaultStore(url: AppPaths.vaultFile),
    ollamaProvider: OllamaProvider = OllamaProvider(),
    appleProvider: AppleFoundationModelsProvider = AppleFoundationModelsProvider(),
    coreMLService: CoreMLService = CoreMLService(),
    workspaceIndexService: WorkspaceIndexService = WorkspaceIndexService(),
    sshLaunchService: SSHLaunchService = SSHLaunchService(),
    agentRuntime: AgentRuntime = AgentRuntime()
  ) {
    self.configurationStore = configurationStore
    self.conversationStore = conversationStore
    self.sshHostStore = sshHostStore
    self.vaultStore = vaultStore
    self.ollamaProvider = ollamaProvider
    self.appleProvider = appleProvider
    self.coreMLService = coreMLService
    self.workspaceIndexService = workspaceIndexService
    self.sshLaunchService = sshLaunchService
    self.agentRuntime = agentRuntime
  }

  public func bootstrap() async {
    do {
      try AppPaths.purgeRuntimeDirectory()
      async let loadedConfiguration = configurationStore.load()
      async let loadedMessages = conversationStore.load()
      async let loadedHosts = sshHostStore.load()
      async let neuralSnapshot = coreMLService.bootstrap()
      let (configuration, messages, hosts, snapshot) = try await (
        loadedConfiguration,
        loadedMessages,
        loadedHosts,
        neuralSnapshot
      )
      self.configuration = configuration
      self.messages = messages
      self.sshHosts = hosts.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      coreMLModels = snapshot.models
      activeCoreMLModelID = snapshot.activeModelID
      coreMLDescriptor = snapshot.activeDescriptor
      workspaceIndexStatus = try? await workspaceIndexService.status(
        workspacePath: configuration.workspacePath
      )
      workspaceEmbeddingModelID = workspaceIndexStatus?.modelID

      let appleStatus = await appleProvider.availabilityDescription()
      hardwareProfile = HardwareService.makeProfile(
        appleFoundationModelStatus: appleStatus
      )
    } catch {
      present(error)
    }
  }

  public func providerChanged(to kind: ProviderKind) {
    configuration.providerKind = kind
    configuration.baseURL = kind.defaultBaseURL
    switch kind {
    case .ollamaLocal:
      if configuration.model.isEmpty || configuration.model == "glm-5.2" {
        configuration.model = "qwen3:8b"
      }
    case .ollamaCloud:
      if configuration.model.isEmpty || configuration.model == "qwen3:8b" {
        configuration.model = "glm-5.2"
      }
    case .appleOnDevice:
      configuration.model = "Apple System Language Model"
    }
  }

  public func saveConfiguration() async {
    configuration.maxToolIterations = max(
      1,
      min(configuration.maxToolIterations, 24)
    )
    do {
      try await configurationStore.save(configuration)
    } catch {
      present(error)
    }
  }

  public func selectWorkspace() {
    let panel = NSOpenPanel()
    panel.title = "AgenTM5N Workspace auswählen"
    panel.prompt = "Auswählen"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.directoryURL = URL(
      fileURLWithPath: NSString(string: configuration.workspacePath).expandingTildeInPath
    )

    guard panel.runModal() == .OK, let url = panel.url else { return }
    configuration.workspacePath = url.path
    workspaceIndexStatus = nil
    workspaceSemanticResults = []
    Task { [weak self] in
      await self?.refreshWorkspaceIndexStatus()
    }
  }

  public func unlockVault(password: String) async -> Bool {
    do {
      secrets = try await vaultStore.unlock(password: password)
      vaultUnlocked = true
      return true
    } catch {
      vaultUnlocked = false
      present(error)
      return false
    }
  }

  public func lockVault() async {
    await vaultStore.lock()
    vaultUnlocked = false
    secrets = []
  }

  public func upsertSecret(_ secret: VaultSecret) async -> Bool {
    do {
      secrets = try await vaultStore.upsert(secret)
      return true
    } catch {
      present(error)
      return false
    }
  }

  public func deleteSecret(id: UUID) async {
    do {
      secrets = try await vaultStore.delete(id: id)
      if configuration.apiKeySecretID == id {
        configuration.apiKeySecretID = nil
        try await configurationStore.save(configuration)
      }
    } catch {
      present(error)
    }
  }

  public func copySecretToClipboard(id: UUID) async {
    do {
      let secret = try await vaultStore.secret(id: id)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(secret.value, forType: .string)
    } catch {
      present(error)
    }
  }

  public func fetchModels() async {
    guard configuration.providerKind != .appleOnDevice else {
      availableModels = ["Apple System Language Model"]
      return
    }

    isLoadingModels = true
    defer { isLoadingModels = false }

    do {
      let apiKey = try await configuredAPIKey()
      availableModels = try await ollamaProvider.listModels(
        configuration: configuration,
        apiKey: apiKey
      )
    } catch {
      present(error)
    }
  }

  public func sendMessage() {
    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !isGenerating else { return }
    inputText = ""
    generationTask = Task { [weak self] in
      await self?.performSend(text: text)
    }
  }

  public func stopGeneration() {
    resolvePendingApproval(allowed: false)
    generationTask?.cancel()
    generationTask = nil
    isGenerating = false
  }

  public func approvePendingTool() {
    resolvePendingApproval(allowed: true)
  }

  public func denyPendingTool() {
    resolvePendingApproval(allowed: false)
  }

  public func resetConversation() async {
    stopGeneration()
    messages = []
    latestMetrics = nil
    do {
      try PromptImageAttachmentStorage.removeAll()
      try await conversationStore.save(messages)
    } catch {
      present(error)
    }
  }

  public func saveSSHHost(_ host: SSHHost) async -> Bool {
    var updatedHost = host
    updatedHost.updatedAt = Date()
    if let index = sshHosts.firstIndex(where: { $0.id == host.id }) {
      sshHosts[index] = updatedHost
    } else {
      sshHosts.append(updatedHost)
    }
    sshHosts.sort {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }

    do {
      try await sshHostStore.save(sshHosts)
      return true
    } catch {
      present(error)
      return false
    }
  }

  public func deleteSSHHost(id: UUID) async {
    sshHosts.removeAll { $0.id == id }
    do {
      try await sshHostStore.save(sshHosts)
    } catch {
      present(error)
    }
  }

  public func connect(to host: SSHHost) async {
    do {
      let credentials = try await authenticationSecrets(for: host)
      terminalLaunch = try sshLaunchService.makeLaunch(
        host: host,
        authenticationSecret: credentials.authentication,
        passphraseSecret: credentials.passphrase
      )
      selectedSection = .terminal
    } catch {
      present(error)
    }
  }

  public func openLocalTerminal(
    command: String? = nil,
    title: String = "Lokales Terminal"
  ) {
    terminalLaunch = TerminalLaunch(
      title: title,
      initialCommand: command
    )
    selectedSection = .terminal
  }

  public func loadCoreMLModel(from url: URL) async {
    do {
      let record = try await coreMLService.loadModel(sourceURL: url)
      coreMLModels = await coreMLService.listModels()
      activeCoreMLModelID = record.id
      coreMLDescriptor = record.descriptor
      coreMLPredictionResult = nil
    } catch {
      present(error)
    }
  }

  public func runCoreMLPrediction() async {
    isRunningCoreML = true
    defer { isRunningCoreML = false }

    do {
      coreMLPredictionResult = try await coreMLService.predict(
        jsonInput: coreMLPredictionInput
      )
      activeCoreMLModelID = await coreMLService.activeModelID()
    } catch {
      present(error)
    }
  }

  public func refreshWorkspaceIndexStatus() async {
    do {
      workspaceIndexStatus = try await workspaceIndexService.status(
        workspacePath: configuration.workspacePath
      )
      if let modelID = workspaceIndexStatus?.modelID {
        workspaceEmbeddingModelID = modelID
      }
    } catch {
      present(error)
    }
  }

  public func buildWorkspaceIndex() async {
    guard !isBuildingWorkspaceIndex else { return }
    isBuildingWorkspaceIndex = true
    workspaceIndexProgress = WorkspaceIndexBuildProgress(
      phase: .preparing
    )
    defer { isBuildingWorkspaceIndex = false }

    do {
      let model = try await selectedWorkspaceEmbeddingModel()
      workspaceIndexStatus = try await workspaceIndexService.build(
        workspacePath: configuration.workspacePath,
        model: model,
        progress: { [weak self] progress in
          self?.workspaceIndexProgress = progress
        }
      )
      workspaceEmbeddingModelID = workspaceIndexStatus?.modelID
      workspaceSemanticResults = []
    } catch {
      workspaceIndexProgress = nil
      present(error)
    }
  }

  public func searchWorkspaceMemory() async {
    do {
      guard let status = workspaceIndexStatus else {
        throw WorkspaceIndexError.indexNotFound(configuration.workspacePath)
      }
      let model: CoreMLRegisteredModel?
      if let modelID = status.modelID {
        model = try await coreMLService.registeredModel(
          query: modelID.uuidString
        )
      } else {
        model = nil
      }
      workspaceSemanticResults = try await workspaceIndexService.search(
        query: workspaceSemanticQuery,
        workspacePath: configuration.workspacePath,
        model: model
      )
    } catch {
      present(error)
    }
  }

  public func clearWorkspaceIndex() async {
    do {
      try await workspaceIndexService.clear(
        workspacePath: configuration.workspacePath
      )
      workspaceIndexStatus = nil
      workspaceIndexProgress = nil
      workspaceSemanticResults = []
    } catch {
      present(error)
    }
  }

  public func dismissError() {
    errorMessage = nil
  }

  private func performSend(text: String) async {
    isGenerating = true
    latestMetrics = nil
    let userMessage = ChatMessage(role: .user, content: text)
    let assistantID = UUID()
    messages.append(userMessage)
    messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))

    do {
      switch configuration.providerKind {
      case .ollamaLocal, .ollamaCloud:
        try await performOllamaSend(assistantID: assistantID)

      case .appleOnDevice:
        if PromptAttachmentService.hasImageAttachments(in: text) {
          throw PromptAttachmentError.imageProviderUnsupported
        }
        let providerMessages = makeAppleMessages(excludingAssistantID: assistantID)
        let event = try await appleProvider.complete(
          configuration: configuration,
          messages: providerMessages
        )
        apply(event: event, to: assistantID)
      }

      try await conversationStore.save(messages)
    } catch is CancellationError {
      if let index = messages.firstIndex(where: { $0.id == assistantID }),
        messages[index].content.isEmpty
      {
        messages[index].content = "Abgebrochen."
      }
    } catch {
      if let index = messages.firstIndex(where: { $0.id == assistantID }),
        messages[index].content.isEmpty
      {
        messages[index].content = "Fehler: \(error.localizedDescription)"
      }
      present(error)
    }

    resolvePendingApproval(allowed: false)
    isGenerating = false
    generationTask = nil
  }

  private func performOllamaSend(assistantID: UUID) async throws {
    let apiKey = try await configuredAPIKey()
    var providerMessages = makeOllamaMessages(excludingAssistantID: assistantID)

    if providerMessages.contains(where: {
      PromptAttachmentService.hasImageAttachments(in: $0.content)
    }) {
      let capabilities = try await ollamaProvider.modelCapabilities(
        configuration: configuration,
        apiKey: apiKey
      )
      guard capabilities.contains("vision") else {
        throw PromptAttachmentError.modelDoesNotSupportVision(
          configuration.model
        )
      }
    }

    let tools = configuration.agentEnabled
      ? AgentRuntime.toolDefinitions
        + CoreMLAgentTools.definitions
        + WorkspaceMemoryAgentTools.definitions
      : []
    var completedToolIterations = 0

    while true {
      try Task.checkCancellation()
      var turnContent = ""
      var turnThinking = ""
      var turnToolCalls: [ProviderToolCall] = []

      let stream = ollamaProvider.streamChat(
        configuration: configuration,
        apiKey: apiKey,
        messages: providerMessages,
        tools: tools
      )
      for try await event in stream {
        try Task.checkCancellation()
        turnContent += event.contentDelta
        turnThinking += event.thinkingDelta
        mergeToolCalls(event.toolCalls, into: &turnToolCalls)
        apply(event: event, to: assistantID)
      }

      providerMessages.append(
        ProviderMessage(
          role: .assistant,
          content: turnContent,
          thinking: turnThinking.isEmpty ? nil : turnThinking,
          toolCalls: turnToolCalls.isEmpty ? nil : turnToolCalls
        )
      )

      guard configuration.agentEnabled, !turnToolCalls.isEmpty else {
        break
      }

      guard completedToolIterations < configuration.maxToolIterations else {
        appendAssistantText(
          "\n\nAgent-Limit erreicht: maximal \(configuration.maxToolIterations) Tool-Runden.",
          to: assistantID
        )
        break
      }
      completedToolIterations += 1

      for call in turnToolCalls {
        try Task.checkCancellation()
        let toolMessage = await executeToolCall(
          call,
          assistantID: assistantID
        )
        providerMessages.append(toolMessage)
      }
    }
  }

  private func executeToolCall(
    _ call: ProviderToolCall,
    assistantID: UUID
  ) async -> ProviderMessage {
    let risk: ToolRisk
    let summary: String
    if CoreMLAgentTools.handles(call) {
      risk = CoreMLAgentTools.risk(for: call)
      summary = CoreMLAgentTools.summary(for: call)
    } else if WorkspaceMemoryAgentTools.handles(call) {
      risk = WorkspaceMemoryAgentTools.risk(for: call)
      summary = WorkspaceMemoryAgentTools.summary(for: call)
    } else {
      risk = await agentRuntime.risk(for: call)
      summary = await agentRuntime.summary(for: call)
    }
    let allowed = await authorize(call: call, risk: risk, summary: summary)
    let recordID = UUID()
    appendToolRecord(
      ToolExecutionRecord(
        id: recordID,
        toolName: call.function.name,
        argumentsSummary: summary,
        risk: risk,
        status: allowed ? .running : .denied,
        output: allowed ? "" : "Vom Benutzer oder Berechtigungsmodus abgelehnt.",
        endedAt: allowed ? nil : Date()
      ),
      to: assistantID
    )

    guard allowed else {
      return ProviderMessage(
        role: .tool,
        content: "Tool execution denied by the user or permission policy.",
        toolName: call.function.name
      )
    }

    let result = await executeAuthorizedToolCall(call)
    finishToolRecord(
      id: recordID,
      result: result,
      assistantID: assistantID
    )
    return ProviderMessage(
      role: .tool,
      content: result.output,
      toolName: call.function.name
    )
  }

  private func executeAuthorizedToolCall(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    switch call.function.name {
    case "terminal_open":
      return openTerminalTool(call)
    case "ssh_list_hosts":
      return listSSHHostsTool()
    case "ssh_run":
      return await runSSHTool(call)
    case "ssh_open_terminal":
      return await openSSHTerminalTool(call)
    case "coreml_list_models":
      return await listCoreMLModelsTool()
    case "coreml_describe_model":
      return await describeCoreMLModelTool(call)
    case "coreml_predict":
      return await predictCoreMLTool(call)
    case "workspace_index_status":
      return await workspaceIndexStatusTool()
    case "workspace_index_build":
      return await buildWorkspaceIndexTool(call)
    case "workspace_semantic_search":
      return await searchWorkspaceIndexTool(call)
    case "workspace_index_clear":
      return await clearWorkspaceIndexTool()
    default:
      return await agentRuntime.execute(
        call: call,
        workspacePath: configuration.workspacePath,
        permissionMode: configuration.permissionMode
      )
    }
  }

  private func openTerminalTool(
    _ call: ProviderToolCall
  ) -> ToolExecutionResult {
    let command = optionalToolString("command", in: call)
    let title = optionalToolString("title", in: call) ?? "Agent Terminal"
    openLocalTerminal(command: command, title: title)
    return ToolExecutionResult(
      success: true,
      output: command == nil
        ? "Das sichtbare lokale Terminal wurde geöffnet."
        : "Das sichtbare lokale Terminal wurde mit einem initialen Kommando geöffnet."
    )
  }

  private func listSSHHostsTool() -> ToolExecutionResult {
    let descriptors = sshHosts.map { host in
      SSHHostToolDescriptor(
        id: host.id.uuidString,
        name: host.name,
        hostname: host.hostname,
        port: host.port,
        username: host.username,
        authentication: host.authenticationKind.rawValue,
        credentialConfigured: host.authenticationSecretID != nil,
        passphraseConfigured: host.passphraseSecretID != nil
      )
    }

    return encodedToolResult(descriptors)
  }

  private func runSSHTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      let hostQuery = try requiredToolString("host", in: call)
      let command = try requiredToolString("command", in: call)
      let host = try resolveSSHHost(hostQuery)
      let credentials = try await authenticationSecrets(for: host)
      let launch = try sshLaunchService.makeExecutionLaunch(
        host: host,
        authenticationSecret: credentials.authentication,
        passphraseSecret: credentials.passphrase,
        command: command
      )
      defer { cleanupRuntimePaths(launch.cleanupPaths) }

      guard let localCommand = launch.initialCommand else {
        throw SSHAgentToolError.missingLaunchCommand
      }

      return await agentRuntime.executeCommand(
        localCommand,
        workspacePath: configuration.workspacePath
      )
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private func openSSHTerminalTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      let hostQuery = try requiredToolString("host", in: call)
      var host = try resolveSSHHost(hostQuery)
      if let command = optionalToolString("command", in: call) {
        host.remoteCommand = command
      }
      let credentials = try await authenticationSecrets(for: host)
      terminalLaunch = try sshLaunchService.makeLaunch(
        host: host,
        authenticationSecret: credentials.authentication,
        passphraseSecret: credentials.passphrase
      )
      selectedSection = .terminal
      return ToolExecutionResult(
        success: true,
        output: "Interaktive SSH-Sitzung zu \(host.name) wurde im sichtbaren Terminal geöffnet."
      )
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private func listCoreMLModelsTool() async -> ToolExecutionResult {
    let activeID = await coreMLService.activeModelID()
    let descriptors = (await coreMLService.listModels()).map { model in
      CoreMLToolModelDescriptor(
        id: model.id.uuidString,
        name: model.name,
        active: model.id == activeID,
        inputs: model.inputs,
        outputs: model.outputs,
        computePolicy: model.computeUnits,
        importedAt: model.importedAt
      )
    }
    return encodedToolResult(descriptors)
  }

  private func describeCoreMLModelTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      let query = optionalToolString("model", in: call)
      let model = try await coreMLService.registeredModel(query: query)
      let activeID = await coreMLService.activeModelID()
      return encodedToolResult(
        CoreMLToolModelDescriptor(
          id: model.id.uuidString,
          name: model.name,
          active: model.id == activeID,
          inputs: model.inputs,
          outputs: model.outputs,
          computePolicy: model.computeUnits,
          importedAt: model.importedAt
        )
      )
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private func predictCoreMLTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      guard let input = call.function.arguments["input"]?.objectValue else {
        throw AgentRuntimeError.missingArgument(
          tool: call.function.name,
          name: "input"
        )
      }
      let modelQuery = optionalToolString("model", in: call)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let inputData = try encoder.encode(JSONValue.object(input))
      let inputText = String(decoding: inputData, as: UTF8.self)
      let model = try await coreMLService.registeredModel(query: modelQuery)
      let result = try await coreMLService.predict(
        jsonInput: inputText,
        modelQuery: modelQuery
      )
      activeCoreMLModelID = model.id
      coreMLDescriptor = model.descriptor
      coreMLModels = await coreMLService.listModels()
      coreMLPredictionResult = result
      return encodedToolResult(
        CoreMLToolPredictionDescriptor(
          modelID: model.id.uuidString,
          modelName: model.name,
          computePolicy: model.computeUnits,
          durationMilliseconds: result.durationMilliseconds,
          values: result.values
        )
      )
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private func workspaceIndexStatusTool() async -> ToolExecutionResult {
    do {
      let status = try await workspaceIndexService.status(
        workspacePath: configuration.workspacePath
      )
      workspaceIndexStatus = status
      return encodedToolResult(workspaceStatusDescriptor(status))
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private func buildWorkspaceIndexTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      let modelQuery = optionalToolString("model", in: call)
      let model: CoreMLRegisteredModel?
      if let modelQuery {
        model = try await coreMLService.registeredModel(query: modelQuery)
      } else {
        model = nil
      }
      let status = try await workspaceIndexService.build(
        workspacePath: configuration.workspacePath,
        model: model,
        progress: { [weak self] progress in
          self?.workspaceIndexProgress = progress
        }
      )
      workspaceIndexStatus = status
      workspaceEmbeddingModelID = status.modelID
      workspaceSemanticResults = []
      return encodedToolResult(workspaceStatusDescriptor(status))
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private func searchWorkspaceIndexTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      let query = try requiredToolString("query", in: call)
      let limit = optionalToolInt("limit", in: call) ?? 8
      guard let status = try await workspaceIndexService.status(
        workspacePath: configuration.workspacePath
      ) else {
        throw WorkspaceIndexError.indexNotFound(configuration.workspacePath)
      }
      let model: CoreMLRegisteredModel?
      if let modelID = status.modelID {
        model = try await coreMLService.registeredModel(
          query: modelID.uuidString
        )
      } else {
        model = nil
      }
      let matches = try await workspaceIndexService.search(
        query: query,
        workspacePath: configuration.workspacePath,
        model: model,
        limit: limit
      )
      workspaceIndexStatus = status
      workspaceSemanticQuery = query
      workspaceSemanticResults = matches
      return encodedToolResult(
        matches.map {
          WorkspaceSemanticToolMatchDescriptor(
            relativePath: $0.relativePath,
            startLine: $0.startLine,
            endLine: $0.endLine,
            score: $0.score,
            excerpt: $0.excerpt
          )
        }
      )
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private func clearWorkspaceIndexTool() async -> ToolExecutionResult {
    do {
      try await workspaceIndexService.clear(
        workspacePath: configuration.workspacePath
      )
      workspaceIndexStatus = nil
      workspaceSemanticResults = []
      return ToolExecutionResult(
        success: true,
        output: L10n.text(
          de: "Der lokale semantische Workspace-Index wurde gelöscht.",
          en: "The local semantic workspace index was deleted.",
          fr: "L’index sémantique local de l’espace de travail a été supprimé."
        )
      )
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private func workspaceStatusDescriptor(
    _ status: WorkspaceIndexStatus?
  ) -> WorkspaceIndexToolStatusDescriptor {
    WorkspaceIndexToolStatusDescriptor(
      indexed: status != nil,
      mode: status?.mode.rawValue,
      modelID: status?.modelID?.uuidString,
      modelName: status?.modelName,
      warning: status?.warning,
      createdAt: status?.createdAt,
      fileCount: status?.fileCount,
      chunkCount: status?.chunkCount,
      embeddingDimension: status?.embeddingDimension,
      indexedCharacterCount: status?.indexedCharacterCount
    )
  }

  private func selectedWorkspaceEmbeddingModel() async throws -> CoreMLRegisteredModel? {
    guard let modelID = workspaceEmbeddingModelID else {
      return nil
    }
    return try await coreMLService.registeredModel(
      query: modelID.uuidString
    )
  }

  private func encodedToolResult<T: Encodable>(_ value: T) -> ToolExecutionResult {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(value)
      return ToolExecutionResult(
        success: true,
        output: String(decoding: data, as: UTF8.self)
      )
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }
  private func authorize(
    call: ProviderToolCall,
    risk: ToolRisk,
    summary: String
  ) async -> Bool {
    let remoteExecution = call.function.name == "ssh_run"
      || call.function.name == "ssh_open_terminal"

    switch configuration.permissionMode {
    case .fullAccess:
      return true
    case .workspaceTrusted:
      if remoteExecution {
        return await requestToolApproval(call: call, risk: risk, summary: summary)
      }
      return true
    case .confirm:
      guard risk != .read else { return true }
      return await requestToolApproval(call: call, risk: risk, summary: summary)
    }
  }

  private func requestToolApproval(
    call: ProviderToolCall,
    risk: ToolRisk,
    summary: String
  ) async -> Bool {
    await withCheckedContinuation { continuation in
      approvalContinuation = continuation
      pendingToolApproval = PendingToolApproval(
        call: call,
        risk: risk,
        summary: summary
      )
    }
  }

  private func resolvePendingApproval(allowed: Bool) {
    pendingToolApproval = nil
    guard let continuation = approvalContinuation else { return }
    approvalContinuation = nil
    continuation.resume(returning: allowed)
  }

  private func authenticationSecrets(
    for host: SSHHost
  ) async throws -> (authentication: VaultSecret?, passphrase: VaultSecret?) {
    let authentication: VaultSecret?
    if let id = host.authenticationSecretID {
      authentication = try await vaultStore.secret(id: id)
    } else {
      authentication = nil
    }

    let passphrase: VaultSecret?
    if let id = host.passphraseSecretID {
      passphrase = try await vaultStore.secret(id: id)
    } else {
      passphrase = nil
    }
    return (authentication, passphrase)
  }

  private func resolveSSHHost(_ query: String) throws -> SSHHost {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = sshHosts.filter { host in
      host.id.uuidString.caseInsensitiveCompare(normalized) == .orderedSame
        || host.name.caseInsensitiveCompare(normalized) == .orderedSame
        || host.hostname.caseInsensitiveCompare(normalized) == .orderedSame
    }

    guard !matches.isEmpty else {
      throw SSHAgentToolError.hostNotFound(query)
    }
    guard matches.count == 1, let host = matches.first else {
      throw SSHAgentToolError.ambiguousHost(query, matches.map(\.name))
    }
    return host
  }

  private func requiredToolString(
    _ name: String,
    in call: ProviderToolCall
  ) throws -> String {
    guard let value = optionalToolString(name, in: call) else {
      throw AgentRuntimeError.missingArgument(
        tool: call.function.name,
        name: name
      )
    }
    return value
  }

  private func optionalToolString(
    _ name: String,
    in call: ProviderToolCall
  ) -> String? {
    guard let value = call.function.arguments[name]?.stringValue else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func optionalToolInt(
    _ name: String,
    in call: ProviderToolCall
  ) -> Int? {
    guard let value = call.function.arguments[name] else { return nil }
    guard case .number(let number) = value, number.isFinite else { return nil }
    return Int(number)
  }

  private func cleanupRuntimePaths(_ paths: [URL]) {
    for path in paths {
      do {
        try FileManager.default.removeItem(at: path)
      } catch {
        AppLogger.security.error(
          "Runtime secret cleanup failed for \(path.path, privacy: .private): \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }

  private func makeOllamaMessages(
    excludingAssistantID: UUID
  ) -> [ProviderMessage] {
    var result = [
      ProviderMessage(
        role: .system,
        content: configuration.systemPrompt
      )
    ]
    result.append(
      contentsOf: messages.compactMap { message -> ProviderMessage? in
        guard message.id != excludingAssistantID, message.role != .system else {
          return nil
        }
        return ProviderMessage(
          role: message.role == .user ? .user : .assistant,
          content: message.content,
          thinking: message.thinking.isEmpty ? nil : message.thinking
        )
      }
    )
    return result
  }

  private func makeAppleMessages(
    excludingAssistantID: UUID
  ) -> [ChatMessage] {
    var result = [
      ChatMessage(role: .system, content: configuration.systemPrompt)
    ]
    result.append(
      contentsOf: messages.filter {
        $0.id != excludingAssistantID && $0.role != .system
      })
    return result
  }

  private func mergeToolCalls(
    _ incoming: [ProviderToolCall],
    into accumulated: inout [ProviderToolCall]
  ) {
    for call in incoming {
      if let index = call.function.index,
        let existingIndex = accumulated.firstIndex(
          where: { $0.function.index == index })
      {
        accumulated[existingIndex] = call
      } else if !accumulated.contains(call) {
        accumulated.append(call)
      }
    }
  }

  private func apply(event: ProviderStreamEvent, to assistantID: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == assistantID }) else {
      return
    }
    messages[index].content += event.contentDelta
    messages[index].thinking += event.thinkingDelta
    if let metrics = event.metrics {
      latestMetrics = metrics
    }
  }

  private func appendAssistantText(_ text: String, to assistantID: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == assistantID }) else {
      return
    }
    messages[index].content += text
  }

  private func appendToolRecord(
    _ record: ToolExecutionRecord,
    to assistantID: UUID
  ) {
    guard let index = messages.firstIndex(where: { $0.id == assistantID }) else {
      return
    }
    var records = messages[index].toolExecutions ?? []
    records.append(record)
    messages[index].toolExecutions = records
  }

  private func finishToolRecord(
    id: UUID,
    result: ToolExecutionResult,
    assistantID: UUID
  ) {
    guard
      let messageIndex = messages.firstIndex(where: { $0.id == assistantID }),
      var records = messages[messageIndex].toolExecutions,
      let recordIndex = records.firstIndex(where: { $0.id == id })
    else {
      return
    }
    records[recordIndex].status = result.success ? .succeeded : .failed
    records[recordIndex].output = result.output
    records[recordIndex].endedAt = Date()
    messages[messageIndex].toolExecutions = records
  }

  private func configuredAPIKey() async throws -> String? {
    guard configuration.providerKind == .ollamaCloud else {
      return nil
    }
    guard let id = configuration.apiKeySecretID else {
      return nil
    }
    return try await vaultStore.secret(id: id).value
  }

  private func present(_ error: Error) {
    errorMessage = error.localizedDescription
    AppLogger.app.error("Application error: \(error.localizedDescription, privacy: .public)")
  }
}
