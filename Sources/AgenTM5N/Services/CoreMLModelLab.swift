import Foundation

public enum CoreMLANESuitability: String, Codable, CaseIterable, Sendable {
  case high
  case medium
  case low
  case inconclusive

  public var displayName: String {
    switch self {
    case .high:
      return L10n.text(de: "Hoch", en: "High", fr: "Élevée")
    case .medium:
      return L10n.text(de: "Mittel", en: "Medium", fr: "Moyenne")
    case .low:
      return L10n.text(de: "Niedrig", en: "Low", fr: "Faible")
    case .inconclusive:
      return L10n.text(de: "Unbestimmt", en: "Inconclusive", fr: "Indéterminée")
    }
  }
}

public struct CoreMLModelLabModeResult: Codable, Equatable, Sendable, Identifiable {
  public var id: String { mode.rawValue }

  public let mode: CoreMLComputeMode
  public let succeeded: Bool
  public let durationMilliseconds: Double
  public let report: CoreMLComputePlanReport?
  public let errorDescription: String?

  public init(
    mode: CoreMLComputeMode,
    succeeded: Bool,
    durationMilliseconds: Double,
    report: CoreMLComputePlanReport?,
    errorDescription: String?
  ) {
    self.mode = mode
    self.succeeded = succeeded
    self.durationMilliseconds = durationMilliseconds
    self.report = report
    self.errorDescription = errorDescription
  }

  public var resolvedOperations: Int {
    guard let report else { return 0 }
    return max(0, report.totalOperations - report.unknownPreferredOperations)
  }
}

public struct CoreMLModelLabReport: Codable, Equatable, Sendable {
  public let modelName: String
  public let generatedAt: Date
  public let results: [CoreMLModelLabModeResult]
  public let aneSuitability: CoreMLANESuitability
  public let aneSuitabilityScore: Int
  public let recommendedMode: CoreMLComputeMode
  public let recommendationReason: String

  public init(
    modelName: String,
    generatedAt: Date = Date(),
    results: [CoreMLModelLabModeResult],
    aneSuitability: CoreMLANESuitability,
    aneSuitabilityScore: Int,
    recommendedMode: CoreMLComputeMode,
    recommendationReason: String
  ) {
    self.modelName = modelName
    self.generatedAt = generatedAt
    self.results = results
    self.aneSuitability = aneSuitability
    self.aneSuitabilityScore = max(0, min(aneSuitabilityScore, 100))
    self.recommendedMode = recommendedMode
    self.recommendationReason = recommendationReason
  }

  public func result(for mode: CoreMLComputeMode) -> CoreMLModelLabModeResult? {
    results.first(where: { $0.mode == mode })
  }
}

public enum CoreMLModelLab {
  /// Deliberately excludes CPU-only from the default comparison. The lab is
  /// focused on the decision between adaptive scheduling, GPU-backed Core ML,
  /// and the CPU+ANE policy. CPU-only remains available as a manual diagnostic.
  public static let benchmarkModes: [CoreMLComputeMode] = [
    .automatic,
    .cpuAndGPU,
    .neuralEnginePreferred,
  ]

  public static func runMode(
    compiledURL: URL,
    mode: CoreMLComputeMode
  ) async -> CoreMLModelLabModeResult {
    let startedAt = ContinuousClock().now
    do {
      let report = try await CoreMLComputePlanAnalyzer.analyze(
        compiledURL: compiledURL,
        mode: mode
      )
      return CoreMLModelLabModeResult(
        mode: mode,
        succeeded: true,
        durationMilliseconds: milliseconds(
          from: startedAt.duration(to: ContinuousClock().now)
        ),
        report: report,
        errorDescription: nil
      )
    } catch {
      return CoreMLModelLabModeResult(
        mode: mode,
        succeeded: false,
        durationMilliseconds: milliseconds(
          from: startedAt.duration(to: ContinuousClock().now)
        ),
        report: nil,
        errorDescription: error.localizedDescription
      )
    }
  }

