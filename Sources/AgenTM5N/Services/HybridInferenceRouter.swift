import Foundation

public enum HybridRoutingStore {
  private static var configurationURL: URL {
    AppPaths.applicationSupportDirectory
      .appendingPathComponent("hybrid-routing.json", isDirectory: false)
  }

  private static var snapshotURL: URL {
    AppPaths.applicationSupportDirectory
      .appendingPathComponent("hybrid-routing-last-decision.json", isDirectory: false)
  }

  public static func loadConfiguration() -> HybridRoutingConfiguration {
    do {
      guard FileManager.default.fileExists(atPath: configurationURL.path) else {
        return .default
      }
      let data = try Data(contentsOf: configurationURL, options: [.mappedIfSafe])
      var value = try JSONDecoder().decode(HybridRoutingConfiguration.self, from: data)
      value.normalize()
      return value
    } catch {
      AppLogger.app.error(
        "Hybrid routing configuration load failed: \(error.localizedDescription, privacy: .public)"
      )
      return .default
    }
  }

  public static func saveConfiguration(_ configuration: HybridRoutingConfiguration) throws {
    var normalized = configuration
    normalized.normalize()
    let directory = configurationURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directory.path
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(normalized)
    try data.write(to: configurationURL, options: [.atomic])
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: configurationURL.path
    )
  }

  public static func loadSnapshot() -> HybridRoutingSnapshot {
    do {
      guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
        return HybridRoutingSnapshot()
      }
      let data = try Data(contentsOf: snapshotURL, options: [.mappedIfSafe])
      return try JSONDecoder().decode(HybridRoutingSnapshot.self, from: data)
    } catch {
      return HybridRoutingSnapshot()
    }
  }

  public static func saveDecision(_ decision: HybridRouteDecision) {
    do {
      let directory = snapshotURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(HybridRoutingSnapshot(lastDecision: decision))
      try data.write(to: snapshotURL, options: [.atomic])
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: snapshotURL.path
      )
    } catch {
      AppLogger.app.error(
        "Hybrid routing snapshot save failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}

public struct HybridInferenceRouter: Sendable {
  public init() {}

  public func decide(
    prompt: String,
    activeConfiguration: AppConfiguration,
    operatingConfiguration: AgentOperatingLayerConfiguration,
    routingConfiguration: HybridRoutingConfiguration,
    appleFoundationModelsAvailable: Bool,
    peers: [AgentMeshPeerRecord],
    modelProfiles: [ModelProfile] = [],
    hasImageInput: Bool = false
  ) -> HybridRouteDecision {
    let normalizedPrompt = prompt.lowercased()
    let requiredCapabilities = Self.requiredCapabilities(for: normalizedPrompt)
    let activeIsLocal = activeConfiguration.providerKind != .ollamaCloud
    let personal = Self.containsAny(
      normalizedPrompt,
      [
        "kalender", "calendar", "termin", "kontakte", "kontakt", "contacts", "contact",
        "mail", "email", "e-mail", "reminder", "erinnerung", "zwischenablage", "clipboard",
        "meine nachricht", "my message", "meine daten", "personal data",
      ]
    )

    guard routingConfiguration.mode == .adaptive else {
      return decisionForActiveProvider(
        configuration: activeConfiguration,
        operatingConfiguration: operatingConfiguration,
        reason: "Hybrid Routing ist auf Manual gestellt; die aktive Provider-/Runtime-Konfiguration bleibt maßgeblich.",
        confidence: 1,
        requiredCapabilities: requiredCapabilities
      )
    }

    let eligibleProfiles = Self.eligibleProfiles(
      modelProfiles,
      requiredCapabilities: requiredCapabilities,
      routingConfiguration: routingConfiguration,
      appleFoundationModelsAvailable: appleFoundationModelsAvailable,
      hasImageInput: hasImageInput,
      localOnly: false
    )

    // Privacy Lock is evaluated before every cloud or Mesh route. Personal
    // macOS data may still use another validated local model profile, but it
    // can never be pushed to a remote model merely because that profile has a
    // higher priority.
    if routingConfiguration.privacyLockEnabled, personal {
      let localProfiles = Self.eligibleProfiles(
        modelProfiles,
        requiredCapabilities: requiredCapabilities,
        routingConfiguration: routingConfiguration,
        appleFoundationModelsAvailable: appleFoundationModelsAvailable,
        hasImageInput: hasImageInput,
        localOnly: true
      )

      if let selected = Self.profileCandidate(
        prompt: normalizedPrompt,
        candidates: localProfiles,
        activeConfiguration: activeConfiguration,
        operatingConfiguration: operatingConfiguration,
        preferLocal: true,
        activeIsLocal: activeIsLocal
      ) {
        return decisionForProfile(
          selected,
          activeConfiguration: activeConfiguration,
          operatingConfiguration: operatingConfiguration,
          reason: "Privacy Lock: persönlicher Turn bleibt auf dem lokalen Modellprofil \(selected.name).",
          confidence: 0.98,
          privacyLocked: true,
          requiredCapabilities: requiredCapabilities
        )
      }

      if activeIsLocal {
        return decisionForActiveProvider(
          configuration: activeConfiguration,
          operatingConfiguration: operatingConfiguration,
          reason: "Privacy Lock: persönliche macOS-Daten bleiben auf dem aktuell lokalen Provider/Runtime-Pfad.",
          confidence: 1,
          privacyLocked: true,
          requiredCapabilities: requiredCapabilities
        )
      }

      // Backward-compatible fallback for installations that have not loaded a
      // Model Manager document yet. With Build 42 profiles loaded, the built-in
      // Apple profile is handled by localProfiles above.
      if modelProfiles.isEmpty,
        routingConfiguration.allowAppleOnDevice,
        appleFoundationModelsAvailable,
        !hasImageInput
      {
        return HybridRouteDecision(
          kind: .appleOnDevice,
          profileID: ModelProfileCatalog.appleBuiltIn.id,
          profileRuntime: .appleFoundationModels,
          targetName: "Apple On-Device",
          reason: "Privacy Lock: der aktive Provider ist remote; Apple Foundation Models ist als lokaler Ersatz verfügbar.",
          confidence: 1,
          privacyLocked: true,
          requiredCapabilities: requiredCapabilities
        )
      }

      return HybridRouteDecision(
        kind: .blocked,
        targetName: "Blocked by Privacy Lock",
        reason: "Privacy Lock verhindert eine automatische Remote-Ausführung für persönliche macOS-Daten. Es ist kein kompatibles lokales Modellprofil verfügbar.",
        confidence: 1,
        privacyLocked: true,
        requiredCapabilities: requiredCapabilities
      )
    }

    if Self.explicitAppleIntent(normalizedPrompt),
      routingConfiguration.allowAppleOnDevice,
      appleFoundationModelsAvailable,
      !hasImageInput
    {
      return HybridRouteDecision(
        kind: .appleOnDevice,
        profileID: ModelProfileCatalog.appleBuiltIn.id,
        profileRuntime: .appleFoundationModels,
        targetName: "Apple On-Device",
        reason: "Der Prompt fordert explizit Apple On-Device/Foundation Models an.",
        confidence: 0.99,
        requiredCapabilities: requiredCapabilities
      )
    }

    let meshIntent = Self.explicitMeshIntent(normalizedPrompt)
    if routingConfiguration.allowMesh,
      (!routingConfiguration.requireExplicitMeshIntent || meshIntent),
      Self.remoteCapabilitiesSupported(requiredCapabilities),
      let peer = Self.bestPeer(
        peers,
        requiredCapabilities: requiredCapabilities,
        limit: routingConfiguration.maximumMeshPeersConsidered
      )
    {
      return HybridRouteDecision(
        kind: .meshPeer,
        peerID: peer.id,
        targetName: "\(peer.kind == .agentNexus ? "AgentNexus" : "AgenTM5N") · \(peer.name)",
        reason: meshIntent
          ? "Explizite Delegations-/Mesh-Absicht; ein vertrauter Peer deckt den angeforderten Capability-Scope ab."
          : "Adaptive Mesh-Auswahl ist erlaubt und ein vertrauter Peer deckt den angeforderten Capability-Scope ab.",
        confidence: meshIntent ? 0.98 : 0.72,
        requiredCapabilities: requiredCapabilities
      )
    }

    if meshIntent, routingConfiguration.allowMesh {
      let detail = Self.remoteCapabilitiesSupported(requiredCapabilities)
        ? "Kein vertrauter Peer deckt den benötigten Capability-Scope ab."
        : "Der Prompt benötigt eine Capability, die Agent Mesh v1 nicht automatisch an Remote-Peers delegiert."
      return decisionForActiveProvider(
        configuration: activeConfiguration,
        operatingConfiguration: operatingConfiguration,
        reason: "Mesh-Fallback auf den aktiven Provider: \(detail)",
        confidence: 0.88,
        requiredCapabilities: requiredCapabilities
      )
    }

    if let explicitlyNamed = Self.explicitlyReferencedProfile(
      in: normalizedPrompt,
      candidates: eligibleProfiles
    ) {
      return decisionForProfile(
        explicitlyNamed,
        activeConfiguration: activeConfiguration,
        operatingConfiguration: operatingConfiguration,
        reason: "Der Prompt nennt das Modellprofil bzw. Modellziel explizit.",
        confidence: 0.99,
        requiredCapabilities: requiredCapabilities
      )
    }

    if Self.explicitCloudIntent(normalizedPrompt) {
      if let cloud = eligibleProfiles.first(where: { $0.runtime == .ollamaCloud }) {
        return decisionForProfile(
          cloud,
          activeConfiguration: activeConfiguration,
          operatingConfiguration: operatingConfiguration,
          reason: "Der Prompt fordert explizit einen Cloud-Modellpfad an; das höchste kompatible Cloud-Profil wurde gewählt.",
          confidence: 0.97,
          requiredCapabilities: requiredCapabilities
        )
      }
      return decisionForActiveProvider(
        configuration: activeConfiguration,
        operatingConfiguration: operatingConfiguration,
        reason: "Expliziter Cloud-Wunsch, aber kein aktiviertes kompatibles Cloud-Modellprofil mit Vault-Secret-Referenz ist verfügbar.",
        confidence: 0.9,
        requiredCapabilities: requiredCapabilities
      )
    }

    if let selected = Self.profileCandidate(
      prompt: normalizedPrompt,
      candidates: eligibleProfiles,
      activeConfiguration: activeConfiguration,
      operatingConfiguration: operatingConfiguration,
      preferLocal: routingConfiguration.preferLocal,
      activeIsLocal: activeIsLocal
    ) {
      return decisionForProfile(
        selected,
        activeConfiguration: activeConfiguration,
        operatingConfiguration: operatingConfiguration,
        reason: routingConfiguration.preferLocal
          ? "Build 42 Profile Router: Local-first und Profilpriorität wählen \(selected.name)."
          : "Build 42 Profile Router: Profilpriorität wählt \(selected.name).",
        confidence: 0.9,
        requiredCapabilities: requiredCapabilities
      )
    }

    if routingConfiguration.preferLocal, activeIsLocal {
      return decisionForActiveProvider(
        configuration: activeConfiguration,
        operatingConfiguration: operatingConfiguration,
        reason: "Local-first Policy: der aktive Provider/Runtime-Pfad ist lokal und kein höher priorisiertes kompatibles lokales Modellprofil greift.",
        confidence: 0.92,
        requiredCapabilities: requiredCapabilities
      )
    }

    if routingConfiguration.preferLocal,
      routingConfiguration.allowAppleOnDevice,
      appleFoundationModelsAvailable,
      activeConfiguration.providerKind == .ollamaCloud,
      !Self.explicitCloudIntent(normalizedPrompt),
      !hasImageInput
    {
      return HybridRouteDecision(
        kind: .appleOnDevice,
        profileID: ModelProfileCatalog.appleBuiltIn.id,
        profileRuntime: .appleFoundationModels,
        targetName: "Apple On-Device",
        reason: "Local-first Policy: der aktive Provider ist Cloud; ohne kompatibles geladenes Profil wird Apple On-Device bevorzugt.",
        confidence: 0.82,
        requiredCapabilities: requiredCapabilities
      )
    }

    return decisionForActiveProvider(
      configuration: activeConfiguration,
      operatingConfiguration: operatingConfiguration,
      reason: "Keine stärkere Routing-Regel greift; der aktive Provider/Runtime-Pfad bleibt erhalten.",
      confidence: 0.8,
      requiredCapabilities: requiredCapabilities
    )
  }

  public static func requiredCapabilities(for prompt: String) -> Set<AgentToolCapability> {
    let text = prompt.lowercased()
    var capabilities: Set<AgentToolCapability> = []

    if containsAny(text, ["datei", "file", "ordner", "folder", "workspace", "source", "code"]) {
      capabilities.insert(.workspace)
    }
    if containsAny(text, ["git", "commit", "branch", "merge", "rebase", "diff", "repository", "repo"]) {
      capabilities.formUnion([.workspace, .git])
    }
    if containsAny(text, ["terminal", "shell", "befehl", "command", "docker", "container", "compose", "systemctl", "journalctl"]) {
      capabilities.formUnion([.terminal, .system])
    }
    if containsAny(text, ["ssh", "scp", "remote host", "remote server"]) {
      capabilities.insert(.ssh)
    }
    if containsAny(text, ["kalender", "calendar", "termin", "kontakte", "kontakt", "contacts", "contact", "mail", "email", "e-mail"]) {
      capabilities.insert(.macPersonal)
    }
    if containsAny(text, ["reminder", "erinnerung", "erinnerungen"]) {
      capabilities.insert(.reminders)
    }
    if containsAny(text, ["coreml", "core ml", "neural engine", "ane", "embedding"]) {
      capabilities.insert(.coreML)
    }
    if containsAny(text, ["pdf", "docx", "xlsx", "pptx", "dokument", "document"]) {
      capabilities.formUnion([.documents, .attachments])
    }
    if containsAny(text, ["http", "https", "rest api", "webhook"]) {
      capabilities.insert(.http)
    }
    if containsAny(text, ["secret", "passwort", "password", "token", "api key", "apikey"]) {
      capabilities.insert(.secrets)
    }
    if containsAny(text, ["edge", "kubernetes", "kubectl", "openshift", "podman"]) {
      capabilities.insert(.edge)
    }
    if containsAny(text, ["agent delegieren", "delegate agent", "subagent", "workflow"]) {
      capabilities.formUnion([.agents, .workflows])
    }

    return capabilities
  }

  public static func explicitMeshIntent(_ prompt: String) -> Bool {
    containsAny(
      prompt.lowercased(),
      [
        "agent mesh", "mesh peer", "anderer agent", "anderen agent", "anderer mac", "anderen mac",
        "remote agent", "remote agen", "agentnexus", "delegiere an einen peer", "delegate to a peer",
        "delegate to another agent", "auf einem anderen mac", "on another mac",
      ]
    )
  }

  private func decisionForActiveProvider(
    configuration: AppConfiguration,
    operatingConfiguration: AgentOperatingLayerConfiguration,
    reason: String,
    confidence: Double,
    privacyLocked: Bool = false,
    requiredCapabilities: Set<AgentToolCapability>
  ) -> HybridRouteDecision {
    HybridRouteDecision(
      kind: .activeProvider,
      targetName: Self.activeProviderName(
        configuration: configuration,
        operatingConfiguration: operatingConfiguration
      ),
      reason: reason,
      confidence: confidence,
      privacyLocked: privacyLocked,
      requiredCapabilities: requiredCapabilities
    )
  }

  private func decisionForProfile(
    _ profile: ModelProfile,
    activeConfiguration: AppConfiguration,
    operatingConfiguration: AgentOperatingLayerConfiguration,
    reason: String,
    confidence: Double,
    privacyLocked: Bool = false,
    requiredCapabilities: Set<AgentToolCapability>
  ) -> HybridRouteDecision {
    let matchesActive = Self.profileMatchesActive(
      profile,
      activeConfiguration: activeConfiguration,
      operatingConfiguration: operatingConfiguration
    )
    let kind: HybridRouteKind
    if matchesActive {
      kind = .activeProvider
    } else if profile.runtime == .appleFoundationModels {
      kind = .appleOnDevice
    } else {
      kind = .modelProfile
    }

    return HybridRouteDecision(
      kind: kind,
      profileID: profile.id,
      profileRuntime: profile.runtime,
      targetName: profile.name,
      reason: matchesActive
        ? reason + " Das Profil entspricht bereits dem aktiven Provider/Runtime-Pfad."
        : reason,
      confidence: confidence,
      privacyLocked: privacyLocked,
      requiredCapabilities: requiredCapabilities
    )
  }

  private static func eligibleProfiles(
    _ profiles: [ModelProfile],
    requiredCapabilities: Set<AgentToolCapability>,
    routingConfiguration: HybridRoutingConfiguration,
    appleFoundationModelsAvailable: Bool,
    hasImageInput: Bool,
    localOnly: Bool
  ) -> [ModelProfile] {
    let needsToolCalling = !requiredCapabilities.isEmpty
    return ModelProfileCatalog.routingCandidates(
      from: profiles,
      preferLocal: routingConfiguration.preferLocal || localOnly
    ).filter { profile in
      if localOnly, !profile.runtime.isLocal { return false }
      if profile.runtime == .ollamaCloud, profile.apiKeySecretID == nil { return false }
      if profile.runtime == .appleFoundationModels,
        (!routingConfiguration.allowAppleOnDevice || !appleFoundationModelsAvailable)
      {
        return false
      }
      if hasImageInput, !profile.capabilities.contains(.imageInput) { return false }
      if needsToolCalling, !profile.capabilities.contains(.toolCalling) { return false }
      return true
    }
  }

  private static func profileCandidate(
    prompt: String,
    candidates: [ModelProfile],
    activeConfiguration: AppConfiguration,
    operatingConfiguration: AgentOperatingLayerConfiguration,
    preferLocal: Bool,
    activeIsLocal: Bool
  ) -> ModelProfile? {
    guard !candidates.isEmpty else { return nil }

    if explicitLocalIntent(prompt), let local = candidates.first(where: { $0.runtime.isLocal }) {
      return local
    }

    let userProfiles = candidates.filter { $0.id != ModelProfileCatalog.appleBuiltIn.id }
    if preferLocal, activeIsLocal, !explicitCloudIntent(prompt) {
      let localUserProfiles = userProfiles.filter(\.runtime.isLocal)
      guard !localUserProfiles.isEmpty else {
        return nil
      }
      return localUserProfiles[0]
    }

    return candidates[0]
  }

  private static func explicitlyReferencedProfile(
    in prompt: String,
    candidates: [ModelProfile]
  ) -> ModelProfile? {
    candidates.first { profile in
      let name = profile.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
      let model = profile.modelIdentifier.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
      return (name.count >= 4 && prompt.contains(name))
        || (model.count >= 4 && prompt.contains(model))
    }
  }

  private static func profileMatchesActive(
    _ profile: ModelProfile,
    activeConfiguration: AppConfiguration,
    operatingConfiguration: AgentOperatingLayerConfiguration
  ) -> Bool {
    let plan = profile.activationPlan
    guard plan.providerKind == activeConfiguration.providerKind else { return false }
    if plan.providerKind == .appleOnDevice {
      return true
    }
    guard plan.model == activeConfiguration.model,
      normalizedURL(plan.baseURL) == normalizedURL(activeConfiguration.baseURL),
      plan.apiKeySecretID == activeConfiguration.apiKeySecretID
    else {
      return false
    }
    if let runtime = plan.localInferenceRuntime {
      return runtime == operatingConfiguration.localInferenceRuntime
    }
    return true
  }

  private static func normalizedURL(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      .lowercased()
  }

  private static func activeProviderName(
    configuration: AppConfiguration,
    operatingConfiguration: AgentOperatingLayerConfiguration
  ) -> String {
    switch configuration.providerKind {
    case .appleOnDevice:
      return "Apple On-Device"
    case .ollamaCloud:
      return "Ollama Cloud · \(configuration.model)"
    case .ollamaLocal:
      switch operatingConfiguration.localInferenceRuntime {
      case .ollama:
        return "Ollama Local · \(configuration.model)"
      case .mlxServer:
        return "MLX Local · \(configuration.model)"
      case .anemll:
        return "ANEMLL/Qwen3 · \(configuration.model)"
      }
    }
  }

  private static func explicitAppleIntent(_ prompt: String) -> Bool {
    containsAny(
      prompt,
      ["apple on-device", "apple on device", "foundation models", "apple foundation", "system language model"]
    )
  }

  private static func explicitCloudIntent(_ prompt: String) -> Bool {
    containsAny(
      prompt,
      ["ollama cloud", "cloud model", "cloud-modell", "in der cloud", "use cloud", "remote model"]
    )
  }

  private static func explicitLocalIntent(_ prompt: String) -> Bool {
    containsAny(
      prompt,
      ["lokales modell", "lokaler provider", "local model", "local provider", "on-device model", "on device model"]
    )
  }

  private static func remoteCapabilitiesSupported(_ capabilities: Set<AgentToolCapability>) -> Bool {
    let blocked: Set<AgentToolCapability> = [
      .secrets,
      .http,
      .ssh,
      .edge,
      .agents,
      .workflows,
    ]
    return capabilities.isDisjoint(with: blocked)
  }

  private static func bestPeer(
    _ peers: [AgentMeshPeerRecord],
    requiredCapabilities: Set<AgentToolCapability>,
    limit: Int
  ) -> AgentMeshPeerRecord? {
    let trusted = peers
      .filter {
        $0.status == .trusted
          && $0.protocolVersion == AgentMeshProtocol.version
          && requiredCapabilities.isSubset(of: $0.allowedCapabilities)
      }
      .sorted { lhs, rhs in
        let leftSeen = lhs.lastSeenAt ?? .distantPast
        let rightSeen = rhs.lastSeenAt ?? .distantPast
        if leftSeen != rightSeen { return leftSeen > rightSeen }
        let leftName = lhs.name.lowercased()
        let rightName = rhs.name.lowercased()
        if leftName != rightName { return leftName < rightName }
        return lhs.id.uuidString < rhs.id.uuidString
      }
    return Array(trusted.prefix(max(1, limit))).first
  }

  private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
    needles.contains(where: { value.contains($0) })
  }
}
