import AppKit
import Foundation

public enum AgentMeshExecutionError: LocalizedError {
  case notConfigured
  case unsupportedProvider
  case unsupportedTool(String)
  case toolOutsidePeerScope(String)
  case toolLimitReached
  case multipleToolCalls
  case delegationDepthExceeded
  case emptyResult

  public var errorDescription: String? {
    switch self {
    case .notConfigured:
      return "Agent Mesh Execution Service ist nicht konfiguriert."
    case .unsupportedProvider:
      return "Der aktive Modellanbieter wird fuer delegierte Build-40-Tasks noch nicht unterstuetzt."
    case .unsupportedTool(let name):
      return "Tool \(name) ist fuer Remote-Mesh-Tasks nicht freigegeben."
    case .toolOutsidePeerScope(let name):
      return "Tool \(name) liegt ausserhalb des Peer-Capability-Scopes."
    case .toolLimitReached:
      return "Remote Agent Mesh Tool-Limit erreicht."
    case .multipleToolCalls:
      return "Remote Agent Mesh erlaubt hoechstens einen Tool-Aufruf pro Modellrunde."
    case .delegationDepthExceeded:
      return "Maximale Agent-Mesh-Delegationstiefe erreicht."
    case .emptyResult:
      return "Der delegierte Agent-Mesh-Task lieferte kein Ergebnis."
    }
  }
}

public struct AgentMeshAuditEntry: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public let taskID: UUID
  public let peerID: UUID
  public let toolName: String?
  public let risk: ToolRisk?
  public let decision: String
  public let success: Bool?
  public let createdAt: Date

  public init(
    id: UUID = UUID(),
    taskID: UUID,
    peerID: UUID,
    toolName: String? = nil,
    risk: ToolRisk? = nil,
    decision: String,
    success: Bool? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.taskID = taskID
    self.peerID = peerID
    self.toolName = toolName
    self.risk = risk
    self.decision = decision
    self.success = success
    self.createdAt = createdAt
  }
}

public actor AgentMeshAuditStore {
  public static let shared = AgentMeshAuditStore()
  private let fileURL: URL

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      let manager = FileManager.default
      let base = (try? manager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )) ?? manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
      self.fileURL = base
        .appendingPathComponent("AgenTM5N", isDirectory: true)
        .appendingPathComponent("agent-mesh-audit.jsonl", isDirectory: false)
    }
  }

  public func record(_ entry: AgentMeshAuditEntry) {
    do {
      let manager = FileManager.default
      let directory = fileURL.deletingLastPathComponent()
      try manager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      var data = try encoder.encode(entry)
      data.append(0x0A)
      if manager.fileExists(atPath: fileURL.path) {
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
      } else {
        try data.write(to: fileURL, options: [.atomic])
      }
      try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    } catch {
      // Content-free best effort. Never include prompts, arguments, outputs or
      // secrets in a secondary audit failure path.
    }
  }
}

@MainActor
public enum AgentMeshRemoteApproval {
  public static func authorize(
    peer: AgentMeshPeerRecord,
    taskID: UUID,
    toolName: String,
    risk: ToolRisk,
    summary: String
  ) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = risk == .execute ? .critical : .warning
    alert.messageText = L10n.text(
      de: "Remote Agent Mesh Aktion bestaetigen",
      en: "Confirm remote Agent Mesh action",
      fr: "Confirmer l'action Agent Mesh distante"
    )
    alert.informativeText = """
    Peer: \(peer.name)
    Fingerprint: \(peer.fingerprint)
    Task: \(taskID.uuidString)
    Tool: \(toolName)
    Risiko: \(risk.displayName)

    \(summary)
    """
    alert.addButton(withTitle: L10n.text(de: "Einmal erlauben", en: "Allow once", fr: "Autoriser une fois"))
    alert.addButton(withTitle: L10n.text(de: "Ablehnen", en: "Deny", fr: "Refuser"))
    return alert.runModal() == .alertFirstButtonReturn
  }
}

