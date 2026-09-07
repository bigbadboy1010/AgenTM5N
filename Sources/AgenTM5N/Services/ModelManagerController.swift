import Foundation

@MainActor
public final class ModelManagerController: ObservableObject {
  public static let shared = ModelManagerController()

  @Published public private(set) var profiles: [ModelProfile] = []
  @Published public private(set) var activeProfileID: UUID?
  @Published public private(set) var statusMessage = "Model Manager bereit"

  private let store: ModelProfileStore
  private let ollamaDiscovery: OllamaModelDiscoveryService

  public init(
    store: ModelProfileStore = .shared,
    ollamaDiscovery: OllamaModelDiscoveryService = OllamaModelDiscoveryService()
  ) {
    self.store = store
    self.ollamaDiscovery = ollamaDiscovery
  }

  public func bootstrap() async {
    await reload()
  }

  public func reload() async {
    do {
      let document = try await store.load()
      profiles = document.profiles.sorted(by: Self.profileSort)
      activeProfileID = document.activeProfileID
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  @discardableResult
  public func importCurrentConfiguration(
    appState: AppState,
    operating: AgentOperatingLayerSettings = .shared
  ) async -> ModelProfile? {
    do {
      let profile = ModelProfile.fromCurrentConfiguration(
        app: appState.configuration,
        operating: operating.configuration
      )
      let saved = try await store.upsert(profile)
      await reload()
      statusMessage = "Aktuelle Provider-/Runtime-Konfiguration als Modellprofil importiert."
      return saved
    } catch {
      statusMessage = error.localizedDescription
      return nil
    }
  }

  @discardableResult
  public func discoverLocalOllamaModels(
    baseURL: String = LocalInferenceRuntime.ollama.defaultBaseURL
  ) async -> [ModelProfile] {
    statusMessage = "Lokale Ollama-Modelle werden erkannt …"

    do {
      let discovered = try await ollamaDiscovery.discover(baseURL: baseURL)
      let candidates = discovered.map {
        OllamaModelDiscoveryService.makeProfile(from: $0, baseURL: baseURL)
      }
      let merged = try await store.mergeDiscoveredLocalOllamaProfiles(candidates)
      await reload()
      statusMessage =
        "Ollama-Scan abgeschlossen: \(merged.count) lokale Modelle erkannt/aktualisiert. :cloud-Aliase wurden bewusst nicht als lokale Profile importiert."
      return merged
    } catch is CancellationError {
      statusMessage = "Ollama-Scan abgebrochen."
      return []
    } catch {
      statusMessage = error.localizedDescription
      return []
    }
  }

  public func save(_ profile: ModelProfile) async {
    do {
      _ = try await store.upsert(profile)
      await reload()
      statusMessage = "Modellprofil gespeichert."
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  public func remove(_ profile: ModelProfile) async {
    do {
      try await store.remove(id: profile.id)
      await reload()
      statusMessage = "Modellprofil entfernt. Vault-Secrets wurden nicht verändert."
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  public func activate(
    profileID: UUID,
    appState: AppState,
    operating: AgentOperatingLayerSettings = .shared
  ) async {
    do {
      guard let profile = try await store.profile(id: profileID) else {
        throw ModelProfileError.profileNotFound
      }
      guard profile.enabled else { throw ModelProfileError.profileDisabled }
      if profile.runtime == .ollamaCloud, profile.apiKeySecretID == nil {
        throw ModelProfileError.missingCloudSecretReference
      }

      let plan = profile.activationPlan
      if operating.configuration.localInferenceRuntime == .anemll,
        plan.localInferenceRuntime != .anemll
      {
        await ANEMLLPersistentRuntimeService.shared.shutdown()
      }

      appState.configuration.providerKind = plan.providerKind
      appState.configuration.baseURL = plan.baseURL
      appState.configuration.model = plan.model
      appState.configuration.apiKeySecretID = plan.apiKeySecretID
      if let runtime = plan.localInferenceRuntime {
        operating.configuration.localInferenceRuntime = runtime
      }
      operating.configuration.numContext = plan.contextWindow
      try operating.save()
      await appState.saveConfiguration()
      try await store.setActive(id: profile.id)
      await reload()
      statusMessage = "Aktiv: \(profile.name)"
    } catch {
      appState.errorMessage = error.localizedDescription
      statusMessage = error.localizedDescription
    }
  }

  public func routingCandidates(preferLocal: Bool) async -> [ModelProfile] {
    do {
      return try await store.routingCandidates(preferLocal: preferLocal)
    } catch {
      statusMessage = error.localizedDescription
      return []
    }
  }

  private static func profileSort(_ lhs: ModelProfile, _ rhs: ModelProfile) -> Bool {
    if lhs.enabled != rhs.enabled { return lhs.enabled && !rhs.enabled }
    if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
  }
}
