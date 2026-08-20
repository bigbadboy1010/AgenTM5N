import Foundation

public enum AgentMeshProtocol {
  public static let version = 1
  public static let name = "agentm5n-mesh/1"
  public static let defaultPort: UInt16 = 8787
  public static let maximumClockSkewSeconds: TimeInterval = 300
  public static let maximumRequestBytes = 1_048_576
  public static let maximumPromptCharacters = 32_000
  public static let maximumResultCharacters = 64_000
  public static let maximumEventCharacters = 8_000
}

public enum AgentMeshPeerKind: String, Codable, CaseIterable, Sendable {
  case agentM5N
  case agentNexus
}

public enum AgentMeshPeerStatus: String, Codable, CaseIterable, Sendable {
  case pending
  case trusted
  case revoked
}

public struct AgentMeshNodeDescriptor: Codable, Equatable, Sendable {
  public let nodeID: UUID
  public let name: String
  public let kind: AgentMeshPeerKind
  public let protocolVersion: Int
  public let appVersion: String
  public let appBuild: String
  public let signingPublicKey: Data
  public let agreementPublicKey: Data
  public let fingerprint: String
  public let capabilities: Set<AgentToolCapability>
  public let features: [String]
  public let generatedAt: Date

  public init(
    nodeID: UUID,
    name: String,
    kind: AgentMeshPeerKind = .agentM5N,
    protocolVersion: Int = AgentMeshProtocol.version,
    appVersion: String,
    appBuild: String,
    signingPublicKey: Data,
    agreementPublicKey: Data,
    fingerprint: String,
    capabilities: Set<AgentToolCapability>,
    features: [String],
    generatedAt: Date = Date()
  ) {
    self.nodeID = nodeID
    self.name = name
    self.kind = kind
    self.protocolVersion = protocolVersion
    self.appVersion = appVersion
    self.appBuild = appBuild
    self.signingPublicKey = signingPublicKey
    self.agreementPublicKey = agreementPublicKey
    self.fingerprint = fingerprint
    self.capabilities = capabilities
    self.features = features
    self.generatedAt = generatedAt
  }
}

public struct AgentMeshPeerRecord: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var kind: AgentMeshPeerKind
  public var endpoint: String
  public var signingPublicKey: Data
  public var agreementPublicKey: Data
  public var fingerprint: String
  public var status: AgentMeshPeerStatus
  public var allowedCapabilities: Set<AgentToolCapability>
  public var protocolVersion: Int
  public let createdAt: Date
  public var updatedAt: Date
  public var lastSeenAt: Date?

  public init(
    id: UUID,
    name: String,
    kind: AgentMeshPeerKind,
    endpoint: String,
    signingPublicKey: Data,
    agreementPublicKey: Data,
    fingerprint: String,
    status: AgentMeshPeerStatus = .pending,
    allowedCapabilities: Set<AgentToolCapability> = [],
    protocolVersion: Int = AgentMeshProtocol.version,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    lastSeenAt: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.endpoint = endpoint
    self.signingPublicKey = signingPublicKey
    self.agreementPublicKey = agreementPublicKey
    self.fingerprint = fingerprint
    self.status = status
    self.allowedCapabilities = allowedCapabilities
    self.protocolVersion = protocolVersion
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastSeenAt = lastSeenAt
  }
}

public struct AgentMeshEnrollmentRequest: Codable, Equatable, Sendable {
  public let node: AgentMeshNodeDescriptor
  public let callbackEndpoint: String

  public init(node: AgentMeshNodeDescriptor, callbackEndpoint: String) {
    self.node = node
    self.callbackEndpoint = callbackEndpoint
  }
}

public struct AgentMeshEnrollmentResponse: Codable, Equatable, Sendable {
  public let node: AgentMeshNodeDescriptor
  public let status: AgentMeshPeerStatus

  public init(node: AgentMeshNodeDescriptor, status: AgentMeshPeerStatus) {
    self.node = node
    self.status = status
  }
}

public struct AgentMeshSealedMessage: Codable, Equatable, Sendable {
  public let protocolVersion: Int
  public let senderNodeID: UUID
  public let recipientNodeID: UUID
  public let createdAt: Date
  public let sealedPayload: Data

  public init(
    protocolVersion: Int = AgentMeshProtocol.version,
    senderNodeID: UUID,
    recipientNodeID: UUID,
    createdAt: Date = Date(),
    sealedPayload: Data
  ) {
    self.protocolVersion = protocolVersion
    self.senderNodeID = senderNodeID
    self.recipientNodeID = recipientNodeID
    self.createdAt = createdAt
    self.sealedPayload = sealedPayload
  }
}