public actor AgentMeshExecutionService {
  public static let shared = AgentMeshExecutionService()

  private let provider = OllamaProvider()
  private let runtime = AgentRuntime()
  private let audit = AgentMeshAuditStore.shared
  private var configuration: AppConfiguration?

  private static let maximumRemoteToolRounds = 12
  private static let supportedRuntimeToolNames: Set<String> = [
    "list_directory",
    "glob_files",
    "search_text",
    "read_file",
    "apply_patch",
    "write_file",
    "run_command",
    "git_status",
    "git_diff",
    "git_branches",
    "git_checkout",
    "git_commit",
  ]

  public init() {}

  public func configure(_ configuration: AppConfiguration) async {
    self.configuration = configuration
    await AgentMeshTaskCoordinator.shared.installExecutor { request, peer, capabilities, sink in
      try await AgentMeshExecutionService.shared.execute(
        request: request,
        peer: peer,
        effectiveCapabilities: capabilities,
        sink: sink
      )
    }
  }

  public func execute(
    request: AgentMeshTaskRequest,
    peer: AgentMeshPeerRecord,
    effectiveCapabilities: Set<AgentToolCapability>,
    sink: @escaping AgentMeshTaskCoordinator.EventSink
  ) async throws -> String {
    guard var configuration else { throw AgentMeshExecutionError.notConfigured }
    guard configuration.providerKind == .ollamaLocal else {
      throw AgentMeshExecutionError.unsupportedProvider
    }
    guard AgentDelegationContext.depth < AgentDelegationContext.maximumDepth else {
      throw AgentMeshExecutionError.delegationDepthExceeded
    }

    configuration.agentEnabled = true
    configuration.maxToolIterations = min(
      max(1, configuration.maxToolIterations),
      Self.maximumRemoteToolRounds
    )

    await audit.record(
      AgentMeshAuditEntry(
        taskID: request.id,
        peerID: peer.id,
        decision: "task_started"
      )
    )

    return try await AgentDelegationContext.$depth.withValue(
      AgentDelegationContext.depth + 1
    ) {
      try await AgentCapabilityExecutionContext.$allowedCapabilities.withValue(effectiveCapabilities) {
        try await runProviderLoop(
          request: request,
          peer: peer,
          effectiveCapabilities: effectiveCapabilities,
          configuration: configuration,
          sink: sink
        )
      }
    }
  }

  private func runProviderLoop(
    request: AgentMeshTaskRequest,
    peer: AgentMeshPeerRecord,
    effectiveCapabilities: Set<AgentToolCapability>,
    configuration: AppConfiguration,
    sink: @escaping AgentMeshTaskCoordinator.EventSink
  ) async throws -> String {
    let system = """
    You are AgenTM5N executing a delegated Agent Mesh task from authenticated peer \(peer.name).
    Peer fingerprint: \(peer.fingerprint).
    Work only inside the capabilities explicitly advertised for this task. Never invent tool results.
    Remote writes, execution and personal-data access require local approval outside the model.
    Complete the requested task and return a concise result to the calling peer.
    """
    var messages: [ProviderMessage] = [
      ProviderMessage(role: .system, content: system),
      ProviderMessage(role: .user, content: request.prompt),
    ]
    let tools = supportedTools(capabilities: effectiveCapabilities)
    var rounds = 0
    var finalText = ""

    while true {
      try Task.checkCancellation()
      var turnContent = ""
      var turnThinking = ""
      var turnCalls: [ProviderToolCall] = []

      let stream = provider.streamChat(
        configuration: configuration,
        apiKey: nil,
        messages: messages,
        tools: tools
      )
      for try await event in stream {
        try Task.checkCancellation()
        if !event.contentDelta.isEmpty {
          turnContent += event.contentDelta
          await sink(.delta, event.contentDelta)
        }
        if !event.thinkingDelta.isEmpty {
          turnThinking += event.thinkingDelta
          await sink(.thinking, "thinking")
        }
        merge(event.toolCalls, into: &turnCalls)
      }

      guard turnCalls.count <= 1 else {
        throw AgentMeshExecutionError.multipleToolCalls
      }

      messages.append(
        ProviderMessage(
          role: .assistant,
          content: turnContent,
          thinking: turnThinking.isEmpty ? nil : turnThinking,
          toolCalls: turnCalls.isEmpty ? nil : turnCalls
        )
      )
      if !turnContent.isEmpty { finalText = turnContent }

      guard let call = turnCalls.first else { break }
      guard rounds < configuration.maxToolIterations,
        rounds < Self.maximumRemoteToolRounds
      else {
        throw AgentMeshExecutionError.toolLimitReached
      }
      rounds += 1

      let toolResult = await executeTool(
        call,
        request: request,
        peer: peer,
        effectiveCapabilities: effectiveCapabilities,
        configuration: configuration,
        sink: sink
      )
      messages.append(toolResult)
    }

    let clean = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { throw AgentMeshExecutionError.emptyResult }
    await audit.record(
      AgentMeshAuditEntry(
        taskID: request.id,
        peerID: peer.id,
        decision: "task_completed",
        success: true
      )
    )
    return String(clean.prefix(request.maximumResultCharacters))
  }

  private func supportedTools(
    capabilities: Set<AgentToolCapability>
  ) -> [ProviderToolDefinition] {
    AgentToolRegistry.definitions(capabilities: capabilities).filter { definition in
      let name = definition.function.name
      return Self.supportedRuntimeToolNames.contains(name)
        || MacNativeAgentTools.definitions.contains(where: { $0.function.name == name })
        || MacNativeMutationAgentTools.definitions.contains(where: { $0.function.name == name })
    }
  }

  private func executeTool(
    _ call: ProviderToolCall,
    request: AgentMeshTaskRequest,
    peer: AgentMeshPeerRecord,
    effectiveCapabilities: Set<AgentToolCapability>,
    configuration: AppConfiguration,
    sink: @escaping AgentMeshTaskCoordinator.EventSink
  ) async -> ProviderMessage {
    guard let entry = AgentToolRegistry.entry(named: call.function.name),
      effectiveCapabilities.contains(entry.capability)
    else {
      await sink(.toolDenied, call.function.name)
      return ProviderMessage(
        role: .tool,
        content: AgentMeshExecutionError.toolOutsidePeerScope(call.function.name).localizedDescription,
        toolName: call.function.name
      )
    }

    // Re-check trust immediately before every remote-requested tool. Revoking a
    // peer therefore closes the execution boundary even for a task that was
    // already running when the trust record changed.
    guard let currentPeer = try? await AgentMeshPeerStore.shared.trustedPeer(id: peer.id),
      currentPeer != nil
    else {
      await sink(.toolDenied, call.function.name)
      return ProviderMessage(
        role: .tool,
        content: AgentMeshSecurityError.peerNotTrusted.localizedDescription,
        toolName: call.function.name
      )
    }

    guard isSupported(call.function.name) else {
      await sink(.toolDenied, call.function.name)
      return ProviderMessage(
        role: .tool,
        content: AgentMeshExecutionError.unsupportedTool(call.function.name).localizedDescription,
        toolName: call.function.name
      )
    }

    let risk = resolvedRisk(call, fallback: entry.risk)
    let summary = resolvedSummary(call)
    await sink(.toolRequested, "\(call.function.name) [\(risk.rawValue)]")

    let personalData = entry.capability == .macPersonal || entry.capability == .reminders
    let requiresLocalApproval = risk != .read || personalData
    let allowed: Bool
    if requiresLocalApproval {
      await sink(
        .approvalRequired,
        personalData
          ? "\(call.function.name) requires local approval for personal data"
          : "\(call.function.name) requires local approval"
      )
      allowed = await MainActor.run {
        AgentMeshRemoteApproval.authorize(
          peer: peer,
          taskID: request.id,
          toolName: call.function.name,
          risk: risk,
          summary: summary
        )
      }
    } else {
      allowed = true
    }

    await audit.record(
      AgentMeshAuditEntry(
        taskID: request.id,
        peerID: peer.id,
        toolName: call.function.name,
        risk: risk,
        decision: allowed ? "approved" : "denied"
      )
    )

    guard allowed else {
      await sink(.toolDenied, call.function.name)
      return ProviderMessage(
        role: .tool,
        content: "Remote tool execution denied by the local AgenTM5N user.",
        toolName: call.function.name
      )
    }

    let result: ToolExecutionResult
    if MacNativeAgentTools.handles(call) {
      result = await MacNativeAgentTools.execute(call: call)
    } else if MacNativeMutationAgentTools.handles(call) {
      result = await MacNativeMutationAgentTools.execute(call: call)
    } else {
      result = await runtime.execute(
        call: call,
        workspacePath: configuration.workspacePath,
        permissionMode: .confirm
      )
    }

    await audit.record(
      AgentMeshAuditEntry(
        taskID: request.id,
        peerID: peer.id,
        toolName: call.function.name,
        risk: risk,
        decision: "executed",
        success: result.success
      )
    )
    await sink(.toolCompleted, "\(call.function.name): \(result.success ? "ok" : "failed")")

    return ProviderMessage(
      role: .tool,
      content: String(result.output.prefix(12_000)),
      toolName: call.function.name
    )
  }

  private func isSupported(_ name: String) -> Bool {
    Self.supportedRuntimeToolNames.contains(name)
      || MacNativeAgentTools.definitions.contains { $0.function.name == name }
      || MacNativeMutationAgentTools.definitions.contains { $0.function.name == name }
  }

  private func resolvedRisk(
    _ call: ProviderToolCall,
    fallback: ToolRisk
  ) -> ToolRisk {
    if MacNativeMutationAgentTools.handles(call) {
      return MacNativeMutationAgentTools.risk(for: call)
    }
    if MacNativeAgentTools.handles(call) { return .read }
    return fallback
  }

  private func resolvedSummary(_ call: ProviderToolCall) -> String {
    if MacNativeMutationAgentTools.handles(call) {
      return MacNativeMutationAgentTools.summary(for: call)
    }
    if MacNativeAgentTools.handles(call) {
      return MacNativeAgentTools.summary(for: call)
    }
    let arguments = call.function.arguments.keys.sorted().map { key in
      let value = call.function.arguments[key]?.compactDescription ?? "null"
      if ["content", "old_text", "new_text", "body"].contains(key) {
        return "\(key)=<\(value.utf8.count) bytes>"
      }
      return "\(key)=\(String(value.prefix(180)))"
    }
    return arguments.isEmpty ? call.function.name : "\(call.function.name): \(arguments.joined(separator: ", "))"
  }

  private func merge(
    _ incoming: [ProviderToolCall],
    into existing: inout [ProviderToolCall]
  ) {
    for call in incoming {
      if let index = call.function.index,
        let position = existing.firstIndex(where: { $0.function.index == index })
      {
        existing[position] = call
      } else if !existing.contains(call) {
        existing.append(call)
      }
    }
  }
}
