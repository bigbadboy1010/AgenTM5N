import Foundation

public enum HybridRoutingMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case manual
  case adaptive

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .manual: "Manual"
    case .adaptive: "Adaptive"
    }
  }
}

public enum HybridRouteKind: String, Codable, CaseIterable, Sendable {
  case activeProvider
  case modelProfile
  case appleOnDevice
  case meshPeer
  case blocked
}

public struct HybridRoutingConfiguration: Codable, Equatable, Sendable {
  public var mode: HybridRoutingMode
  public var preferLocal: Bool
  public var allowAppleOnDevice: Bool
  public var allowMesh: Bool
  public var requireExplicitMeshIntent: Bool
  public var privacyLockEnabled: Bool
  public var maximumMeshPeersConsidered: Int

  public init(
    mode: HybridRoutingMode = .manual,
    preferLocal: Bool = true,
    allowAppleOnDevice: Bool = true,
    allowMesh: Bool = false,
    requireExplicitMeshIntent: Bool = true,
    privacyLockEnabled: Bool = true,
    maximumMeshPeersConsidered: Int = 8
  ) {
    self.mode = mode
    self.preferLocal = preferLocal
    self.allowAppleOnDevice = allowAppleOnDevice
    self.allowMesh = allowMesh
    self.requireExplicitMeshIntent = requireExplicitMeshIntent
    self.privacyLockEnabled = privacyLockEnabled
    self.maximumMeshPeersConsidered = maximumMeshPeersConsidered
    normalize()
  }

  public static let `default` = HybridRoutingConfiguration()

  private enum CodingKeys: String, CodingKey {
    case mode
    case preferLocal
    case allowAppleOnDevice
    case allowMesh
    case requireExplicitMeshIntent
    case privacyLockEnabled
    case maximumMeshPeersConsidered
  }

  public init(from decoder: Decoder) throws {
    let defaults = Self.default
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode = try container.decodeIfPresent(HybridRoutingMode.self, forKey: .mode) ?? defaults.mode
    preferLocal = try container.decodeIfPresent(Bool.self, forKey: .preferLocal) ?? defaults.preferLocal
    allowAppleOnDevice = try container.decodeIfPresent(Bool.self, forKey: .allowAppleOnDevice)
      ?? defaults.allowAppleOnDevice
    allowMesh = try container.decodeIfPresent(Bool.self, forKey: .allowMesh) ?? defaults.allowMesh
    requireExplicitMeshIntent = try container.decodeIfPresent(Bool.self, forKey: .requireExplicitMeshIntent)
      ?? defaults.requireExplicitMeshIntent
    privacyLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .privacyLockEnabled)
      ?? defaults.privacyLockEnabled
    maximumMeshPeersConsidered = try container.decodeIfPresent(Int.self, forKey: .maximumMeshPeersConsidered)
      ?? defaults.maximumMeshPeersConsidered
    normalize()
  }

  public mutating func normalize() {
    maximumMeshPeersConsidered = max(1, min(maximumMeshPeersConsidered, 64))
  }
}

public struct HybridRouteDecision: Codable, Equatable, Sendable {
  public let id: UUID
  public let kind: HybridRouteKind
  public let peerID: UUID?
  public let profileID: UUID?
  public let profileRuntime: ModelProfileRuntime?
  public let targetName: String
  public let reason: String
  public let confidence: Double
  public let privacyLocked: Bool
  public let requiredCapabilities: Set<AgentToolCapability>
  public let decidedAt: Date

  public init(
    id: UUID = UUID(),
    kind: HybridRouteKind,
    peerID: UUID? = nil,
    profileID: UUID? = nil,
    profileRuntime: ModelProfileRuntime? = nil,
    targetName: String,
    reason: String,
    confidence: Double,
    privacyLocked: Bool = false,
    requiredCapabilities: Set<AgentToolCapability> = [],
    decidedAt: Date = Date()
  ) {
    self.id = id
    self.kind = kind
    self.peerID = peerID
    self.profileID = profileID
    self.profileRuntime = profileRuntime
    self.targetName = targetName
    self.reason = reason
    self.confidence = max(0, min(confidence, 1))
    self.privacyLocked = privacyLocked
    self.requiredCapabilities = requiredCapabilities
    self.decidedAt = decidedAt
  }

  public var isRemote: Bool {
    kind == .meshPeer || profileRuntime == .ollamaCloud
  }

  public var isBlocked: Bool {
    kind == .blocked
  }
}

public struct HybridRoutingSnapshot: Codable, Equatable, Sendable {
  public let lastDecision: HybridRouteDecision?

  public init(lastDecision: HybridRouteDecision? = nil) {
    self.lastDecision = lastDecision
  }
}

public enum HybridRoutingError: LocalizedError, Equatable {
  case blocked(String)
  case peerUnavailable
  case profileUnavailable

  public var errorDescription: String? {
    switch self {
    case .blocked(let reason): reason
    case .peerUnavailable:
      L10n.text(
        de: "Der vom Hybrid Router gewählte Agent-Mesh-Peer ist nicht mehr verfügbar oder nicht mehr vertraut.",
        en: "The Agent Mesh peer selected by the Hybrid Router is no longer available or trusted.",
        fr: "Le pair Agent Mesh sélectionné par le routeur hybride n’est plus disponible ou approuvé."
      )
    case .profileUnavailable:
      L10n.text(
        de: "Das vom Hybrid Router gewählte Modellprofil ist nicht mehr verfügbar oder wurde deaktiviert.",
        en: "The model profile selected by the Hybrid Router is no longer available or has been disabled.",
        fr: "Le profil de modèle sélectionné par le routeur hybride n’est plus disponible ou a été désactivé."
      )
    }
  }
}
