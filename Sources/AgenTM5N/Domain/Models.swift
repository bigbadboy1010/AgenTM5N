import Foundation

public enum AppSection: String, CaseIterable, Identifiable, Sendable {
  case chat = "Chat"
  case terminal = "Terminal"
  case ssh = "SSH"
  case vault = "Vault"
  case neuralEngine = "Neural Engine"
  case memory = "Workspace Memory"
  case settings = "Settings"

  public var id: String { rawValue }

  public var systemImage: String {
    switch self {
    case .chat: "bubble.left.and.bubble.right"
    case .terminal: "terminal"
    case .ssh: "network"
    case .vault: "lock.shield"
    case .neuralEngine: "brain.head.profile"
    case .memory: "books.vertical"
    case .settings: "gearshape"
    }
  }
}

public enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case ollamaLocal
  case ollamaCloud
  case appleOnDevice

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .ollamaLocal: "Ollama Local"
    case .ollamaCloud: "Ollama Cloud"
    case .appleOnDevice: "Apple On-Device"
    }
  }

  public var defaultBaseURL: String {
    switch self {
    case .ollamaLocal: "http://localhost:11434"
    case .ollamaCloud: "https://ollama.com"
    case .appleOnDevice: ""
    }
  }
}

public enum AgentPermissionMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case confirm
  case workspaceTrusted
  case fullAccess

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .confirm: "Bestätigen"
    case .workspaceTrusted: "Workspace Trusted"
    case .fullAccess: "Full Access"
    }
  }

  public var explanation: String {
    switch self {
    case .confirm:
      "Lesezugriffe im Workspace laufen direkt. Schreib- und Shell-Aktionen benötigen eine Freigabe."
    case .workspaceTrusted:
      "Werkzeuge dürfen innerhalb des Workspace automatisch lesen, schreiben und Befehle ausführen."
    case .fullAccess:
      "Werkzeuge dürfen auch außerhalb des Workspace arbeiten. Kritische Systemkommandos bleiben auditierbar."
    }
  }
}

public enum ToolRisk: String, Codable, Sendable {
  case read
  case write
  case execute

  public var displayName: String {
    switch self {
    case .read: "Lesen"
    case .write: "Schreiben"
    case .execute: "Ausführen"
    }
  }
}

public enum ChatRole: String, Codable, Sendable {
  case system
  case user
  case assistant
}

public struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public let role: ChatRole
  public var content: String
  public var thinking: String
  public var toolExecutions: [ToolExecutionRecord]?
  public let createdAt: Date

  public init(
    id: UUID = UUID(),
    role: ChatRole,
    content: String,
    thinking: String = "",
    toolExecutions: [ToolExecutionRecord]? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.role = role
    self.content = content
    self.thinking = thinking
    self.toolExecutions = toolExecutions
    self.createdAt = createdAt
  }
}

public struct ChatMetrics: Codable, Equatable, Sendable {
  public var promptTokens: Int?
  public var generatedTokens: Int?
  public var totalDurationNanoseconds: UInt64?
  public var evaluationDurationNanoseconds: UInt64?

  public init(
    promptTokens: Int? = nil,
    generatedTokens: Int? = nil,
    totalDurationNanoseconds: UInt64? = nil,
    evaluationDurationNanoseconds: UInt64? = nil
  ) {
    self.promptTokens = promptTokens
    self.generatedTokens = generatedTokens
    self.totalDurationNanoseconds = totalDurationNanoseconds
    self.evaluationDurationNanoseconds = evaluationDurationNanoseconds
  }

  public var tokensPerSecond: Double? {
    guard
      let generatedTokens,
      let evaluationDurationNanoseconds,
      evaluationDurationNanoseconds > 0
    else {
      return nil
    }

    let seconds = Double(evaluationDurationNanoseconds) / 1_000_000_000
    return Double(generatedTokens) / seconds
  }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
  public var providerKind: ProviderKind
  public var baseURL: String
  public var model: String
  public var apiKeySecretID: UUID?
  public var systemPrompt: String
  public var thinkingEnabled: Bool
  public var agentEnabled: Bool
  public var permissionMode: AgentPermissionMode
  public var workspacePath: String
  public var maxToolIterations: Int

