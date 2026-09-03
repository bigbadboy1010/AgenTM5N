import Foundation

/// Heavy local inference paths that can materially consume unified memory or
/// compute during an active inference turn. A resident server process alone is
/// not treated as an active lease; residency is tracked separately in the next
/// Phase-2 step.
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

  public init?(
    providerKind: ProviderKind,
    localInferenceRuntime: LocalInferenceRuntime
  ) {
    switch providerKind {
    case .ollamaCloud:
      return nil
    case .appleOnDevice:
      self = .appleFoundationModels
    case .ollamaLocal:
      switch localInferenceRuntime {
      case .ollama:
        self = .ollamaLocal
      case .mlxServer:
        self = .mlx
      case .anemll:
        self = .anemll
      }
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
  public let staleAfterSeconds: Int
  public let capturedAt: Date

  public init(
    activeLease: InferenceResourceLease?,
    staleAfterSeconds: Int,
    capturedAt: Date = Date()
  ) {
    self.activeLease = activeLease
    self.staleAfterSeconds = staleAfterSeconds
    self.capturedAt = capturedAt
  }

  public var isBusy: Bool { activeLease != nil }

  public var requiresRecovery: Bool {
    guard let activeLease else { return false }
    return capturedAt.timeIntervalSince(activeLease.startedAt)
      >= Double(staleAfterSeconds)
  }
}

public enum InferenceResourceGovernorError: LocalizedError, Equatable {
  case busy(active: HeavyInferenceRuntime, requested: HeavyInferenceRuntime)
  case recoveryRequired(active: HeavyInferenceRuntime, ageSeconds: Int)

  public var errorDescription: String? {
    switch self {
    case .busy(let active, let requested):
      return L10n.text(
        de: "Ein schwerer lokaler KI-Turn (\(active.rawValue)) läuft bereits. \(requested.rawValue) wird nicht parallel gestartet.",
        en: "A heavy local AI turn (\(active.rawValue)) is already running. \(requested.rawValue) will not be started in parallel.",
        fr: "Un tour d’inférence local lourd (\(active.rawValue)) est déjà actif. \(requested.rawValue) ne sera pas démarré en parallèle."
      )
    case .recoveryRequired(let active, let ageSeconds):
      return L10n.text(
        de: "Der lokale KI-Turn \(active.rawValue) hält die Ressourcen seit \(ageSeconds) Sekunden. Aus Sicherheitsgründen wird keine zweite schwere Runtime gestartet, bis der laufende Turn bereinigt wurde.",
        en: "The local AI turn \(active.rawValue) has held resources for \(ageSeconds) seconds. For safety, no second heavy runtime will start until the active turn has been cleaned up.",
        fr: "Le tour d’inférence local \(active.rawValue) conserve les ressources depuis \(ageSeconds) secondes. Par sécurité, aucun second runtime lourd ne sera démarré avant le nettoyage du tour actif."
      )
    }
  }
}

/// Serializes active heavy local inference turns across routing layers.
///
/// The governor intentionally does not queue callers and never auto-expires an
/// active lease. Automatically stealing an old lease could create exactly the
/// overlap this guard is designed to prevent if the original runtime is still
/// computing. Callers use `withLease` so success, error, and cancellation all
/// release the exact lease in one structured scope. ANEMLL is the one special
/// cleanup case: if its helper cannot confirm exit even after SIGKILL, release
/// deliberately retains the lease so a second heavy runtime cannot start.
public actor InferenceResourceGovernor {
  public static let shared = InferenceResourceGovernor()

  private var activeLease: InferenceResourceLease?
  private let staleAfterSeconds: Int
  private let now: @Sendable () -> Date
  private let anemllRequiresRecovery: @Sendable () async -> Bool

  public init(
    staleAfterSeconds: Int = 330,
    now: @escaping @Sendable () -> Date = Date.init,
    anemllRequiresRecovery: @escaping @Sendable () async -> Bool = {
      ANEMLLPersistentRuntimeService.shared.requiresRecovery()
    }
  ) {
    self.staleAfterSeconds = max(30, min(staleAfterSeconds, 3_600))
    self.now = now
    self.anemllRequiresRecovery = anemllRequiresRecovery
  }

  public func withLease<T: Sendable>(
    runtime: HeavyInferenceRuntime,
    ownerID: UUID,
    operation: @Sendable () async throws -> T
  ) async throws -> T {
    let lease = try acquire(runtime: runtime, ownerID: ownerID)
    do {
      let result = try await operation()
      await release(lease)
      return result
    } catch {
      await release(lease)
      throw error
    }
  }

  func acquire(
    runtime: HeavyInferenceRuntime,
    ownerID: UUID
  ) throws -> InferenceResourceLease {
    if let activeLease {
      let age = max(0, Int(now().timeIntervalSince(activeLease.startedAt)))
      if age >= staleAfterSeconds {
        throw InferenceResourceGovernorError.recoveryRequired(
          active: activeLease.runtime,
          ageSeconds: age
        )
      }
      throw InferenceResourceGovernorError.busy(
        active: activeLease.runtime,
        requested: runtime
      )
    }

    let lease = InferenceResourceLease(
      runtime: runtime,
      ownerID: ownerID,
      startedAt: now()
    )
    activeLease = lease
    return lease
  }

  /// Releases only the exact lease and owner that are currently active. A stale
  /// task may never unlock a newer execution by presenting an old token.
  ///
  /// For ANEMLL, an unconfirmed helper shutdown is treated as a hard residency
  /// uncertainty. The lease remains active until process recovery is confirmed
  /// rather than allowing another heavy runtime to overlap unknown model memory.
  func release(_ lease: InferenceResourceLease) async {
    guard activeLease?.id == lease.id,
      activeLease?.ownerID == lease.ownerID
    else { return }

    if lease.runtime == .anemll,
      await anemllRequiresRecovery()
    {
      return
    }

    activeLease = nil
  }

  public func snapshot() -> InferenceResourceSnapshot {
    InferenceResourceSnapshot(
      activeLease: activeLease,
      staleAfterSeconds: staleAfterSeconds,
      capturedAt: now()
    )
  }
}

/// Conservative limits used only for future automatic model-profile routing.
/// Manual provider execution keeps its existing user-configured limits.
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

  public static let `conservative` = AutomaticInferenceBudget()

  public static func automatic(
    runtime: ModelProfileRuntime,
    contextWindow: Int
  ) -> AutomaticInferenceBudget {
    let context = max(128, contextWindow)
    let rounds: Int
    if context >= 8_192 {
      rounds = 4
    } else if context >= 2_048 {
      rounds = 2
    } else {
      rounds = 1
    }

    let baseTimeout = max(45, min(180, context / 8 + 30))
    let timeout: Int
    switch runtime {
    case .anemll:
      timeout = min(baseTimeout, context <= 1_024 ? 45 : 120)
    case .appleFoundationModels:
      timeout = min(baseTimeout, 60)
    case .mlx, .ollamaLocal:
      timeout = min(baseTimeout, 120)
    case .ollamaCloud:
      timeout = min(max(baseTimeout, 120), 180)
    }

    return AutomaticInferenceBudget(
      timeoutSeconds: timeout,
      maximumToolRounds: rounds
    )
  }

  public mutating func normalize() {
    timeoutSeconds = max(30, min(timeoutSeconds, 180))
    maximumToolRounds = max(1, min(maximumToolRounds, 8))
  }
}
