import Foundation

@MainActor
extension AppState {
  func registryRiskAndSummary(
    for call: ProviderToolCall
  ) async -> (risk: ToolRisk, summary: String) {
    let risk = AgentToolRegistry.entry(named: call.function.name)?.risk ?? .execute

    if BrowserBatchAgentTools.handles(call) {
      return (risk, BrowserBatchAgentTools.summary(for: call))
    }
    if BrowserAgentTools.handles(call) {
      return (risk, BrowserAgentTools.summary(for: call))
    }
    if EdgeAgentTools.handles(call) {
      return (risk, EdgeAgentTools.summary(for: call))
    }
    if SelfBuiltToolAgentTools.handles(call) {
      return (risk, SelfBuiltToolAgentTools.summary(for: call))
    }
    if PlatformExpansionAgentTools.handles(call) {
      return (risk, PlatformExpansionAgentTools.summary(for: call))
    }
    if RemindersAgentTools.handles(call) {
      return (risk, RemindersAgentTools.summary(for: call))
    }
    if AgentDelegationTools.handles(call) {
      return (risk, AgentDelegationTools.summary(for: call))
    }
    if WorkflowAgentTools.handles(call) {
      return (risk, await workflowApprovalSummary(for: call))
    }
    if MacNativeAgentTools.handles(call) {
      return (risk, MacNativeAgentTools.summary(for: call))
    }
    if MacNativeMutationAgentTools.handles(call) {
      return (risk, MacNativeMutationAgentTools.summary(for: call))
    }
    if PersistentAgentTools.handles(call) {
      return (risk, PersistentAgentTools.summary(for: call))
    }
    if GeneratedDocumentAgentTools.handles(call) {
      return (risk, GeneratedDocumentAgentTools.summary(for: call))
    }
    if UnifiedContextAgentTools.handles(call) {
      return (risk, UnifiedContextAgentTools.summary(for: call))
    }
    if CoreMLAgentTools.handles(call) {
      return (risk, CoreMLAgentTools.summary(for: call))
    }
    if WorkspaceMemoryAgentTools.handles(call) {
      return (risk, WorkspaceMemoryAgentTools.summary(for: call))
    }
    if ConversationAttachmentAgentTools.handles(call) {
      return (risk, ConversationAttachmentAgentTools.summary(for: call))
    }
    if KnowledgeLibraryAgentTools.handles(call) {
      return (risk, KnowledgeLibraryAgentTools.summary(for: call))
    }

    return (risk, genericRegistrySummary(call))
  }

  func capabilityDenialResult(
    for call: ProviderToolCall,
    explicitScope: Set<AgentToolCapability>? = nil
  ) -> ToolExecutionResult? {
    if let denial = SelfBuiltToolReplacementPolicy.denial(for: call) {
      return denial
    }

    let scope = explicitScope ?? AgentCapabilityExecutionContext.allowedCapabilities
    guard let scope else { return nil }
    guard AgentToolRegistry.isAllowed(call.function.name, within: scope) else {
      let capability = AgentToolRegistry.entry(named: call.function.name)?.capability.rawValue
        ?? "unknown"
      return ToolExecutionResult(
        success: false,
        output: "CAPABILITY_DENIED: Tool \(call.function.name) benötigt Capability \(capability), die diesem Spezial-Agenten nicht freigegeben ist."
      )
    }
    return nil
  }

  func executeMeasuredTool(
    call: ProviderToolCall,
    risk: ToolRisk,
    operation: () async -> ToolExecutionResult
  ) async -> ToolExecutionResult {
    let startedAt = Date()
    let entry = AgentToolRegistry.entry(named: call.function.name)
    let ttl = ToolResultCache.shared.ttl(for: call.function.name)

    if let denial = capabilityDenialResult(for: call) {
      let sanitized = sanitizeToolResult(denial)
      recordTelemetry(
        call: call,
        risk: risk,
        result: sanitized,
        startedAt: startedAt,
        cacheHit: false
      )
      return sanitized
    }

    if risk == .read, entry?.cacheable == true,
      let cached = await ToolResultCache.shared.result(for: call)
    {
      let sanitized = sanitizeToolResult(cached)
      recordTelemetry(
        call: call,
        risk: risk,
        result: sanitized,
        startedAt: startedAt,
        cacheHit: true
      )
      return sanitized
    }

    if let blockReason = await ToolStagnationGuard.shared.blockReason(for: call) {
      let blocked = ToolExecutionResult(success: false, output: blockReason)
      let sanitized = sanitizeToolResult(blocked)
      recordTelemetry(
        call: call,
        risk: risk,
        result: sanitized,
        startedAt: startedAt,
        cacheHit: false
      )
      return sanitized
    }

    let raw = await operation()
    let result = sanitizeToolResult(raw)

    if risk == .read, entry?.cacheable == true, ttl > 0 {
      await ToolResultCache.shared.store(result, for: call, ttl: ttl)
    } else if risk != .read {
      await ToolResultCache.shared.invalidateAll()
    }

    recordTelemetry(
      call: call,
      risk: risk,
      result: result,
      startedAt: startedAt,
      cacheHit: false
    )
    return result
  }

