import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public enum AppleFoundationModelsProviderError: LocalizedError {
  case unavailable(String)
  case unsupportedPlatform
  case missingUserPrompt

  public var errorDescription: String? {
    switch self {
    case .unavailable(let reason):
      return reason
    case .unsupportedPlatform:
      return "Apple Foundation Models sind auf diesem System nicht verfügbar."
    case .missingUserPrompt:
      return "Es wurde keine Benutzeranfrage für Apple Foundation Models gefunden."
    }
  }
}

public final class AppleFoundationModelsProvider: @unchecked Sendable {
  public init() {}

  public func availabilityDescription() async -> String {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      switch SystemLanguageModel.default.availability {
      case .available:
        return "Apple Foundation Models verfügbar"
      case .unavailable(let reason):
        return "Apple Foundation Models nicht verfügbar: \(String(describing: reason))"
      }
    }
    #endif
    return "Apple Foundation Models werden von diesem macOS nicht unterstützt"
  }

  public func complete(
    configuration: AppConfiguration,
    messages: [ChatMessage]
  ) async throws -> ProviderStreamEvent {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      return try await completeAvailable(
        configuration: configuration,
        messages: messages
      )
    }
    #endif
    throw AppleFoundationModelsProviderError.unsupportedPlatform
  }

  #if canImport(FoundationModels)
  @available(macOS 26.0, *)
  private func completeAvailable(
    configuration: AppConfiguration,
    messages: [ChatMessage]
  ) async throws -> ProviderStreamEvent {
    let model = SystemLanguageModel.default
    guard case .available = model.availability else {
      throw AppleFoundationModelsProviderError.unavailable(
        "Apple Foundation Models sind derzeit nicht verfügbar: \(String(describing: model.availability))"
      )
    }

    let providerMessages = messages.map { message in
      ProviderMessage(
        role: message.role == .system ? .system : (message.role == .user ? .user : .assistant),
        content: message.content,
        thinking: message.thinking.isEmpty ? nil : message.thinking
      )
    }
    return try await completeAvailable(
      configuration: configuration,
      messages: providerMessages
    )
  }

  @available(macOS 26.0, *)
  public func complete(
    configuration: AppConfiguration,
    messages: [ProviderMessage]
  ) async throws -> ProviderStreamEvent {
    try await completeAvailable(configuration: configuration, messages: messages)
  }

  @available(macOS 26.0, *)
  private func completeAvailable(
    configuration: AppConfiguration,
    messages: [ProviderMessage]
  ) async throws -> ProviderStreamEvent {
    let model = SystemLanguageModel.default
    guard case .available = model.availability else {
      throw AppleFoundationModelsProviderError.unavailable(
        "Apple Foundation Models sind derzeit nicht verfügbar: \(String(describing: model.availability))"
      )
    }

    let operating = AgentOperatingLayerStore.load()
    let selection = AppleFoundationModelToolSelection.make(
      messages: messages,
      operatingConfiguration: operating
    )
    let capabilityScope = AgentCapabilityExecutionContext.allowedCapabilities
    let temporalContext = AgentRuntimeContext.currentTemporalContext()
    let instructions = Self.makeInstructions(
      messages: messages,
      temporalContext: temporalContext,
      selection: selection
    )

    var tools: [any Tool] = []
    if configuration.agentEnabled {
      if let focused = selection.focused {
        switch focused {
        case .document:
          if Self.isAllowed(.documents, in: capabilityScope) {
            tools.append(contentsOf: AppleRequiredDocumentTools.makeTools())
          }
        case .clipboard:
          if Self.isAllowed(.system, in: capabilityScope) {
            tools.append(contentsOf: AppleRequiredClipboardTools.makeReadTools())
          }
        case .calendarCreate:
          if Self.isAllowed(.macPersonal, in: capabilityScope) {
            tools.append(AppleLocalCalendarCreateTool())
          }
        }
      } else {
        if selection.browser,
          Self.isAllowed(.http, in: capabilityScope)
        {
          tools.append(contentsOf: AppleRoutedBrowserTools.makeTools())
        }
        if selection.edge,
          Self.isAllowed(.edge, in: capabilityScope)
        {
          tools.append(contentsOf: AppleRoutedEdgeTools.makeTools())
        }
        if selection.knowledgeMemory {
          if Self.isAllowed(.memory, in: capabilityScope) {
            tools.append(contentsOf: AppleRoutedKnowledgeMemoryTools.makeMemoryTools())
            tools.append(contentsOf: AppleRoutedKnowledgeMemoryTools.makeContextTools())
          }
          if Self.isAllowed(.knowledge, in: capabilityScope) {
            tools.append(contentsOf: AppleRoutedKnowledgeMemoryTools.makeKnowledgeTools())
          }
          if Self.isAllowed(.attachments, in: capabilityScope) {
            tools.append(contentsOf: AppleRoutedKnowledgeMemoryTools.makeAttachmentTools())
          }
          if Self.isAllowed(.documents, in: capabilityScope) {
            tools.append(contentsOf: AppleRoutedKnowledgeMemoryTools.makeDocumentTools())
          }
          if Self.isAllowed(.coreML, in: capabilityScope) {
            tools.append(contentsOf: AppleRoutedKnowledgeMemoryTools.makeCoreMLTools())
          }
        }
        if selection.macNative,
          Self.isAllowed(.macPersonal, in: capabilityScope)
        {
          tools.append(contentsOf: AppleRoutedMacNativeTools.makeTools())
        }
        if selection.persistentAgents,
          Self.isAllowed(.agents, in: capabilityScope)
        {
          tools.append(contentsOf: AppleRoutedPersistentAgentTools.makeTools())
        }
      }
    }

    let session = LanguageModelSession(model: model, tools: tools) {
      instructions
    }

    let prompt: String
    if selection.focused != nil {
      prompt = Self.latestUserPrompt(messages: messages)
    } else {
      prompt = Self.makePrompt(messages: messages)
        + "\n\nAUTHORITATIVE RUNTIME CONTEXT FOR THIS TURN:\n"
        + temporalContext
    }

    let bridgeCapabilityScopeToken: UUID?
    if let capabilityScope {
      bridgeCapabilityScopeToken = await AgentToolExecutionBridge.shared
        .pushCapabilityScope(capabilityScope)
    } else {
      bridgeCapabilityScopeToken = nil
    }

    let clock = ContinuousClock()
    let startedAt = clock.now

    do {
      let responseContent: String
      #if compiler(>=6.4)
      if #available(macOS 27.0, *), Self.requiresToolCall(selection) {
        // Xcode 27 adds explicit required tool-calling mode. Keep this stronger
        // contract on current systems while allowing the Xcode 26 native CI
        // baseline to compile the same source without referencing a newer API.
        let response = try await session.respond(
          to: prompt,
          options: GenerationOptions(toolCallingMode: .required)
        )
        responseContent = response.content
      } else {
        let response = try await session.respond(to: prompt)
        responseContent = response.content
      }
      #else
      let response = try await session.respond(to: prompt)
      responseContent = response.content
      #endif

      if let bridgeCapabilityScopeToken {
        await AgentToolExecutionBridge.shared.popCapabilityScope(
          bridgeCapabilityScopeToken
        )
      }

      let duration = startedAt.duration(to: clock.now)
      return ProviderStreamEvent(
        contentDelta: responseContent,
        thinkingDelta: "",
        isFinished: true,
        metrics: ChatMetrics(
          totalDurationNanoseconds: Self.nanoseconds(from: duration)
        )
      )
    } catch {
      if Self.requiresToolCall(selection),
        let toolOutput = AppleRequiredDocumentTools.completionOutput(from: error)
      {
        if let bridgeCapabilityScopeToken {
          await AgentToolExecutionBridge.shared.popCapabilityScope(
            bridgeCapabilityScopeToken
          )
        }
        let duration = startedAt.duration(to: clock.now)
        return ProviderStreamEvent(
          contentDelta: toolOutput,
          thinkingDelta: "",
          isFinished: true,
          metrics: ChatMetrics(
            totalDurationNanoseconds: Self.nanoseconds(from: duration)
          )
        )
      }

      if let bridgeCapabilityScopeToken {
        await AgentToolExecutionBridge.shared.popCapabilityScope(
          bridgeCapabilityScopeToken
        )
      }
      throw error
    }
  }
  #else
  public func complete(
    configuration: AppConfiguration,
    messages: [ProviderMessage]
  ) async throws -> ProviderStreamEvent {
    throw AppleFoundationModelsProviderError.unsupportedPlatform
  }
  #endif

  private static func isAllowed(
    _ capability: AgentToolCapability,
    in scope: Set<AgentToolCapability>?
  ) -> Bool {
    scope?.contains(capability) ?? true
  }

  private static func requiresToolCall(
    _ selection: AppleFoundationModelToolSelection
  ) -> Bool {
    selection.focused != nil
  }

  private static func makeInstructions(
    messages: [ProviderMessage],
    temporalContext: String,
    selection: AppleFoundationModelToolSelection
  ) -> String {
    let system = messages.first(where: { $0.role == .system })?.content ?? ""
    let routeInstruction: String
    if let focused = selection.focused {
      switch focused {
      case .document:
        routeInstruction = "Use the provided document generation tool to create the requested file. Do not claim creation unless the tool succeeds."
      case .clipboard:
        routeInstruction = "Use the provided clipboard tool before answering. Do not guess clipboard contents."
      case .calendarCreate:
        routeInstruction = "Use the provided calendar creation tool for the requested mutation. Do not claim creation unless the tool succeeds."
      }
    } else {
      routeInstruction = "Use an available tool when the current request requires real external/local data or an action. Never invent tool output."
    }

    return [
      system,
      AgentRuntimeContext.providerInstruction(),
      temporalContext,
      routeInstruction,
    ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: "\n\n")
  }

  private static func latestUserPrompt(
    messages: [ProviderMessage]
  ) -> String {
    messages.last(where: { $0.role == .user })?.content
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private static func makePrompt(
    messages: [ProviderMessage]
  ) -> String {
    messages.compactMap { message -> String? in
      guard message.role != .system else { return nil }
      let label: String
      switch message.role {
      case .system: label = "System"
      case .user: label = "User"
      case .assistant: label = "Assistant"
      case .tool: label = "Tool"
      }
      return "\(label): \(message.content)"
    }.joined(separator: "\n\n")
  }

  private static func nanoseconds(
    from duration: Duration
  ) -> UInt64 {
    let components = duration.components
    let seconds = max(Int64.zero, components.seconds)
    let attoseconds = max(Int64.zero, components.attoseconds)
    let secondNanos = UInt64(seconds) * 1_000_000_000
    let fractionalNanos = UInt64(attoseconds / 1_000_000_000)
    return secondNanos + fractionalNanos
  }
}
