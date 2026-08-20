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
    peers: [AgentMeshPeerRecord]
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

    if routingConfiguration.privacyLockEnabled, personal {
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
      if routingConfiguration.allowAppleOnDevice, appleFoundationModelsAvailable {
        return HybridRouteDecision(
          kind: .appleOnDevice,
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
        reason: "Privacy Lock verhindert eine automatische Remote-Ausführung für persönliche macOS-Daten. Wähle einen lokalen Provider/Runtime-Pfad oder aktiviere Apple On-Device.",
        confidence: 1,
        privacyLocked: true,
        requiredCapabilities: requiredCapabilities
      )
    }

    if Self.explicitAppleIntent(normalizedPrompt),
      routingConfiguration.allowAppleOnDevice,
      appleFoundationModelsAvailable
    {
      return HybridRouteDecision(
        kind: .appleOnDevice,
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
        : "Der Prompt benötigt eine Capability, die Build 40/41 nicht automatisch an Remote-Peers delegiert."
      return decisionForActiveProvider(
        configuration: activeConfiguration,
        operatingConfiguration: operatingConfiguration,
        reason: "Mesh-Fallback auf den aktiven Provider: \(detail)",
        confidence: 0.88,
        requiredCapabilities: requiredCapabilities
      )
    }

    if routingConfiguration.preferLocal, activeIsLocal {
      return decisionForActiveProvider(
        configuration: activeConfiguration,
        operatingConfiguration: operatingConfiguration,
        reason: "Local-first Policy: der aktive Provider/Runtime-Pfad ist lokal und es gibt keine explizite Remote-Absicht.",
        confidence: 0.92,
        requiredCapabilities: requiredCapabilities
      )
    }

    if routingConfiguration.preferLocal,
      routingConfiguration.allowAppleOnDevice,
      appleFoundationModelsAvailable,
      activeConfiguration.providerKind == .ollamaCloud,
      !Self.explicitCloudIntent(normalizedPrompt)
    {
      return HybridRouteDecision(
        kind: .appleOnDevice,
        targetName: "Apple On-Device",
        reason: "Local-first Policy: der aktive Provider ist Cloud; ohne explizite Cloud-Absicht wird Apple On-Device bevorzugt.",
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
    if containsAny(text, ["ssh", "scp", "remote host", "remote server"]), !explicitMeshIntent(text) {
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
    if containsAny(text, ["http", "https", "rest api", "webhook"]), !explicitMeshIntent(text) {
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