public struct AgentMeshTaskRequest: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public let correlationID: UUID
  public let prompt: String
  public let requestedCapabilities: Set<AgentToolCapability>
  public let timeoutSeconds: Int
  public let maximumResultCharacters: Int
  public let createdAt: Date

  public init(
    id: UUID = UUID(),
    correlationID: UUID = UUID(),
    prompt: String,
    requestedCapabilities: Set<AgentToolCapability> = [],
    timeoutSeconds: Int = 600,
    maximumResultCharacters: Int = AgentMeshProtocol.maximumResultCharacters,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.correlationID = correlationID
    self.prompt = prompt
    self.requestedCapabilities = requestedCapabilities
    self.timeoutSeconds = max(30, min(timeoutSeconds, 3_600))
    self.maximumResultCharacters = max(1_024, min(maximumResultCharacters, AgentMeshProtocol.maximumResultCharacters))
    self.createdAt = createdAt
  }
}

public enum AgentMeshTaskStatus: String, Codable, CaseIterable, Sendable {
  case queued
  case running
  case waitingForApproval
  case completed
  case failed
  case cancelled
}

public enum AgentMeshTaskEventKind: String, Codable, Sendable {
  case accepted
  case started
  case delta
  case thinking
  case toolRequested
  case toolDenied
  case toolCompleted
  case approvalRequired
  case completed
  case failed
  case cancelled
}

public struct AgentMeshTaskEvent: Codable, Identifiable, Equatable, Sendable {
  public let id: Int
  public let taskID: UUID
  public let kind: AgentMeshTaskEventKind
  public let message: String
  public let createdAt: Date

  public init(
    id: Int,
    taskID: UUID,
    kind: AgentMeshTaskEventKind,
    message: String = "",
    createdAt: Date = Date()
  ) {
    self.id = id
    self.taskID = taskID
    self.kind = kind
    self.message = String(message.prefix(AgentMeshProtocol.maximumEventCharacters))
    self.createdAt = createdAt
  }
}

public struct AgentMeshTaskSnapshot: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public let correlationID: UUID
  public let peerID: UUID
  public let requestedCapabilities: Set<AgentToolCapability>
  public let effectiveCapabilities: Set<AgentToolCapability>
  public var status: AgentMeshTaskStatus
  public var result: String?
  public var error: String?
  public let createdAt: Date
  public var startedAt: Date?
  public var completedAt: Date?

  public init(
    id: UUID,
    correlationID: UUID,
    peerID: UUID,
    requestedCapabilities: Set<AgentToolCapability>,
    effectiveCapabilities: Set<AgentToolCapability>,
    status: AgentMeshTaskStatus = .queued,
    result: String? = nil,
    error: String? = nil,
    createdAt: Date = Date(),
    startedAt: Date? = nil,
    completedAt: Date? = nil
  ) {
    self.id = id
    self.correlationID = correlationID
    self.peerID = peerID
    self.requestedCapabilities = requestedCapabilities
    self.effectiveCapabilities = effectiveCapabilities
    self.status = status
    self.result = result
    self.error = error
    self.createdAt = createdAt
    self.startedAt = startedAt
    self.completedAt = completedAt
  }
}

public struct AgentMeshTaskEventBatch: Codable, Equatable, Sendable {
  public let taskID: UUID
  public let events: [AgentMeshTaskEvent]
  public let nextEventID: Int
  public let terminal: Bool

  public init(
    taskID: UUID,
    events: [AgentMeshTaskEvent],
    nextEventID: Int,
    terminal: Bool
  ) {
    self.taskID = taskID
    self.events = events
    self.nextEventID = nextEventID
    self.terminal = terminal
  }
}

public struct AgentMeshHealthResponse: Codable, Equatable, Sendable {
  public let protocolName: String
  public let protocolVersion: Int
  public let status: String
  public let nodeID: UUID
  public let timestamp: Date

  public init(nodeID: UUID, status: String = "ok") {
    protocolName = AgentMeshProtocol.name
    protocolVersion = AgentMeshProtocol.version
    self.status = status
    self.nodeID = nodeID
    timestamp = Date()
  }
}

public struct AgentMeshCapabilityResponse: Codable, Equatable, Sendable {
  public let capabilities: Set<AgentToolCapability>
  public let features: [String]

  public init(capabilities: Set<AgentToolCapability>, features: [String]) {
    self.capabilities = capabilities
    self.features = features
  }
}

public struct AgentMeshPeerSummary: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public let name: String
  public let kind: AgentMeshPeerKind
  public let status: AgentMeshPeerStatus
  public let allowedCapabilities: Set<AgentToolCapability>
  public let lastSeenAt: Date?

  public init(_ peer: AgentMeshPeerRecord) {
    id = peer.id
    name = peer.name
    kind = peer.kind
    status = peer.status
    allowedCapabilities = peer.allowedCapabilities
    lastSeenAt = peer.lastSeenAt
  }
}