  func requiresWorkspaceTrustedApproval(
    call: ProviderToolCall,
    risk: ToolRisk
  ) -> Bool {
    AgentToolRegistry.requiresWorkspaceTrustedApproval(
      call.function.name,
      risk: risk
    )
  }

  func isPlatformExpansionCall(_ call: ProviderToolCall) -> Bool {
    BrowserBatchAgentTools.handles(call)
      || SelfBuiltToolAgentTools.handles(call)
      || EdgeAgentTools.handles(call)
      || PlatformExpansionAgentTools.handles(call)
      || RemindersAgentTools.handles(call)
      || AgentDelegationTools.handles(call)
      || WorkflowAgentTools.handles(call)
  }

  private func workflowApprovalSummary(for call: ProviderToolCall) async -> String {
    let base = WorkflowAgentTools.summary(for: call)
    guard call.function.name == "workflow_run",
      let query = call.function.arguments["workflow"]?.stringValue,
      let workflow = try? AgentWorkflowLibrary.shared.resolve(query)
    else {
      return base
    }

    var stepSummaries: [String] = []
    for (index, step) in workflow.steps.prefix(20).enumerated() {
      let stepCall = ProviderToolCall(
        function: .init(name: step.toolName, arguments: step.arguments)
      )
      let routing = await registryRiskAndSummary(for: stepCall)
      let bounded = routing.summary.count > 500
        ? String(routing.summary.prefix(500)) + "…"
        : routing.summary
      stepSummaries.append("\(index + 1). [\(routing.risk.displayName)] \(bounded)")
    }

    return """
      \(base)
      Gespeicherte Workflow-Schritte (eine Freigabe für den gesamten Ablauf):
      \(stepSummaries.joined(separator: "\n"))
      """
  }

  private func sanitizeToolResult(_ result: ToolExecutionResult) -> ToolExecutionResult {
    ToolExecutionResult(
      success: result.success,
      output: SecureSecretBroker.redact(result.output, secrets: secrets)
    )
  }

  private func recordTelemetry(
    call: ProviderToolCall,
    risk: ToolRisk,
    result: ToolExecutionResult,
    startedAt: Date,
    cacheHit: Bool
  ) {
    let endedAt = Date()
    let milliseconds = max(0, endedAt.timeIntervalSince(startedAt) * 1_000)
    let entry = AgentToolRegistry.entry(named: call.function.name)
    ToolTelemetryStore.shared.record(
      ToolTelemetryEntry(
        startedAt: startedAt,
        endedAt: endedAt,
        toolName: call.function.name,
        capability: entry?.capability.rawValue ?? "unknown",
        provider: configuration.providerKind.displayName,
        risk: risk,
        success: result.success,
        durationMilliseconds: milliseconds,
        outputBytes: result.output.utf8.count,
        cacheHit: cacheHit
      )
    )
  }

  private func genericRegistrySummary(_ call: ProviderToolCall) -> String {
    let values = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      let lower = key.lowercased()
      if lower == "body" || lower == "content" || lower == "text"
        || lower == "instructions" || lower == "old_text" || lower == "new_text"
        || lower == "source" || lower == "arguments" || lower == "arguments_json"
      {
        return "\(key): <\(value.compactDescription.utf8.count) Bytes>"
      }
      if lower.contains("password") || lower.contains("token")
        || lower.contains("private_key") || lower.contains("passphrase")
      {
        return "\(key): <redacted>"
      }
      let rendered = value.compactDescription
      return "\(key): \(rendered.count > 180 ? String(rendered.prefix(180)) + "…" : rendered)"
    }
    return values.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(values.joined(separator: ", "))"
  }
}
