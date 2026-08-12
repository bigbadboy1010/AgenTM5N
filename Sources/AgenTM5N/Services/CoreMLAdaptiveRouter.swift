import Foundation

public enum CoreMLAdaptiveConfidence: String, Codable, Sendable {
  case high
  case medium
  case low

  public var displayName: String {
    switch self {
    case .high:
      return L10n.text(de: "Hoch", en: "High", fr: "Élevée")
    case .medium:
      return L10n.text(de: "Mittel", en: "Medium", fr: "Moyenne")
    case .low:
      return L10n.text(de: "Niedrig", en: "Low", fr: "Faible")
    }
  }
}

public enum CoreMLAdaptiveWorkloadPreset: String, Codable, CaseIterable, Identifiable, Sendable {
  case oneShot
  case interactive
  case sustained

  public var id: String { rawValue }

  public var expectedPredictions: Int {
    switch self {
    case .oneShot:
      return 1
    case .interactive:
      return 100
    case .sustained:
      return 5_000
    }
  }

  public var displayName: String {
    switch self {
    case .oneShot:
      return L10n.text(de: "Einzellauf", en: "One-shot", fr: "Exécution unique")
    case .interactive:
      return L10n.text(de: "Interaktiver Agent", en: "Interactive agent", fr: "Agent interactif")
    case .sustained:
      return L10n.text(de: "Dauerlast / Batch", en: "Sustained / batch", fr: "Charge soutenue / lot")
    }
  }
}

public struct CoreMLAdaptiveModeEstimate: Codable, Equatable, Sendable, Identifiable {
  public var id: String { mode.rawValue }

  public let mode: CoreMLComputeMode
  public let estimatedTotalMilliseconds: Double
  public let coldStartMilliseconds: Double
  public let warmP50Milliseconds: Double

  public init(
    mode: CoreMLComputeMode,
    estimatedTotalMilliseconds: Double,
    coldStartMilliseconds: Double,
    warmP50Milliseconds: Double
  ) {
    self.mode = mode
    self.estimatedTotalMilliseconds = estimatedTotalMilliseconds
    self.coldStartMilliseconds = coldStartMilliseconds
    self.warmP50Milliseconds = warmP50Milliseconds
  }
}

public struct CoreMLAdaptiveRouteDecision: Codable, Equatable, Sendable {
  public let expectedPredictions: Int
  public let recommendedMode: CoreMLComputeMode
  public let coldStartMode: CoreMLComputeMode?
  public let warmLatencyMode: CoreMLComputeMode?
  public let aneBreakEvenPredictionsVersusAutomatic: Int?
  public let confidence: CoreMLAdaptiveConfidence
  public let estimates: [CoreMLAdaptiveModeEstimate]
  public let reason: String

  public init(
    expectedPredictions: Int,
    recommendedMode: CoreMLComputeMode,
    coldStartMode: CoreMLComputeMode?,
    warmLatencyMode: CoreMLComputeMode?,
    aneBreakEvenPredictionsVersusAutomatic: Int?,
    confidence: CoreMLAdaptiveConfidence,
    estimates: [CoreMLAdaptiveModeEstimate],
    reason: String
  ) {
    self.expectedPredictions = max(1, expectedPredictions)
    self.recommendedMode = recommendedMode
    self.coldStartMode = coldStartMode
    self.warmLatencyMode = warmLatencyMode
    self.aneBreakEvenPredictionsVersusAutomatic = aneBreakEvenPredictionsVersusAutomatic
    self.confidence = confidence
    self.estimates = estimates
    self.reason = reason
  }
}

public struct CoreMLAdaptiveRoutingProfile: Codable, Equatable, Sendable, Identifiable {
  public var id: String { profileKey }

  public let profileKey: String
  public let modelName: String
  public let compiledPath: String
  public let environmentSignature: String
  public var modelLabReport: CoreMLModelLabReport?
  public var runtimeBenchmarkReport: CoreMLRuntimeBenchmarkReport?
  public var updatedAt: Date

  public init(
    profileKey: String,
    modelName: String,
    compiledPath: String,
    environmentSignature: String,
    modelLabReport: CoreMLModelLabReport? = nil,
    runtimeBenchmarkReport: CoreMLRuntimeBenchmarkReport? = nil,
    updatedAt: Date = Date()
  ) {
    self.profileKey = profileKey
    self.modelName = modelName
    self.compiledPath = compiledPath
    self.environmentSignature = environmentSignature
    self.modelLabReport = modelLabReport
    self.runtimeBenchmarkReport = runtimeBenchmarkReport
    self.updatedAt = updatedAt
  }
}

