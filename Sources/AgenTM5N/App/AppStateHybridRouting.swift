import Foundation

private struct HybridTemporaryAppRoute: Equatable {
  let providerKind: ProviderKind
  let baseURL: String
  let model: String
  let apiKeySecretID: UUID?

  init(_ configuration: AppConfiguration) {
    providerKind = configuration.providerKind
    baseURL = configuration.baseURL
    model = configuration.model
    apiKeySecretID = configuration.apiKeySecretID
  }

  func matches(_ configuration: AppConfiguration) -> Bool {
    providerKind == configuration.providerKind
      && baseURL == configuration.baseURL
      && model == configuration.model
      && apiKeySecretID == configuration.apiKeySecretID
  }
}

@MainActor
extension AppState {
  /// Build 42 chat entry point. Manual mode is intentionally identical to the
  /// legacy send path. Adaptive mode may select a validated Model Manager
  /// profile, Apple On-Device, or a trusted Agent Mesh peer. All local/cloud
  /// model routes still enter the existing AppState provider/tool/security path.
  public func sendMessageHybridAware() {
    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !isGenerating else { return }

    let operatingConfiguration = AgentOperatingLayerStore.load()
    let controller = HybridRoutingController.shared
    let decision = controller.preview(
      prompt: text,
      appConfiguration: configuration,
      operatingConfiguration: operatingConfiguration
    )

    switch decision.kind {
    case .activeProvider:
      sendMessage()

    case .modelProfile:
      guard let profileID = decision.profileID,
        let profile = controller.profile(id: profileID)
      else {
        errorMessage = HybridRoutingError.profileUnavailable.localizedDescription
        return
      }
      guard profile.runtime != .appleFoundationModels else {
        errorMessage = HybridRoutingError.profileUnavailable.localizedDescription
        return
      }
      guard profile.runtime != .ollamaCloud || profile.apiKeySecretID != nil else {
        errorMessage = ModelProfileError.missingCloudSecretReference.localizedDescription
        return
      }
      sendViaTemporaryModelProfile(
        profile,
        operatingConfiguration: operatingConfiguration
      )

    case .appleOnDevice:
      guard !PromptAttachmentService.hasImageAttachments(in: text) else {
        // Apple Foundation Models in AgenTM5N is currently text-only. Keep the
        // existing provider so image prompts are never silently dropped.
        let fallback = HybridRouteDecision(
          kind: .activeProvider,
          targetName: "Current provider",
          reason: "Hybrid Router fallback: Apple On-Device is text-only for the current AgenTM5N attachment path.",
          confidence: 1,
          privacyLocked: decision.privacyLocked,
          requiredCapabilities: decision.requiredCapabilities
        )
        HybridRoutingStore.saveDecision(fallback)
        sendMessage()
        return
      }
      sendViaTemporaryAppleRoute()

    case .meshPeer:
      guard PromptAttachmentService.imageReferences(from: text).isEmpty,
        PromptAttachmentService.textAttachmentNames(from: text).isEmpty
      else {
        errorMessage = L10n.text(
          de: "Build 42 delegiert Chat-Anhänge noch nicht automatisch an Agent-Mesh-Peers. Entferne die Anhänge oder verwende einen lokalen Modellpfad.",
          en: "Build 42 does not automatically delegate chat attachments to Agent Mesh peers yet. Remove the attachments or use a local model route.",
          fr: "Le Build 42 ne délègue pas encore automatiquement les pièces jointes aux pairs Agent Mesh. Retirez les pièces jointes ou utilisez un modèle local."
        )
        return
      }
      guard let peerID = decision.peerID else {
        errorMessage = HybridRoutingError.peerUnavailable.localizedDescription
        return
      }
      inputText = ""
      isGenerating = true
      latestMetrics = nil
      Task { @MainActor [weak self] in
        await self?.performHybridMeshSend(
          text: text,
          decision: decision,
          peerID: peerID,
          timeoutSeconds: operatingConfiguration.requestTimeoutSeconds
        )
      }

    case .blocked:
      errorMessage = decision.reason
    }
  }

