import Foundation

public enum CoreMLNeuralWorkloadKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case genericPrediction
  case workspaceEmbeddingQuery
  case workspaceEmbeddingBatch
  case agentInference
  case classification

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .genericPrediction:
      return L10n.text(de: "Generische Vorhersage", en: "Generic prediction", fr: "Prédiction générique")
    case .workspaceEmbeddingQuery:
      return L10n.text(de: "Workspace-Such-Embedding", en: "Workspace search embedding", fr: "Embedding de recherche d’espace de travail")
    case .workspaceEmbeddingBatch:
      return L10n.text(de: "Workspace-Index-Embedding", en: "Workspace index embedding", fr: "Embedding d’index d’espace de travail")
    case .agentInference:
      return L10n.text(de: "Agent-Inferenz", en: "Agent inference", fr: "Inférence agent")
    case .classification:
      return L10n.text(de: "Klassifikation / Intent", en: "Classification / intent", fr: "Classification / intention")
    }
  }
}

public struct CoreMLNeuralWorkload: Equatable, Sendable {
  public let kind: CoreMLNeuralWorkloadKind
  public let expectedPredictions: Int?
  public let itemCount: Int

  public init(
    kind: CoreMLNeuralWorkloadKind,
    expectedPredictions: Int?,
    itemCount: Int = 1
  ) {
    self.kind = kind
    self.expectedPredictions = expectedPredictions.map { max(1, $0) }
    self.itemCount = max(1, itemCount)
  }

  /// Preserves the user-selected Build-34 workload preset.
  public static let genericPrediction = CoreMLNeuralWorkload(
    kind: .genericPrediction,
    expectedPredictions: nil
  )

  /// A semantic-memory lookup embeds exactly one query per request.
  public static let workspaceEmbeddingQuery = CoreMLNeuralWorkload(
    kind: .workspaceEmbeddingQuery,
    expectedPredictions: 1
  )

  /// Workspace indexing performs one prediction per chunk while keeping the
  /// model loaded for the whole batch. The concrete chunk count is therefore
  /// the correct cost input for the adaptive router.
  public static func workspaceEmbeddingBatch(count: Int) -> CoreMLNeuralWorkload {
    let bounded = max(1, count)
    return CoreMLNeuralWorkload(
      kind: .workspaceEmbeddingBatch,
      expectedPredictions: bounded,
      itemCount: bounded
    )
  }

  public static func agentInference(expectedPredictions: Int? = nil) -> CoreMLNeuralWorkload {
    CoreMLNeuralWorkload(
      kind: .agentInference,
      expectedPredictions: expectedPredictions
    )
  }

  public static func classification(count: Int = 1) -> CoreMLNeuralWorkload {
    let bounded = max(1, count)
    return CoreMLNeuralWorkload(
      kind: .classification,
      expectedPredictions: bounded,
      itemCount: bounded
    )
  }
}

/// Build 35 orchestration boundary for real Core ML workloads.
///
/// Build 34 made adaptive routing executable for individual predictions. Build
/// 35 adds workload semantics so callers can supply the actual number of model
/// invocations expected while the model remains loaded. Workspace indexing can
/// therefore be evaluated as a batch, while semantic search remains a one-shot
/// request. Manual execution still preserves the explicit Core ML policy.
public enum CoreMLNeuralRuntimeOrchestrator {
  public static func resolve(
    compiledURL: URL,
    workload: CoreMLNeuralWorkload
  ) async -> CoreMLExecutionRoute {
    await CoreMLAdaptiveExecutionPolicy.resolve(
      compiledURL: compiledURL,
      expectedPredictions: workload.expectedPredictions
    )
  }
}
