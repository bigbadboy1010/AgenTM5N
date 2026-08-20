import Foundation

@MainActor
public final class HybridRoutingController: ObservableObject {
  public static let shared = HybridRoutingController()

  @Published public var configuration: HybridRoutingConfiguration
  @Published public var previewPrompt = ""
  @Published public private(set) var decision: HybridRouteDecision?
  @Published public private(set) var peers: [AgentMeshPeerRecord] = []
  @Published public private(set) var appleAvailability = "Wird geprüft"
  @Published public private(set) var statusMessage = "Hybrid Router bereit"

  private let router: HybridInferenceRouter
  private let peerStore: AgentMeshPeerStore
  private let appleProvider: AppleFoundationModelsProvider

  public init(
    router: HybridInferenceRouter = HybridInferenceRouter(),
    peerStore: AgentMeshPeerStore = .shared,
    appleProvider: AppleFoundationModelsProvider = AppleFoundationModelsProvider()
  ) {
    self.router = router
    self.peerStore = peerStore
    self.appleProvider = appleProvider
    configuration = HybridRoutingStore.loadConfiguration()
    decision = HybridRoutingStore.loadSnapshot().lastDecision
  }

  public func bootstrap() async {
    await refreshEnvironment()
  }

  public func refreshEnvironment() async {
    do {
      peers = try await peerStore.all()
    } catch {
      peers = []
      statusMessage = error.localizedDescription
    }
    appleAvailability = await appleProvider.availabilityDescription()
  }

  public func save() {
    do {
      try HybridRoutingStore.saveConfiguration(configuration)
      statusMessage = configuration.mode == .adaptive
        ? "Adaptive Hybrid Routing gespeichert."
        : "Manual Routing gespeichert. Bestehendes Provider-Verhalten bleibt unverändert."
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  @discardableResult
  public func preview(
    appConfiguration: AppConfiguration,
    operatingConfiguration: AgentOperatingLayerConfiguration
  ) -> HybridRouteDecision {
    let value = router.decide(
      prompt: previewPrompt,
      activeConfiguration: appConfiguration,
      operatingConfiguration: operatingConfiguration,
      routingConfiguration: configuration,
      appleFoundationModelsAvailable: appleIsAvailable,
      peers: peers
    )
    decision = value
    HybridRoutingStore.saveDecision(value)
    statusMessage = "Route: \(value.targetName)"
    return value
  }

  public func preview(
    prompt: String,
    appConfiguration: AppConfiguration,
    operatingConfiguration: AgentOperatingLayerConfiguration
  ) -> HybridRouteDecision {
    previewPrompt = prompt
    return preview(
      appConfiguration: appConfiguration,
      operatingConfiguration: operatingConfiguration
    )
  }

  public var trustedPeers: [AgentMeshPeerRecord] {
    peers.filter { $0.status == .trusted }
  }

  public var appleIsAvailable: Bool {
    let value = appleAvailability.lowercased()
    if value.contains("nicht verfügbar")
      || value.contains("unavailable")
      || value.contains("indisponible")
    {
      return false
    }
    return value.contains("verfügbar")
      || value.contains("available")
      || value.contains("disponible")
  }
}
