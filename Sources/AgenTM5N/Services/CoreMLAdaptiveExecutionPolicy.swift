import Foundation

public enum CoreMLExecutionStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
  case manual
  case adaptive

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .manual:
      return L10n.text(
        de: "Manuell",
        en: "Manual",
        fr: "Manuel"
      )
    case .adaptive:
      return L10n.text(
        de: "Adaptiv",
        en: "Adaptive",
        fr: "Adaptatif"
      )
    }
  }
}

public enum CoreMLExecutionRouteSource: String, Codable, Sendable {
  case manual
  case adaptive
  case automaticFallback
}

public struct CoreMLExecutionRoute: Equatable, Sendable {
  public let mode: CoreMLComputeMode
  public let source: CoreMLExecutionRouteSource
  public let expectedPredictions: Int?
  public let confidence: CoreMLAdaptiveConfidence?
  public let reason: String

  public init(
    mode: CoreMLComputeMode,
    source: CoreMLExecutionRouteSource,
    expectedPredictions: Int? = nil,
    confidence: CoreMLAdaptiveConfidence? = nil,
    reason: String
  ) {
    self.mode = mode
    self.source = source
    self.expectedPredictions = expectedPredictions
    self.confidence = confidence
    self.reason = reason
  }

  public var adaptiveRoutingApplied: Bool {
    source == .adaptive
  }

  public var allowsAutomaticFailover: Bool {
    source == .adaptive && mode != .automatic
  }
}

public enum CoreMLAdaptiveExecutionPolicyStore {
  private static let strategyKey = "AgenTM5N.CoreMLExecutionStrategy"
  private static let workloadKey = "AgenTM5N.CoreMLAdaptiveWorkloadPreset"

  public static var strategy: CoreMLExecutionStrategy {
    guard
      let raw = UserDefaults.standard.string(forKey: strategyKey),
      let value = CoreMLExecutionStrategy(rawValue: raw)
    else {
      return .manual
    }
    return value
  }

  public static func setStrategy(_ strategy: CoreMLExecutionStrategy) {
    UserDefaults.standard.set(strategy.rawValue, forKey: strategyKey)
  }

  public static var workloadPreset: CoreMLAdaptiveWorkloadPreset {
    guard
      let raw = UserDefaults.standard.string(forKey: workloadKey),
      let value = CoreMLAdaptiveWorkloadPreset(rawValue: raw)
    else {
      return .interactive
    }
    return value
  }

  public static func setWorkloadPreset(_ preset: CoreMLAdaptiveWorkloadPreset) {
    UserDefaults.standard.set(preset.rawValue, forKey: workloadKey)
  }
}

/// Resolves the concrete Core ML compute mode used for a prediction.
///
/// Manual execution preserves the explicit Neural Compute Runtime policy.
/// Adaptive execution consumes the hardware/OS-specific routing profile created
/// by the Model Lab and Runtime Benchmark. Missing or low-confidence evidence
/// intentionally falls back to Automatic instead of forcing a specialized
/// backend.
public enum CoreMLAdaptiveExecutionPolicy {
  public static func resolve(compiledURL: URL) async -> CoreMLExecutionRoute {
    let strategy = CoreMLAdaptiveExecutionPolicyStore.strategy
    let manualMode = CoreMLRuntimePolicyStore.currentMode
    let preset = CoreMLAdaptiveExecutionPolicyStore.workloadPreset

    guard strategy == .adaptive else {
      return evaluate(
        strategy: .manual,
        manualMode: manualMode,
        workloadPreset: preset,
        decision: nil
      )
    }

    let decision = await CoreMLAdaptiveRouter.shared.decision(
      compiledURL: compiledURL,
      expectedPredictions: preset.expectedPredictions
    )

    return evaluate(
      strategy: strategy,
      manualMode: manualMode,
      workloadPreset: preset,
      decision: decision
    )
  }

  public static func evaluate(
    strategy: CoreMLExecutionStrategy,
    manualMode: CoreMLComputeMode,
    workloadPreset: CoreMLAdaptiveWorkloadPreset,
    decision: CoreMLAdaptiveRouteDecision?
  ) -> CoreMLExecutionRoute {
    guard strategy == .adaptive else {
      return CoreMLExecutionRoute(
        mode: manualMode,
        source: .manual,
        reason: L10n.text(
          de: "Manuelle Core-ML-Rechenrichtlinie aktiv.",
          en: "Manual Core ML compute policy is active.",
          fr: "La politique de calcul Core ML manuelle est active."
        )
      )
    }

    guard let decision else {
      return CoreMLExecutionRoute(
        mode: .automatic,
        source: .automaticFallback,
        expectedPredictions: workloadPreset.expectedPredictions,
        confidence: .low,
        reason: L10n.text(
          de: "Für dieses Modell und diese Hardware liegt noch kein vollständiges Runtime-Profil vor. Adaptive Execution verwendet deshalb sicherheitshalber Automatisch.",
          en: "No complete runtime profile exists yet for this model and hardware. Adaptive Execution therefore safely uses Automatic.",
          fr: "Aucun profil d’exécution complet n’existe encore pour ce modèle et ce matériel. Adaptive Execution utilise donc Automatique par sécurité."
        )
      )
    }

    guard decision.confidence != .low else {
      return CoreMLExecutionRoute(
        mode: .automatic,
        source: .automaticFallback,
        expectedPredictions: decision.expectedPredictions,
        confidence: decision.confidence,
        reason: L10n.text(
          de: "Die adaptive Routing-Evidenz hat niedrige Konfidenz. AgenTM5N erzwingt keinen spezialisierten Compute-Pfad und verwendet Automatisch.",
          en: "Adaptive routing evidence has low confidence. AgenTM5N does not force a specialized compute path and uses Automatic.",
          fr: "Les données de routage adaptatif ont une faible confiance. AgenTM5N n’impose pas de chemin de calcul spécialisé et utilise Automatique."
        )
      )
    }

    return CoreMLExecutionRoute(
      mode: decision.recommendedMode,
      source: .adaptive,
      expectedPredictions: decision.expectedPredictions,
      confidence: decision.confidence,
      reason: decision.reason
    )
  }

  public static func automaticFailover(
    from route: CoreMLExecutionRoute,
    error: Error
  ) -> CoreMLExecutionRoute {
    CoreMLExecutionRoute(
      mode: .automatic,
      source: .automaticFallback,
      expectedPredictions: route.expectedPredictions,
      confidence: .low,
      reason: L10n.text(
        de: "Der adaptive Modus \(route.mode.displayName) ist bei der echten Vorhersage fehlgeschlagen (\(error.localizedDescription)). AgenTM5N hat die Vorhersage automatisch mit Automatisch wiederholt.",
        en: "Adaptive mode \(route.mode.displayName) failed during the real prediction (\(error.localizedDescription)). AgenTM5N automatically retried the prediction with Automatic.",
        fr: "Le mode adaptatif \(route.mode.displayName) a échoué pendant la prédiction réelle (\(error.localizedDescription)). AgenTM5N a automatiquement relancé la prédiction avec Automatique."
      )
    )
  }
}
