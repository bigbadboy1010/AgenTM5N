import Foundation

/// Heavy local inference paths that can materially consume unified memory,
/// compute, or a persistent helper/server process on the target Mac.
public enum HeavyInferenceRuntime: String, Codable, CaseIterable, Sendable {
  case ollamaLocal
  case mlx
  case anemll
  case appleFoundationModels

  public init?(modelProfileRuntime: ModelProfileRuntime) {
    switch modelProfileRuntime {
    case .ollamaLocal:
      self = .ollamaLocal
    case .mlx:
      self = .mlx
    case .anemll:
      self = .anemll
    case .appleFoundationModels:
      self = .appleFoundationModels
    case .ollamaCloud:
      return nil
    }
  }
}

public struct InferenceResourceLease: Equatable, Sendable {
  public let id: UUID
  public let runtime: HeavyInferenceRuntime
  public let ownerID: UUID
  public let startedAt: Date

  public init(
    id: UUID = UUID(),
    runtime: HeavyInferenceRuntime,
    ownerID: UUID,
    startedAt: Date = Date()
  ) {
    self.id = id
    self.runtime = runtime
    self.ownerID = ownerID
    self.startedAt = startedAt
  }
}

public struct InferenceResourceSnapshot: Equatable, Sendable {
  public let activeLease: InferenceResourceLease?

  public init(activeLease: InferenceResourceLease?) {
    self.activeLease = activeLease
  }

  public var isBusy: Bool { activeLease != nil }
}

public enum InferenceResourceGovernorError: LocalizedError, Equatable {
  case busy(active: HeavyInferenceRuntime, requested: HeavyInferenceRuntime)

  public var errorDescription: String? {
    switch self {
    case .busy(let active, let requested):
      return L10n.text(
        de: "Ein schwerer lokaler KI-Pfad (\(active.rawValue)) läuft bereits. \(requested.rawValue) wird nicht parallel gestartet.",
        en: "A heavy local AI route (\(active.rawValue)) is already running. \(requested.rawValue) will not be started in parallel.",
        fr: "Un chemin d’inférence local lourd (\(active.rawValue)) est déjà actif. \(requested.rawValue) ne sera pas démarré en parallèle."
      )
    }
  }
}

/// Serializes heavy local inference runtimes across routing layers.
///
/// The governor intentionally does not queue callers. A queued heavy-runtime
/// request can surprise the user by starting later after the machine has
/// already been under pressure. Callers must fail closed, fall back to a safe
/// route, or explicitly retry after the current lease has ended.
public actor InferenceResourceGovernor {
  public static let shared = InferenceResourceGovernor()

  private var activeLease: InferenceResourceLease?

  public init() {}

  public func acquire(
    runtime: HeavyInferenceRuntime,
    ownerID: UUID
  ) throws -> InferenceResourceLease {
    if let activeLease {
      throw InferenceResourceGovernorError.busy(
        active: activeLease.runtime,
        requested: runtime
      )
    }

    let lease = InferenceResourceLease(
      runtime: runtime,
      ownerID: ownerID
    )
    activeLease = lease
    return lease
  }

  /// Releases only the exact lease that is currently active. A stale task may
  /// never unlock a newer execution by presenting an old token.
  public func release(_ lease: InferenceResourceLease) {
    guard activeLease?.id == lease.id else { return }
    activeLease = nil
  }

  public func snapshot() -> InferenceResourceSnapshot {
    InferenceResourceSnapshot(activeLease: activeLease)
  }
}

/// Conservative execution limits reserved for future automatic model-profile
/// routing. Manual provider execution keeps its existing user-configured limits.
public struct AutomaticInferenceBudget: Equatable, Sendable {
  public var timeoutSeconds: Int
  public var maximumToolRounds: Int

  public init(
    timeoutSeconds: Int = 120,
    maximumToolRounds: Int = 4
  ) {
    self.timeoutSeconds = timeoutSeconds
    self.maximumToolRounds = maximumToolRounds
    normalize()
  }

  public static let conservative = AutomaticInferenceBudget()

  public mutating func normalize() {
    timeoutSeconds = max(30, min(timeoutSeconds, 300))
    maximumToolRounds = max(1, min(maximumToolRounds, 8))
  }
}