  public init(
    providerKind: ProviderKind,
    baseURL: String,
    model: String,
    apiKeySecretID: UUID?,
    systemPrompt: String,
    thinkingEnabled: Bool,
    agentEnabled: Bool = true,
    permissionMode: AgentPermissionMode = .confirm,
    workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path,
    maxToolIterations: Int = 8
  ) {
    self.providerKind = providerKind
    self.baseURL = baseURL
    self.model = model
    self.apiKeySecretID = apiKeySecretID
    self.systemPrompt = systemPrompt
    self.thinkingEnabled = thinkingEnabled
    self.agentEnabled = agentEnabled
    self.permissionMode = permissionMode
    self.workspacePath = workspacePath
    self.maxToolIterations = max(1, min(maxToolIterations, 24))
  }

  private enum CodingKeys: String, CodingKey {
    case providerKind
    case baseURL
    case model
    case apiKeySecretID
    case systemPrompt
    case thinkingEnabled
    case agentEnabled
    case permissionMode
    case workspacePath
    case maxToolIterations
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    providerKind = try container.decodeIfPresent(ProviderKind.self, forKey: .providerKind) ?? .ollamaLocal
    baseURL =
      try container.decodeIfPresent(String.self, forKey: .baseURL)
      ?? providerKind.defaultBaseURL
    model = try container.decodeIfPresent(String.self, forKey: .model) ?? "qwen3:8b"
    apiKeySecretID = try container.decodeIfPresent(UUID.self, forKey: .apiKeySecretID)
    systemPrompt =
      try container.decodeIfPresent(String.self, forKey: .systemPrompt)
      ?? AppConfiguration.default.systemPrompt
    thinkingEnabled = try container.decodeIfPresent(Bool.self, forKey: .thinkingEnabled) ?? false
    agentEnabled = try container.decodeIfPresent(Bool.self, forKey: .agentEnabled) ?? true
    permissionMode =
      try container.decodeIfPresent(AgentPermissionMode.self, forKey: .permissionMode)
      ?? .confirm
    workspacePath =
      try container.decodeIfPresent(String.self, forKey: .workspacePath)
      ?? FileManager.default.homeDirectoryForCurrentUser.path
    maxToolIterations = max(
      1,
      min(try container.decodeIfPresent(Int.self, forKey: .maxToolIterations) ?? 8, 24)
    )
  }

  public static let `default` = AppConfiguration(
    providerKind: .ollamaLocal,
    baseURL: ProviderKind.ollamaLocal.defaultBaseURL,
    model: "qwen3:8b",
    apiKeySecretID: nil,
    systemPrompt: """
      Du bist AgenTM5N, ein persönlicher Senior-Software- und DevOps-Agent. Arbeite präzise, reproduzierbar und lösungsorientiert. Verwende vorhandenen Kontext, vermeide erfundene Fakten und kennzeichne Unsicherheit klar. Wenn Werkzeuge verfügbar sind, nutze sie schrittweise und prüfe ihre Ergebnisse, bevor du fortfährst.
      """,
    thinkingEnabled: false,
    agentEnabled: true,
    permissionMode: .confirm,
    workspacePath: FileManager.default.homeDirectoryForCurrentUser.path,
    maxToolIterations: 8
  )
}

public enum SecretKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case apiKey
  case token
  case password
  case sshPrivateKey
  case sshPassphrase
  case databaseConnectionString
  case generic

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .apiKey: "API Key"
    case .token: "Token"
    case .password: "Passwort"
    case .sshPrivateKey: "SSH Private Key"
    case .sshPassphrase: "SSH Passphrase"
    case .databaseConnectionString: "Database Connection String"
    case .generic: "Generic Secret"
    }
  }
}

public struct VaultSecret: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var kind: SecretKind
  public var label: String
  public var username: String
  public var host: String
  public var value: String
  public var notes: String
  public let createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    kind: SecretKind,
    label: String,
    username: String = "",
    host: String = "",
    value: String,
    notes: String = "",
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.kind = kind
    self.label = label
    self.username = username
    self.host = host
    self.value = value
    self.notes = notes
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public var redactedValue: String {
    guard !value.isEmpty else { return "" }
    return String(repeating: "•", count: min(max(value.count, 8), 24))
  }
}

