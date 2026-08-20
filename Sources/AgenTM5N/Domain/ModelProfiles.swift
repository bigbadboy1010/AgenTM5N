import Foundation

public enum ModelProfileRuntime: String, Codable, CaseIterable, Identifiable, Sendable {
  case ollamaLocal
  case ollamaCloud
  case mlx
  case anemll
  case appleFoundationModels

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .ollamaLocal: "Ollama Local"
    case .ollamaCloud: "Ollama Cloud"
    case .mlx: "MLX"
    case .anemll: "ANEMLL / Neural Engine"
    case .appleFoundationModels: "Apple Foundation Models"
    }
  }

  public var isLocal: Bool {
    self != .ollamaCloud
  }

  public var defaultBaseURL: String {
    switch self {
    case .ollamaLocal: LocalInferenceRuntime.ollama.defaultBaseURL
    case .ollamaCloud: ProviderKind.ollamaCloud.defaultBaseURL
    case .mlx: LocalInferenceRuntime.mlxServer.defaultBaseURL
    case .anemll: LocalInferenceRuntime.anemll.defaultBaseURL
    case .appleFoundationModels: ""
    }
  }

  public var providerKind: ProviderKind {
    switch self {
    case .ollamaLocal, .mlx, .anemll: .ollamaLocal
    case .ollamaCloud: .ollamaCloud
    case .appleFoundationModels: .appleOnDevice
    }
  }

  public var localInferenceRuntime: LocalInferenceRuntime? {
    switch self {
    case .ollamaLocal: .ollama
    case .mlx: .mlxServer
    case .anemll: .anemll
    case .ollamaCloud, .appleFoundationModels: nil
    }
  }
}

public enum ModelProfileCapability: String, Codable, CaseIterable, Identifiable, Sendable {
  case textGeneration
  case streaming
  case toolCalling
  case thinking
  case imageInput
  case onDevice
  case neuralEngineOptimized

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .textGeneration: "Text Generation"
    case .streaming: "Streaming"
    case .toolCalling: "Tool Calling"
    case .thinking: "Thinking"
    case .imageInput: "Image Input"
    case .onDevice: "On-Device"
    case .neuralEngineOptimized: "Neural Engine optimized"
    }
  }
}

public struct ModelProfileActivationPlan: Equatable, Sendable {
  public let providerKind: ProviderKind
  public let localInferenceRuntime: LocalInferenceRuntime?
  public let baseURL: String
  public let model: String
  public let apiKeySecretID: UUID?
  public let contextWindow: Int

  public init(
    providerKind: ProviderKind,
    localInferenceRuntime: LocalInferenceRuntime?,
    baseURL: String,
    model: String,
    apiKeySecretID: UUID?,
    contextWindow: Int
  ) {
    self.providerKind = providerKind
    self.localInferenceRuntime = localInferenceRuntime
    self.baseURL = baseURL
    self.model = model
    self.apiKeySecretID = apiKeySecretID
    self.contextWindow = contextWindow
  }
}