  private func sendViaTemporaryModelProfile(
    _ profile: ModelProfile,
    operatingConfiguration: AgentOperatingLayerConfiguration
  ) {
    let originalRoute = HybridTemporaryAppRoute(configuration)
    let plan = profile.activationPlan

    configuration.providerKind = plan.providerKind
    configuration.baseURL = plan.baseURL
    configuration.model = plan.model
    configuration.apiKeySecretID = plan.apiKeySecretID
    let appliedRoute = HybridTemporaryAppRoute(configuration)

    var runtimeOverride = operatingConfiguration
    runtimeOverride.localInferenceRuntime = plan.localInferenceRuntime ?? .ollama
    runtimeOverride.numContext = plan.contextWindow
    runtimeOverride.normalize()

    // Free ANEMLL memory when this turn intentionally selects another runtime.
    // The persistent runtime restarts lazily on the next ANEMLL turn.
    if operatingConfiguration.localInferenceRuntime == .anemll,
      profile.runtime != .anemll
    {
      Task {
        await ANEMLLPersistentRuntimeService.shared.shutdown()
      }
    }

    AgentOperatingLayerExecutionContext.$configurationOverride.withValue(
      runtimeOverride
    ) {
      sendMessage()
    }

    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.restoreTemporaryRoute(
        originalRoute,
        appliedRoute: appliedRoute
      )
    }
  }

  private func sendViaTemporaryAppleRoute() {
    let originalRoute = HybridTemporaryAppRoute(configuration)

    configuration.providerKind = .appleOnDevice
    configuration.baseURL = ProviderKind.appleOnDevice.defaultBaseURL
    configuration.model = "Apple System Language Model"
    configuration.apiKeySecretID = nil
    let appliedRoute = HybridTemporaryAppRoute(configuration)

    sendMessage()

    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.restoreTemporaryRoute(
        originalRoute,
        appliedRoute: appliedRoute
      )
    }
  }

  private func restoreTemporaryRoute(
    _ originalRoute: HybridTemporaryAppRoute,
    appliedRoute: HybridTemporaryAppRoute
  ) async {
    // sendMessage() schedules generation asynchronously. Do not restore the
    // provider before performSend has actually entered its generation phase.
    var observedGeneration = isGenerating
    for _ in 0..<100 where !observedGeneration {
      try? await Task.sleep(for: .milliseconds(10))
      observedGeneration = isGenerating
    }

    while isGenerating {
      try? await Task.sleep(for: .milliseconds(75))
    }

    // Restore only if the temporary route is still present. A deliberate UI
    // provider change made by the user while generation was running wins.
    guard appliedRoute.matches(configuration) else { return }

    configuration.providerKind = originalRoute.providerKind
    configuration.baseURL = originalRoute.baseURL
    configuration.model = originalRoute.model
    configuration.apiKeySecretID = originalRoute.apiKeySecretID
  }

  private func performHybridMeshSend(
    text: String,
    decision: HybridRouteDecision,
    peerID: UUID,
    timeoutSeconds: Int
  ) async {
    let userMessage = ChatMessage(role: .user, content: text)
    let assistantID = UUID()
    messages.append(userMessage)
    messages.append(
      ChatMessage(
        id: assistantID,
        role: .assistant,
        content: "",
        thinking: "Hybrid Route: \(decision.targetName)\n\(decision.reason)"
      )
    )

    let client = AgentMeshClient()
    let request = AgentMeshTaskRequest(
      prompt: PromptAttachmentService.providerPrompt(from: text),
      requestedCapabilities: decision.requiredCapabilities,
      timeoutSeconds: timeoutSeconds
    )

    do {
      guard let peer = try await AgentMeshPeerStore.shared.trustedPeer(id: peerID),
        peer.status == .trusted
      else {
        throw HybridRoutingError.peerUnavailable
      }

      _ = try await client.submit(request, to: peer)

      let cancellationWatcher = Task.detached { [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(125))
          let stillGenerating = await MainActor.run { self?.isGenerating ?? false }
          if !stillGenerating {
            _ = try? await client.cancel(taskID: request.id, peer: peer)
            return
          }
        }
      }
      defer { cancellationWatcher.cancel() }

      for try await event in client.follow(taskID: request.id, peer: peer) {
        if !isGenerating {
          _ = try? await client.cancel(taskID: request.id, peer: peer)
          throw CancellationError()
        }
        applyHybridMeshEvent(event, assistantID: assistantID)
      }

      let snapshot = try await client.snapshot(taskID: request.id, peer: peer)
      switch snapshot.status {
      case .completed:
        if let result = snapshot.result, !result.isEmpty,
          let index = messages.firstIndex(where: { $0.id == assistantID })
        {
          // The completed snapshot is canonical and avoids duplicate content if
          // an event consumer reconnects or receives a retried delta batch.
          messages[index].content = result
        }
      case .cancelled:
        throw CancellationError()
      case .failed:
        throw HybridRoutingError.blocked(
          snapshot.error ?? L10n.text(
            de: "Der Remote-Agent hat den Task nicht erfolgreich abgeschlossen.",
            en: "The remote agent did not complete the task successfully.",
            fr: "L’agent distant n’a pas terminé la tâche avec succès."
          )
        )
      case .queued, .running, .waitingForApproval:
        throw HybridRoutingError.blocked(
          L10n.text(
            de: "Der Remote-Task endete ohne terminalen Status.",
            en: "The remote task ended without a terminal status.",
            fr: "La tâche distante s’est terminée sans état terminal."
          )
        )
      }

      try await persistHybridConversation()
    } catch is CancellationError {
      if let index = messages.firstIndex(where: { $0.id == assistantID }),
        messages[index].content.isEmpty
      {
        messages[index].content = L10n.text(
          de: "Abgebrochen.",
          en: "Cancelled.",
          fr: "Annulé."
        )
      }
      try? await persistHybridConversation()
    } catch {
      if let index = messages.firstIndex(where: { $0.id == assistantID }),
        messages[index].content.isEmpty
      {
        messages[index].content = "Fehler: \(error.localizedDescription)"
      }
      errorMessage = error.localizedDescription
      try? await persistHybridConversation()
    }

    isGenerating = false
  }

  private func applyHybridMeshEvent(
    _ event: AgentMeshTaskEvent,
    assistantID: UUID
  ) {
    guard let index = messages.firstIndex(where: { $0.id == assistantID }) else {
      return
    }

    switch event.kind {
    case .delta:
      messages[index].content += event.message
    case .thinking:
      if !event.message.isEmpty {
        messages[index].thinking += "\n\(event.message)"
      }
    case .approvalRequired:
      messages[index].thinking += "\nRemote node: local approval required."
    case .toolRequested:
      messages[index].thinking += "\nRemote node requested a tool."
    case .toolDenied:
      messages[index].thinking += "\nRemote node denied a tool request."
    case .toolCompleted:
      messages[index].thinking += "\nRemote node completed a tool request."
    case .accepted, .started, .completed, .failed, .cancelled:
      break
    }
  }

  private func persistHybridConversation() async throws {
    let store = JSONDocumentStore<[ChatMessage]>(
      url: AppPaths.conversationFile,
      defaultValue: []
    )
    try await store.save(messages)
  }
}