public struct VaultPayload: Codable, Equatable, Sendable {
  public var secrets: [VaultSecret]

  public init(secrets: [VaultSecret] = []) {
    self.secrets = secrets
  }
}

public struct VaultEnvelope: Codable, Equatable, Sendable {
  public let version: Int
  public let salt: Data
  public let iterations: UInt32
  public let sealedPayload: Data

  public init(
    version: Int,
    salt: Data,
    iterations: UInt32,
    sealedPayload: Data
  ) {
    self.version = version
    self.salt = salt
    self.iterations = iterations
    self.sealedPayload = sealedPayload
  }
}

public enum SSHAuthenticationKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case systemDefault
  case password
  case privateKey

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .systemDefault: "System / SSH Agent"
    case .password: "Passwort"
    case .privateKey: "Private Key"
    }
  }
}

public struct SSHHost: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var hostname: String
  public var port: Int
  public var username: String
  public var authenticationKind: SSHAuthenticationKind
  public var authenticationSecretID: UUID?
  public var passphraseSecretID: UUID?
  public var remoteCommand: String
  public let createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    name: String,
    hostname: String,
    port: Int = 22,
    username: String,
    authenticationKind: SSHAuthenticationKind = .systemDefault,
    authenticationSecretID: UUID? = nil,
    passphraseSecretID: UUID? = nil,
    remoteCommand: String = "",
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.hostname = hostname
    self.port = port
    self.username = username
    self.authenticationKind = authenticationKind
    self.authenticationSecretID = authenticationSecretID
    self.passphraseSecretID = passphraseSecretID
    self.remoteCommand = remoteCommand
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct TerminalLaunch: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let title: String
  public let initialCommand: String?
  public let cleanupPaths: [URL]

  public init(
    id: UUID = UUID(),
    title: String,
    initialCommand: String?,
    cleanupPaths: [URL] = []
  ) {
    self.id = id
    self.title = title
    self.initialCommand = initialCommand
    self.cleanupPaths = cleanupPaths
  }
}

public struct HardwareProfile: Equatable, Sendable {
  public let chipName: String
  public let memoryBytes: UInt64
  public let operatingSystem: String
  public let appleFoundationModelStatus: String

  public init(
    chipName: String,
    memoryBytes: UInt64,
    operatingSystem: String,
    appleFoundationModelStatus: String
  ) {
    self.chipName = chipName
    self.memoryBytes = memoryBytes
    self.operatingSystem = operatingSystem
    self.appleFoundationModelStatus = appleFoundationModelStatus
  }

  public var memoryDescription: String {
    ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
  }
}

public struct CoreMLModelDescriptor: Equatable, Sendable {
  public let sourceURL: URL
  public let compiledURL: URL
  public let inputs: [String]
  public let outputs: [String]
  public let computeUnits: String

  public init(
    sourceURL: URL,
    compiledURL: URL,
    inputs: [String],
    outputs: [String],
    computeUnits: String
  ) {
    self.sourceURL = sourceURL
    self.compiledURL = compiledURL
    self.inputs = inputs
    self.outputs = outputs
    self.computeUnits = computeUnits
  }
}

public struct CoreMLPredictionResult: Equatable, Sendable {
  public let values: [String: String]
  public let durationMilliseconds: Double

  public init(values: [String: String], durationMilliseconds: Double) {
    self.values = values
    self.durationMilliseconds = durationMilliseconds
  }
}

public enum JSONValue: Codable, Equatable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported JSON value"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .null:
      try container.encodeNil()
    }
  }

  public var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  public var boolValue: Bool? {
    guard case .bool(let value) = self else { return nil }
    return value
  }

  public var objectValue: [String: JSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }

  public var compactDescription: String {
    switch self {
    case .string(let value): value
    case .number(let value): String(value)
    case .bool(let value): String(value)
    case .object(let value):
      value.keys.sorted().map { "\($0)=\(value[$0]?.compactDescription ?? "null")" }
        .joined(separator: ", ")
    case .array(let value):
      value.map(\.compactDescription).joined(separator: ", ")
    case .null: "null"
    }
  }
}

