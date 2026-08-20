import Foundation

@MainActor
extension AppState {
  /// Build 41 chat entry point. Manual mode is intentionally identical to the
  /// legacy send path. Adaptive mode may select Apple On-Device or a trusted
  /// Agent Mesh peer, but never creates a second local tool/security router.
  public func sendMessageHybridAware() {
    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, generationPhase.acceptsNewTurn, !isGenerating else {
      return
    }

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
          de: "Build 41 delegiert Chat-Anhänge noch nicht automatisch an Agent-Mesh-Peers. Entferne die Anhänge oder verwende den lokalen Provider.",
          en: "Build 41 does not automatically delegate chat attachments to Agent Mesh peers yet. Remove the attachments or use the local provider.",
          fr: "Le Build 41 ne délègue pas encore automatiquement les pièces jointes aux pairs Agent Mesh. Retirez les pièces jointes ou utilisez le fournisseur local."
        )
        return
      }
      guard let peerID = decision.peerID else {
        errorMessage = HybridRoutingError.peerUnavailable.localizedDescription
        return
      }

      let turnID = UUID()
      guard beginManagedGeneration(turnID: turnID) else { return }

      inputText = ""
      latestMetrics = nil

      let task = Task { @MainActor [weak self] in
        guard let self else { return }
        await self.performHybridMeshSend(
          text: text,
          decision: decision,
          peerID: peerID,
          timeoutSeconds: operatingConfiguration.requestTimeoutSeconds,
          turnID: turnID
        )
      }
      installManagedGenerationTask(task, turnID: turnID)

    case .blocked:
      errorMessage = decision.reason
    }
  }

  private func sendViaTemporaryAppleRoute() {
    // Hybrid Apple is already an automatic local runtime decision even while
    // Phase-2 ModelProfile routing remains disabled. Apply the same fail-closed
    // thermal/memory/swap admission boundary before switching this single turn.
    let snapshot = AutomaticSystemResourceSampler.capture()
    do {
      try AutomaticInferenceAdmissionGate.validate(
        profile: ModelProfileCatalog.appleBuiltIn,
        snapshot: snapshot
      )
    } catch {
      errorMessage = error.localizedDescription
      return
    }

    // Capture the current user configuration by value and derive an Apple route
    // inside TurnExecutionPlan. AppConfiguration remains untouched and therefore
    // requires no polling restore task after generation.
    sendMessage(using: configuration, origin: .hybridAppleOnDevice)
  }

  private func performHybridMeshSend(
    text: String,
    decision: HybridRouteDecision,
    peerID: UUID,
    timeoutSeconds: Int,
    turnID: UUID
  ) async {
    defer { finishManagedGeneration(turnID: turnID) }

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
    var activePeer: AgentMeshPeerRecord?

    do {
      try Task.checkCancellation()
      guard generationPhase.turnID == turnID else {
        throw CancellationError()
      }

      guard let peer = try await AgentMeshPeerStore.shared.trustedPeer(id: peerID),
        peer.status == .trusted
      else {
        throw HybridRoutingError.peerUnavailable
      }
      activePeer = peer

      try Task.checkCancellation()
      _ = try await client.submit(request, to: peer)
      try Task.checkCancellation()

      for try await event in client.follow(taskID: request.id, peer: peer) {
        try Task.checkCancellation()
        guard generationPhase.turnID == turnID else {
          throw CancellationError()
        }
        applyHybridMeshEvent(event, assistantID: assistantID)
      }

      try Task.checkCancellation()
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
    } catch {
      if Task.isCancelled || error is CancellationError {
        if let activePeer {
          _ = try? await client.cancel(taskID: request.id, peer: activePeer)
        }
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
        return
      }

      if let index = messages.firstIndex(where: { $0.id == assistantID }),
        messages[index].content.isEmpty
      {
        messages[index].content = "Fehler: \(error.localizedDescription)"
      }
      errorMessage = error.localizedDescription
      try? await persistHybridConversation()
    }
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
