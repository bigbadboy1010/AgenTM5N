import Foundation

public enum AppSection: String, CaseIterable, Identifiable, Sendable {
  case chat = "Chat"
  case terminal = "Terminal"
  case ssh = "SSH"
  case vault = "Vault"
  case neuralEngine = "Neural Engine"
  case settings = "Settings"

  public var id: String { rawValue }

  public var systemImage: String {
    switch self {
    case .chat: "bubble.left.and.bubble.right"
    case .terminal: "terminal"
    case .ssh: "network"
    case .vault: "lock.shield"
    case .neuralEngine: "brain.head.profile"
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
  public let createdAt: Date

  public init(
    id: UUID = UUID(),
    role: ChatRole,
    content: String,
    thinking: String = "",
    createdAt: Date = Date()
  ) {
    self.id = id
    self.role = role
    self.content = content
    self.thinking = thinking
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

  public init(
    providerKind: ProviderKind,
    baseURL: String,
    model: String,
    apiKeySecretID: UUID?,
    systemPrompt: String,
    thinkingEnabled: Bool
  ) {
    self.providerKind = providerKind
    self.baseURL = baseURL
    self.model = model
    self.apiKeySecretID = apiKeySecretID
    self.systemPrompt = systemPrompt
    self.thinkingEnabled = thinkingEnabled
  }

  public static let `default` = AppConfiguration(
    providerKind: .ollamaLocal,
    baseURL: ProviderKind.ollamaLocal.defaultBaseURL,
    model: "qwen3:8b",
    apiKeySecretID: nil,
    systemPrompt: """
      Du bist ein persönlicher Senior-Software- und DevOps-Agent. Arbeite präzise, reproduzierbar und lösungsorientiert. Verwende vorhandenen Kontext, vermeide erfundene Fakten und kennzeichne Unsicherheit klar.
      """,
    thinkingEnabled: false
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

public struct ProviderStreamEvent: Equatable, Sendable {
  public let contentDelta: String
  public let thinkingDelta: String
  public let isFinished: Bool
  public let metrics: ChatMetrics?

  public init(
    contentDelta: String = "",
    thinkingDelta: String = "",
    isFinished: Bool = false,
    metrics: ChatMetrics? = nil
  ) {
    self.contentDelta = contentDelta
    self.thinkingDelta = thinkingDelta
    self.isFinished = isFinished
    self.metrics = metrics
  }
}