public struct ModelProfile: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var runtime: ModelProfileRuntime
  public var modelIdentifier: String
  public var baseURL: String
  public var apiKeySecretID: UUID?
  public var contextWindow: Int
  public var estimatedMemoryMB: Int?
  public var priority: Int
  public var enabled: Bool
  public var capabilities: Set<ModelProfileCapability>
  public let createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    name: String,
    runtime: ModelProfileRuntime,
    modelIdentifier: String,
    baseURL: String? = nil,
    apiKeySecretID: UUID? = nil,
    contextWindow: Int = 8_192,
    estimatedMemoryMB: Int? = nil,
    priority: Int = 100,
    enabled: Bool = true,
    capabilities: Set<ModelProfileCapability> = [.textGeneration, .streaming],
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.runtime = runtime
    self.modelIdentifier = modelIdentifier
    self.baseURL = baseURL ?? runtime.defaultBaseURL
    self.apiKeySecretID = apiKeySecretID
    self.contextWindow = contextWindow
    self.estimatedMemoryMB = estimatedMemoryMB
    self.priority = priority
    self.enabled = enabled
    self.capabilities = capabilities
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    normalize()
  }

  public mutating func normalize() {
    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty { name = runtime.displayName }
    modelIdentifier = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if runtime == .appleFoundationModels {
      baseURL = ""
      if modelIdentifier.isEmpty { modelIdentifier = "SystemLanguageModel.default" }
      apiKeySecretID = nil
      capabilities.insert(.onDevice)
    } else if baseURL.isEmpty {
      baseURL = runtime.defaultBaseURL
    }
    if runtime.isLocal { apiKeySecretID = nil }
    contextWindow = max(128, min(contextWindow, 1_048_576))
    if let estimatedMemoryMB {
      self.estimatedMemoryMB = max(1, min(estimatedMemoryMB, 1_048_576))
    }
    priority = max(0, min(priority, 1_000))
    capabilities.insert(.textGeneration)
    if runtime.isLocal { capabilities.insert(.onDevice) }
    if runtime == .anemll { capabilities.insert(.neuralEngineOptimized) }
  }

  public var activationPlan: ModelProfileActivationPlan {
    ModelProfileActivationPlan(
      providerKind: runtime.providerKind,
      localInferenceRuntime: runtime.localInferenceRuntime,
      baseURL: baseURL,
      model: modelIdentifier,
      apiKeySecretID: apiKeySecretID,
      contextWindow: contextWindow
    )
  }

  public static func fromCurrentConfiguration(
    app: AppConfiguration,
    operating: AgentOperatingLayerConfiguration,
    name: String? = nil
  ) -> ModelProfile {
    let runtime: ModelProfileRuntime
    switch app.providerKind {
    case .ollamaCloud:
      runtime = .ollamaCloud
    case .appleOnDevice:
      runtime = .appleFoundationModels
    case .ollamaLocal:
      switch operating.localInferenceRuntime {
      case .ollama: runtime = .ollamaLocal
      case .mlxServer: runtime = .mlx
      case .anemll: runtime = .anemll
      }
    }

    var capabilities: Set<ModelProfileCapability> = [.textGeneration, .streaming]
    if app.agentEnabled { capabilities.insert(.toolCalling) }
    if app.thinkingEnabled || operating.thinkingMode != .off { capabilities.insert(.thinking) }
    if runtime.isLocal { capabilities.insert(.onDevice) }
    if runtime == .anemll { capabilities.insert(.neuralEngineOptimized) }

    return ModelProfile(
      name: name ?? "\(runtime.displayName) · \(app.model)",
      runtime: runtime,
      modelIdentifier: app.providerKind == .appleOnDevice ? "SystemLanguageModel.default" : app.model,
      baseURL: app.baseURL,
      apiKeySecretID: app.apiKeySecretID,
      contextWindow: operating.numContext,
      priority: 100,
      enabled: true,
      capabilities: capabilities
    )
  }
}

public struct ModelProfileDocument: Codable, Equatable, Sendable {
  public var version: Int
  public var activeProfileID: UUID?
  public var profiles: [ModelProfile]

  public init(version: Int = 1, activeProfileID: UUID? = nil, profiles: [ModelProfile] = []) {
    self.version = version
    self.activeProfileID = activeProfileID
    self.profiles = profiles
  }
}

public enum ModelProfileCatalog {
  public static func routingCandidates(
    from profiles: [ModelProfile],
    preferLocal: Bool
  ) -> [ModelProfile] {
    profiles
      .filter(\.enabled)
      .sorted { lhs, rhs in
        if preferLocal, lhs.runtime.isLocal != rhs.runtime.isLocal {
          return lhs.runtime.isLocal && !rhs.runtime.isLocal
        }
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        let leftName = lhs.name.lowercased()
        let rightName = rhs.name.lowercased()
        if leftName != rightName { return leftName < rightName }
        return lhs.id.uuidString < rhs.id.uuidString
      }
  }

  public static var appleBuiltIn: ModelProfile {
    ModelProfile(
      id: UUID(uuidString: "B42A0000-0000-4000-8000-000000000001")!,
      name: "Apple Foundation Models",
      runtime: .appleFoundationModels,
      modelIdentifier: "SystemLanguageModel.default",
      contextWindow: 4_096,
      estimatedMemoryMB: nil,
      priority: 90,
      enabled: true,
      capabilities: [.textGeneration, .toolCalling, .onDevice]
    )
  }
}

public enum ModelProfileError: LocalizedError, Equatable {
  case profileNotFound
  case profileDisabled
  case missingCloudSecretReference

  public var errorDescription: String? {
    switch self {
    case .profileNotFound: "Das Modellprofil wurde nicht gefunden."
    case .profileDisabled: "Das Modellprofil ist deaktiviert."
    case .missingCloudSecretReference: "Das Cloud-Modellprofil besitzt keine Vault-Secret-Referenz für den API-Key."
    }
  }
}
