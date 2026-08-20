import Foundation

public enum AutomaticRuntimeResidencyAction: Equatable, Sendable {
  case none
  case preserveUserConfiguration
  case evictANEMLLAfterTurn
  case shortOllamaKeepAlive(seconds: Int)
  case observeOnly(HeavyInferenceRuntime)
}

/// Residency policy for a complete model turn, not for individual tool rounds.
///
/// A tool-calling turn may invoke the provider multiple times. Evicting between
/// those rounds can turn one request into repeated model loads and worsen the
/// exact CPU/unified-memory pressure this safety branch is designed to avoid.
public enum AutomaticRuntimeResidencyPolicy {
  public static let defaultAutomaticOllamaKeepAliveSeconds = 30

  public static func action(
    origin: TurnExecutionOrigin,
    runtime: ModelProfileRuntime?
  ) -> AutomaticRuntimeResidencyAction {
    guard origin == .automaticModelProfile else {
      return .preserveUserConfiguration
    }
    guard let runtime else { return .none }

    switch runtime {
    case .anemll:
      return .evictANEMLLAfterTurn
    case .ollamaLocal:
      return .shortOllamaKeepAlive(
        seconds: defaultAutomaticOllamaKeepAliveSeconds
      )
    case .mlx:
      return .observeOnly(.mlx)
    case .appleFoundationModels:
      return .observeOnly(.appleFoundationModels)
    case .ollamaCloud:
      return .none
    }
  }

  public static func applying(
    _ action: AutomaticRuntimeResidencyAction,
    to operatingConfiguration: AgentOperatingLayerConfiguration
  ) -> AgentOperatingLayerConfiguration {
    var result = operatingConfiguration
    switch action {
    case .shortOllamaKeepAlive(let seconds):
      result.keepAlive = "\(max(0, min(seconds, 300)))s"
      result.normalize()
    case .none, .preserveUserConfiguration, .evictANEMLLAfterTurn, .observeOnly:
      break
    }
    return result
  }
}

public enum AutomaticRuntimeResidencyCleanupError: LocalizedError, Equatable {
  case anemllExitUnconfirmed

  public var errorDescription: String? {
    switch self {
    case .anemllExitUnconfirmed:
      return L10n.text(
        de: "Der automatische ANEMLL-Turn konnte die Runtime nach Abschluss nicht sicher entladen. Weitere schwere lokale Inferenz bleibt fail-closed blockiert.",
        en: "The automatic ANEMLL turn could not safely unload the runtime after completion. Further heavy local inference remains blocked fail-closed.",
        fr: "Le tour ANEMLL automatique n’a pas pu décharger le runtime en toute sécurité après son exécution. Toute nouvelle inférence locale lourde reste bloquée en mode fail-closed."
      )
    }
  }
}

/// Concrete end-of-turn cleanup used by the future automatic ModelProfile
/// executor. The automatic execution entry remains disabled on the Build-42
/// safety branch; this coordinator is staged and independently testable first.
public struct AutomaticRuntimeResidencyCoordinator: Sendable {
  private let shutdownANEMLL: @Sendable () async -> Bool

  public init(
    shutdownANEMLL: @escaping @Sendable () async -> Bool = {
      await ANEMLLPersistentRuntimeService.shared.shutdown()
    }
  ) {
    self.shutdownANEMLL = shutdownANEMLL
  }

  public func finalize(
    action: AutomaticRuntimeResidencyAction
  ) async throws {
    switch action {
    case .evictANEMLLAfterTurn:
      guard await shutdownANEMLL() else {
        throw AutomaticRuntimeResidencyCleanupError.anemllExitUnconfirmed
      }
    case .none,
      .preserveUserConfiguration,
      .shortOllamaKeepAlive,
      .observeOnly:
      return
    }
  }
}
