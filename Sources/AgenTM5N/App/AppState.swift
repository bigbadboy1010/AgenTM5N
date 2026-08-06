import AppKit
import Foundation
import SwiftUI

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
  @Published public var coreMLPredictionInput = "{\n  \"input\": 1.0\n}"
  @Published public var coreMLPredictionResult: CoreMLPredictionResult?
  @Published public var isRunningCoreML = false

  private let configurationStore: JSONDocumentStore<AppConfiguration>
  private let conversationStore: JSONDocumentStore<[ChatMessage]>
  private let sshHostStore: JSONDocumentStore<[SSHHost]>
  private let vaultStore: VaultStore
  private let ollamaProvider: OllamaProvider
  private let appleProvider: AppleFoundationModelsProvider
  private let coreMLService: CoreMLService
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
    self.sshLaunchService = sshLaunchService
    self.agentRuntime = agentRuntime
  }

  public func bootstrap() async {
    do {
      try AppPaths.purgeRuntimeDirectory()
      async let loadedConfiguration = configurationStore.load()
      async let loadedMessages = conversationStore.load()
      async let loadedHosts = sshHostStore.load()
      let (configuration, messages, hosts) = try await (
        loadedConfiguration,
        loadedMessages,
        loadedHosts
      )
      self.configuration = configuration
      self.messages = messages
      self.sshHosts = hosts.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }

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
      let authenticationSecret: VaultSecret?
      if let id = host.authenticationSecretID {
        authenticationSecret = try await vaultStore.secret(id: id)
      } else {
        authenticationSecret = nil
      }

      let passphraseSecret: VaultSecret?
      if let id = host.passphraseSecretID {
        passphraseSecret = try await vaultStore.secret(id: id)
      } else {
        passphraseSecret = nil
      }

      terminalLaunch = try sshLaunchService.makeLaunch(
        host: host,
        authenticationSecret: authenticationSecret,
        passphraseSecret: passphraseSecret
      )
      selectedSection = .terminal
    } catch {
      present(error)
    }
  }

  public func openLocalTerminal() {
    terminalLaunch = TerminalLaunch(
      title: "Lokales Terminal",
      initialCommand: nil
    )
    selectedSection = .terminal
  }

  public func loadCoreMLModel(from url: URL) async {
    do {
      coreMLDescriptor = try await coreMLService.loadModel(sourceURL: url)
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
    let tools =
      configuration.agentEnabled
      ? AgentRuntime.toolDefinitions
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
    let risk = await agentRuntime.risk(for: call)
    let summary = await agentRuntime.summary(for: call)
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

    let result = await agentRuntime.execute(
      call: call,
      workspacePath: configuration.workspacePath,
      permissionMode: configuration.permissionMode
    )
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

  private func authorize(
    call: ProviderToolCall,
    risk: ToolRisk,
    summary: String
  ) async -> Bool {
    switch configuration.permissionMode {
    case .fullAccess, .workspaceTrusted:
      return true
    case .confirm:
      guard risk != .read else { return true }
      return await withCheckedContinuation { continuation in
        approvalContinuation = continuation
        pendingToolApproval = PendingToolApproval(
          call: call,
          risk: risk,
          summary: summary
        )
      }
    }
  }

  private func resolvePendingApproval(allowed: Bool) {
    pendingToolApproval = nil
    guard let continuation = approvalContinuation else { return }
    approvalContinuation = nil
    continuation.resume(returning: allowed)
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