  public static func evaluate(
    modelName: String,
    results: [CoreMLModelLabModeResult]
  ) -> CoreMLModelLabReport {
    let automatic = results.first(where: { $0.mode == .automatic })
    let cpuGPU = results.first(where: { $0.mode == .cpuAndGPU })
    let cpuANE = results.first(where: { $0.mode == .neuralEnginePreferred })

    let aneEvidence = cpuANE?.report
    let automaticEvidence = automatic?.report

    let anePlanSucceeded = cpuANE?.succeeded == true
    let resolvedANE = max(
      0,
      (aneEvidence?.totalOperations ?? 0) - (aneEvidence?.unknownPreferredOperations ?? 0)
    )
    let aneSignalCount = max(
      aneEvidence?.preferredNeuralEngineOperations ?? 0,
      aneEvidence?.neuralEngineSupportedOperations ?? 0
    )
    let aneCoverage = resolvedANE > 0
      ? Double(aneSignalCount) / Double(resolvedANE)
      : 0

    let suitability: CoreMLANESuitability
    let score: Int

    if anePlanSucceeded, aneSignalCount > 0 {
      if aneCoverage >= 0.50 {
        suitability = .high
      } else {
        suitability = .medium
      }
      // Transparent heuristic, not a measured utilization percentage. A
      // successful CPU+ANE plan establishes a 35-point base; resolved ANE
      // coverage contributes the remaining 65 points.
      score = Int((35 + min(1, aneCoverage) * 65).rounded())
    } else if anePlanSucceeded {
      suitability = .inconclusive
      score = 35
    } else if automaticEvidence?.preferredNeuralEngineOperations == 0,
      automaticEvidence?.neuralEngineSupportedOperations == 0
    {
      suitability = .low
      score = 0
    } else {
      suitability = .inconclusive
      score = 10
    }

    let recommendedMode: CoreMLComputeMode
    let reason: String

    if (suitability == .high || suitability == .medium), anePlanSucceeded {
      recommendedMode = .neuralEnginePreferred
      reason = L10n.text(
        de: "Der CPU+ANE-Plan lässt sich aufbauen und Core ML meldet Neural-Engine-Unterstützung für aufgelöste Operationen.",
        en: "The CPU+ANE plan builds successfully and Core ML reports Neural Engine support for resolved operations.",
        fr: "Le plan CPU+ANE se construit correctement et Core ML signale une prise en charge du Neural Engine pour les opérations résolues."
      )
    } else if automatic?.succeeded == true {
      recommendedMode = .automatic
      if cpuANE?.succeeded == false, cpuGPU?.succeeded == true {
        reason = L10n.text(
          de: "Automatisch ist der sicherste Modus: der adaptive Plan funktioniert, CPU+GPU funktioniert, während CPU+ANE keinen Plan aufbauen konnte.",
          en: "Automatic is the safest mode: adaptive scheduling works, CPU+GPU works, while CPU+ANE could not build a plan.",
          fr: "Automatique est le mode le plus sûr : la planification adaptative fonctionne, CPU+GPU fonctionne, tandis que CPU+ANE n’a pas pu construire de plan."
        )
      } else {
        reason = L10n.text(
          de: "Der automatische Core-ML-Plan ist verfügbar und bleibt die robusteste Standardwahl, solange keine stärkere ANE-Evidenz vorliegt.",
          en: "The automatic Core ML plan is available and remains the most robust default while stronger ANE evidence is absent.",
          fr: "Le plan Core ML automatique est disponible et reste le choix par défaut le plus robuste tant qu’aucune preuve ANE plus forte n’est disponible."
        )
      }
    } else if cpuGPU?.succeeded == true {
      recommendedMode = .cpuAndGPU
      reason = L10n.text(
        de: "Der adaptive Plan ist fehlgeschlagen, aber CPU+GPU konnte erfolgreich aufgebaut werden.",
        en: "The adaptive plan failed, but CPU+GPU built successfully.",
        fr: "Le plan adaptatif a échoué, mais CPU+GPU a été construit avec succès."
      )
    } else {
      recommendedMode = .cpuOnly
      reason = L10n.text(
        de: "Keiner der beschleunigten Vergleichsmodi war eindeutig verfügbar. CPU-only bleibt als Diagnose-Fallback.",
        en: "None of the accelerated comparison modes was clearly available. CPU-only remains as a diagnostic fallback.",
        fr: "Aucun des modes accélérés comparés n’était clairement disponible. CPU-only reste un mode de diagnostic de secours."
      )
    }

    return CoreMLModelLabReport(
      modelName: modelName,
      results: benchmarkModes.compactMap { mode in
        results.first(where: { $0.mode == mode })
      },
      aneSuitability: suitability,
      aneSuitabilityScore: score,
      recommendedMode: recommendedMode,
      recommendationReason: reason
    )
  }

  private static func milliseconds(from duration: Duration) -> Double {
    let components = duration.components
    let seconds = Double(components.seconds)
    let attoseconds = Double(components.attoseconds)
    return seconds * 1_000 + attoseconds / 1_000_000_000_000_000
  }
}