/// Persists hardware-specific Core ML routing evidence and combines plan data
/// with actual prediction latency. The router never claims measured ANE
/// utilization: MLComputePlan supplies anticipated placement while the runtime
/// benchmark supplies end-to-end prediction latency.
public actor CoreMLAdaptiveRouter {
  public static let shared = CoreMLAdaptiveRouter()

  private let store: JSONDocumentStore<[CoreMLAdaptiveRoutingProfile]>

  public init(
    store: JSONDocumentStore<[CoreMLAdaptiveRoutingProfile]> = JSONDocumentStore(
      url: AppPaths.coreMLRoutingProfilesFile,
      defaultValue: []
    )
  ) {
    self.store = store
  }

  public func profile(
    compiledURL: URL
  ) async -> CoreMLAdaptiveRoutingProfile? {
    let key = Self.profileKey(compiledURL: compiledURL)
    return (try? await store.load())?.first(where: { $0.profileKey == key })
  }

  public func recordModelLab(
    _ report: CoreMLModelLabReport,
    compiledURL: URL,
    modelName: String
  ) async {
    await mutateProfile(
      compiledURL: compiledURL,
      modelName: modelName
    ) { profile in
      profile.modelLabReport = report
      profile.updatedAt = Date()
    }
  }

  public func recordRuntimeBenchmark(
    _ report: CoreMLRuntimeBenchmarkReport,
    compiledURL: URL,
    modelName: String
  ) async {
    await mutateProfile(
      compiledURL: compiledURL,
      modelName: modelName
    ) { profile in
      profile.runtimeBenchmarkReport = report
      profile.updatedAt = Date()
    }
  }

  public func decision(
    compiledURL: URL,
    expectedPredictions: Int
  ) async -> CoreMLAdaptiveRouteDecision? {
    guard
      let profile = await profile(compiledURL: compiledURL),
      let runtime = profile.runtimeBenchmarkReport
    else {
      return nil
    }
    return Self.evaluate(
      modelLabReport: profile.modelLabReport,
      runtimeReport: runtime,
      expectedPredictions: expectedPredictions
    )
  }

  public static func evaluate(
    modelLabReport: CoreMLModelLabReport?,
    runtimeReport: CoreMLRuntimeBenchmarkReport,
    expectedPredictions: Int
  ) -> CoreMLAdaptiveRouteDecision {
    let predictionCount = max(1, expectedPredictions)
    let usable = runtimeReport.results.compactMap { result -> CoreMLAdaptiveModeEstimate? in
      guard
        result.succeeded,
        let first = result.firstPredictionMilliseconds,
        let warmP50 = result.warmP50Milliseconds
      else {
        return nil
      }
      let cold = result.modelLoadMilliseconds + first
      let total = cold + Double(max(0, predictionCount - 1)) * warmP50
      return CoreMLAdaptiveModeEstimate(
        mode: result.mode,
        estimatedTotalMilliseconds: total,
        coldStartMilliseconds: cold,
        warmP50Milliseconds: warmP50
      )
    }

    let automaticEstimate = usable.first(where: { $0.mode == .automatic })
    let coldStartMode = usable.min {
      $0.coldStartMilliseconds < $1.coldStartMilliseconds
    }?.mode
    let warmLatencyMode = usable.min {
      $0.warmP50Milliseconds < $1.warmP50Milliseconds
    }?.mode
    let breakEven = breakEvenPredictions(
      baseline: automaticEstimate,
      challenger: usable.first(where: { $0.mode == .neuralEnginePreferred })
    )

    let outputsSafe = runtimeReport.outputsStructurallyEquivalent
    let selected: CoreMLAdaptiveModeEstimate?
    if outputsSafe {
      selected = usable.min {
        $0.estimatedTotalMilliseconds < $1.estimatedTotalMilliseconds
      }
    } else if let automaticEstimate {
      // If successful modes produce different output structures, keep the
      // adaptive Core ML policy rather than automatically forcing a specialized
      // backend based on latency alone.
      selected = automaticEstimate
    } else {
      selected = usable.min {
        $0.estimatedTotalMilliseconds < $1.estimatedTotalMilliseconds
      }
    }

    let recommendedMode = selected?.mode ?? .automatic
    let planResult = modelLabReport?.result(for: recommendedMode)
    let confidence: CoreMLAdaptiveConfidence
    if outputsSafe, selected != nil, planResult?.succeeded == true {
      confidence = .high
    } else if outputsSafe, selected != nil {
      confidence = .medium
    } else {
      confidence = .low
    }

    let reason: String
    if !outputsSafe {
      reason = L10n.text(
        de: "Die erfolgreichen Runtime-Modi liefern keine identische Ausgabestruktur. Der Router priorisiert deshalb Robustheit vor Latenz und vermeidet eine aggressive automatische Umschaltung.",
        en: "Successful runtime modes do not produce an identical output structure. The router therefore prioritizes robustness over latency and avoids an aggressive automatic switch.",
        fr: "Les modes d’exécution réussis ne produisent pas une structure de sortie identique. Le routeur privilégie donc la robustesse à la latence et évite une commutation automatique agressive."
      )
    } else if recommendedMode == .automatic,
      warmLatencyMode == .neuralEnginePreferred,
      let breakEven,
      predictionCount < breakEven
    {
      reason = L10n.text(
        de: "CPU+ANE hat die niedrigere warme p50-Latenz, aber seine zusätzliche Ladezeit amortisiert sich gegenüber Automatisch erst nach ungefähr \(breakEven) Vorhersagen pro Modell-Ladevorgang. Für \(predictionCount) erwartete Vorhersagen bleibt Automatisch insgesamt schneller.",
        en: "CPU+ANE has the lower warm p50 latency, but its additional load cost only breaks even against Automatic after about \(breakEven) predictions per model load. For \(predictionCount) expected predictions, Automatic remains faster overall.",
        fr: "CPU+ANE offre une latence p50 à chaud plus faible, mais son coût de chargement supplémentaire ne s’amortit face à Automatique qu’après environ \(breakEven) prédictions par chargement du modèle. Pour \(predictionCount) prédictions attendues, Automatique reste globalement plus rapide."
      )
    } else if recommendedMode == .neuralEnginePreferred {
      reason = L10n.text(
        de: "Für \(predictionCount) erwartete Vorhersagen überwiegt die niedrigere warme CPU+ANE-Latenz die zusätzliche Ladezeit. Der Router empfiehlt deshalb CPU+Neural Engine für diese Lastklasse.",
        en: "For \(predictionCount) expected predictions, the lower warm CPU+ANE latency outweighs its additional load cost. The router therefore recommends CPU+Neural Engine for this workload class.",
        fr: "Pour \(predictionCount) prédictions attendues, la latence CPU+ANE plus faible à chaud compense son coût de chargement supplémentaire. Le routeur recommande donc CPU+Neural Engine pour cette classe de charge."
      )
    } else {
      reason = L10n.text(
        de: "Der Router wählt den erfolgreichen Modus mit der niedrigsten geschätzten Gesamtlatenz aus Modell-Ladezeit, erster Vorhersage und warmem p50 für \(predictionCount) Vorhersagen.",
        en: "The router selects the successful mode with the lowest estimated total latency from model load, first prediction, and warm p50 for \(predictionCount) predictions.",
        fr: "Le routeur choisit le mode réussi avec la latence totale estimée la plus faible à partir du chargement du modèle, de la première prédiction et du p50 à chaud pour \(predictionCount) prédictions."
      )
    }

    return CoreMLAdaptiveRouteDecision(
      expectedPredictions: predictionCount,
      recommendedMode: recommendedMode,
      coldStartMode: coldStartMode,
      warmLatencyMode: warmLatencyMode,
      aneBreakEvenPredictionsVersusAutomatic: breakEven,
      confidence: confidence,
      estimates: usable.sorted {
        $0.estimatedTotalMilliseconds < $1.estimatedTotalMilliseconds
      },
      reason: reason
    )
  }

  public static func currentEnvironmentSignature() -> String {
    let profile = HardwareService.makeProfile(appleFoundationModelStatus: "")
    return [
      profile.chipName,
      String(profile.memoryBytes),
      profile.operatingSystem,
    ].joined(separator: "|")
  }

  private func mutateProfile(
    compiledURL: URL,
    modelName: String,
    mutation: (inout CoreMLAdaptiveRoutingProfile) -> Void
  ) async {
    do {
      var profiles = try await store.load()
      let key = Self.profileKey(compiledURL: compiledURL)
      let environment = Self.currentEnvironmentSignature()
      if let index = profiles.firstIndex(where: { $0.profileKey == key }) {
        // A profile is hardware/OS-specific. If the environment changed, keep
        // the model identity but discard stale benchmark evidence.
        if profiles[index].environmentSignature != environment {
          profiles[index] = CoreMLAdaptiveRoutingProfile(
            profileKey: key,
            modelName: modelName,
            compiledPath: compiledURL.standardizedFileURL.path,
            environmentSignature: environment
          )
        }
        mutation(&profiles[index])
      } else {
        var profile = CoreMLAdaptiveRoutingProfile(
          profileKey: key,
          modelName: modelName,
          compiledPath: compiledURL.standardizedFileURL.path,
          environmentSignature: environment
        )
        mutation(&profile)
        profiles.append(profile)
      }
      try await store.save(profiles)
    } catch {
      AppLogger.app.error(
        "Adaptive Core ML routing profile persistence failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private static func profileKey(compiledURL: URL) -> String {
    "\(compiledURL.standardizedFileURL.path)|\(currentEnvironmentSignature())"
  }

  private static func breakEvenPredictions(
    baseline: CoreMLAdaptiveModeEstimate?,
    challenger: CoreMLAdaptiveModeEstimate?
  ) -> Int? {
    guard let baseline, let challenger else { return nil }
    let warmSavings = baseline.warmP50Milliseconds - challenger.warmP50Milliseconds
    guard warmSavings > 0 else { return nil }

    let extraColdCost = challenger.coldStartMilliseconds - baseline.coldStartMilliseconds
    if extraColdCost <= 0 { return 1 }

    return Int(ceil(extraColdCost / warmSavings)) + 1
  }
}