public struct ProviderToolDefinition: Encodable, Equatable, Sendable {
  public let type: String
  public let function: Function

  public init(name: String, description: String, parameters: JSONValue) {
    type = "function"
    function = Function(name: name, description: description, parameters: parameters)
  }

  public struct Function: Encodable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let parameters: JSONValue
  }
}

public struct ProviderToolCall: Codable, Equatable, Sendable {
  public let type: String?
  public let function: Function

  public init(type: String? = "function", function: Function) {
    self.type = type
    self.function = function
  }

  public struct Function: Codable, Equatable, Sendable {
    public let index: Int?
    public let name: String
    public let arguments: [String: JSONValue]

    public init(
      index: Int? = nil,
      name: String,
      arguments: [String: JSONValue]
    ) {
      self.index = index
      self.name = name
      self.arguments = arguments
    }
  }
}

public enum ProviderMessageRole: String, Encodable, Sendable {
  case system
  case user
  case assistant
  case tool
}

public struct ProviderMessage: Encodable, Sendable {
  public let role: ProviderMessageRole
  public let content: String
  public let thinking: String?
  public let toolCalls: [ProviderToolCall]?
  public let toolName: String?

  public init(
    role: ProviderMessageRole,
    content: String,
    thinking: String? = nil,
    toolCalls: [ProviderToolCall]? = nil,
    toolName: String? = nil
  ) {
    self.role = role
    self.content = content
    self.thinking = thinking
    self.toolCalls = toolCalls
    self.toolName = toolName
  }

  private enum CodingKeys: String, CodingKey {
    case role
    case content
    case thinking
    case toolCalls = "tool_calls"
    case toolName = "tool_name"
  }
}

public enum ToolExecutionStatus: String, Codable, Sendable {
  case running
  case succeeded
  case failed
  case denied
}

public struct ToolExecutionRecord: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public let toolName: String
  public let argumentsSummary: String
  public let risk: ToolRisk
  public var status: ToolExecutionStatus
  public var output: String
  public let startedAt: Date
  public var endedAt: Date?

  public init(
    id: UUID = UUID(),
    toolName: String,
    argumentsSummary: String,
    risk: ToolRisk,
    status: ToolExecutionStatus = .running,
    output: String = "",
    startedAt: Date = Date(),
    endedAt: Date? = nil
  ) {
    self.id = id
    self.toolName = toolName
    self.argumentsSummary = argumentsSummary
    self.risk = risk
    self.status = status
    self.output = output
    self.startedAt = startedAt
    self.endedAt = endedAt
  }
}

public struct ToolExecutionResult: Equatable, Sendable {
  public let success: Bool
  public let output: String
  public let exitCode: Int32?

  public init(success: Bool, output: String, exitCode: Int32? = nil) {
    self.success = success
    self.output = output
    self.exitCode = exitCode
  }
}

public struct PendingToolApproval: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let call: ProviderToolCall
  public let risk: ToolRisk
  public let summary: String

  public init(
    id: UUID = UUID(),
    call: ProviderToolCall,
    risk: ToolRisk,
    summary: String
  ) {
    self.id = id
    self.call = call
    self.risk = risk
    self.summary = summary
  }
}

public struct ProviderStreamEvent: Equatable, Sendable {
  public let contentDelta: String
  public let thinkingDelta: String
  public let toolCalls: [ProviderToolCall]
  public let isFinished: Bool
  public let metrics: ChatMetrics?

  public init(
    contentDelta: String = "",
    thinkingDelta: String = "",
    toolCalls: [ProviderToolCall] = [],
    isFinished: Bool = false,
    metrics: ChatMetrics? = nil
  ) {
    self.contentDelta = contentDelta
    self.thinkingDelta = thinkingDelta
    self.toolCalls = toolCalls
    self.isFinished = isFinished
    self.metrics = metrics
  }
}
