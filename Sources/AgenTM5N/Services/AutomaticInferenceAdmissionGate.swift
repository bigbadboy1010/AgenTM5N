import Darwin
import Foundation

public enum AutomaticThermalState: String, Codable, Equatable, Sendable {
  case nominal
  case fair
  case serious
  case critical

  public init(_ state: ProcessInfo.ThermalState) {
    switch state {
    case .nominal:
      self = .nominal
    case .fair:
      self = .fair
    case .serious:
      self = .serious
    case .critical:
      self = .critical
    @unknown default:
      self = .critical
    }
  }
}

public struct AutomaticResourceSnapshot: Equatable, Sendable {
  public let thermalState: AutomaticThermalState
  public let physicalMemoryMB: Int
  public let availableMemoryMB: Int?
  public let swapUsedMB: Int?
  public let capturedAt: Date

  public init(
    thermalState: AutomaticThermalState,
    physicalMemoryMB: Int,
    availableMemoryMB: Int?,
    swapUsedMB: Int?,
    capturedAt: Date = Date()
  ) {
    self.thermalState = thermalState
    self.physicalMemoryMB = max(0, physicalMemoryMB)
    self.availableMemoryMB = availableMemoryMB.map { max(0, $0) }
    self.swapUsedMB = swapUsedMB.map { max(0, $0) }
    self.capturedAt = capturedAt
  }
}

public struct AutomaticInferenceAdmissionPolicy: Equatable, Sendable {
  public let reserveMemoryMB: Int
  public let minimumFreeMemoryFraction: Double
  public let maximumSwapUsedMB: Int

  public init(
    reserveMemoryMB: Int = 2_048,
    minimumFreeMemoryFraction: Double = 0.20,
    maximumSwapUsedMB: Int = 2_048
  ) {
    self.reserveMemoryMB = max(512, min(reserveMemoryMB, 65_536))
    self.minimumFreeMemoryFraction = max(0.05, min(minimumFreeMemoryFraction, 0.50))
    self.maximumSwapUsedMB = max(0, min(maximumSwapUsedMB, 65_536))
  }

  public static let conservative = AutomaticInferenceAdmissionPolicy()

  public func effectiveReserveMemoryMB(physicalMemoryMB: Int) -> Int {
    let fractionalReserve = Int(
      (Double(max(0, physicalMemoryMB)) * minimumFreeMemoryFraction).rounded(.up)
    )
    return max(reserveMemoryMB, fractionalReserve)
  }
}

public enum AutomaticInferenceAdmissionError: LocalizedError, Equatable {
  case thermalPressure(AutomaticThermalState)
  case monitoringUnavailable(String)
  case swapPressure(usedMB: Int, limitMB: Int)
  case missingMemoryEstimate(ModelProfileRuntime)
  case insufficientMemory(requiredMB: Int, availableMB: Int, reserveMB: Int)

  public var errorDescription: String? {
    switch self {
    case .thermalPressure(let state):
      return L10n.text(
        de: "Automatische lokale Inferenz wurde wegen thermischer Belastung (\(state.rawValue)) blockiert.",
        en: "Automatic local inference was blocked because of thermal pressure (\(state.rawValue)).",
        fr: "L’inférence locale automatique a été bloquée en raison de la pression thermique (\(state.rawValue))."
      )
    case .monitoringUnavailable(let metric):
      return L10n.text(
        de: "Automatische lokale Inferenz wurde blockiert, weil die Ressourcenmetrik \(metric) nicht zuverlässig verfügbar ist.",
        en: "Automatic local inference was blocked because resource metric \(metric) is not reliably available.",
        fr: "L’inférence locale automatique a été bloquée car la métrique de ressources \(metric) n’est pas disponible de manière fiable."
      )
    case .swapPressure(let usedMB, let limitMB):
      return L10n.text(
        de: "Automatische lokale Inferenz wurde blockiert: \(usedMB) MB Swap sind belegt; das Sicherheitslimit liegt bei \(limitMB) MB.",
        en: "Automatic local inference was blocked: \(usedMB) MB of swap is in use; the safety limit is \(limitMB) MB.",
        fr: "L’inférence locale automatique a été bloquée : \(usedMB) Mo de swap sont utilisés ; la limite de sécurité est de \(limitMB) Mo."
      )
    case .missingMemoryEstimate(let runtime):
      return L10n.text(
        de: "Für die automatische lokale Runtime \(runtime.displayName) fehlt eine Speicherschätzung. Der Start wird fail-closed blockiert.",
        en: "Automatic local runtime \(runtime.displayName) has no memory estimate. Startup is blocked fail-closed.",
        fr: "Le runtime local automatique \(runtime.displayName) ne dispose d’aucune estimation mémoire. Le démarrage est bloqué en mode fail-closed."
      )
    case .insufficientMemory(let requiredMB, let availableMB, let reserveMB):
      return L10n.text(
        de: "Automatische lokale Inferenz benötigt mindestens \(requiredMB) MB verfügbaren Speicher inklusive \(reserveMB) MB Reserve; verfügbar sind \(availableMB) MB.",
        en: "Automatic local inference requires at least \(requiredMB) MB of available memory including a \(reserveMB) MB reserve; \(availableMB) MB is available.",
        fr: "L’inférence locale automatique nécessite au moins \(requiredMB) Mo de mémoire disponible, dont \(reserveMB) Mo de réserve ; \(availableMB) Mo sont disponibles."
      )
    }
  }
}

/// Admission boundary for future automatic ModelProfile execution.
///
/// Manual provider execution is deliberately not passed through this gate. The
/// policy exists to prevent an automatic route from starting a heavy local
/// runtime while the machine is already thermally constrained, swapping
/// heavily, or unable to satisfy the profile's declared memory requirement.
public enum AutomaticInferenceAdmissionGate {
  public static func validate(
    profile: ModelProfile,
    snapshot: AutomaticResourceSnapshot?,
    policy: AutomaticInferenceAdmissionPolicy = .conservative
  ) throws {
    guard profile.runtime.isLocal else { return }
    guard let snapshot else {
      throw AutomaticInferenceAdmissionError.monitoringUnavailable("resource snapshot")
    }

    switch snapshot.thermalState {
    case .nominal, .fair:
      break
    case .serious, .critical:
      throw AutomaticInferenceAdmissionError.thermalPressure(snapshot.thermalState)
    }

    guard let swapUsedMB = snapshot.swapUsedMB else {
      throw AutomaticInferenceAdmissionError.monitoringUnavailable("swap")
    }
    guard swapUsedMB <= policy.maximumSwapUsedMB else {
      throw AutomaticInferenceAdmissionError.swapPressure(
        usedMB: swapUsedMB,
        limitMB: policy.maximumSwapUsedMB
      )
    }

    guard let availableMemoryMB = snapshot.availableMemoryMB else {
      throw AutomaticInferenceAdmissionError.monitoringUnavailable("available memory")
    }

    let reserveMB = policy.effectiveReserveMemoryMB(
      physicalMemoryMB: snapshot.physicalMemoryMB
    )

    let estimatedMemoryMB: Int
    if let estimate = profile.estimatedMemoryMB {
      estimatedMemoryMB = estimate
    } else if profile.runtime == .appleFoundationModels {
      // Apple owns the Foundation Models residency lifecycle. We cannot assign a
      // meaningful process-level model estimate, but still require the system
      // reserve, swap, and thermal gates above.
      estimatedMemoryMB = 0
    } else {
      throw AutomaticInferenceAdmissionError.missingMemoryEstimate(profile.runtime)
    }

    let requiredMemoryMB = estimatedMemoryMB + reserveMB
    guard availableMemoryMB >= requiredMemoryMB else {
      throw AutomaticInferenceAdmissionError.insufficientMemory(
        requiredMB: requiredMemoryMB,
        availableMB: availableMemoryMB,
        reserveMB: reserveMB
      )
    }
  }
}

public enum AutomaticSystemResourceSampler {
  public static func capture() -> AutomaticResourceSnapshot {
    AutomaticResourceSnapshot(
      thermalState: AutomaticThermalState(ProcessInfo.processInfo.thermalState),
      physicalMemoryMB: megabytes(ProcessInfo.processInfo.physicalMemory),
      availableMemoryMB: availableMemoryMB(),
      swapUsedMB: swapUsedMB()
    )
  }

  private static func availableMemoryMB() -> Int? {
    var pageSize: vm_size_t = 0
    let host = mach_host_self()
    guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }

    var statistics = vm_statistics64()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &statistics) { pointer in
      pointer.withMemoryRebound(
        to: integer_t.self,
        capacity: Int(count)
      ) { rebound in
        host_statistics64(host, HOST_VM_INFO64, rebound, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }

    let availablePages = UInt64(statistics.free_count)
      + UInt64(statistics.inactive_count)
      + UInt64(statistics.speculative_count)
    let availableBytes = availablePages * UInt64(pageSize)
    return megabytes(availableBytes)
  }

  private static func swapUsedMB() -> Int? {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
    guard result == 0 else { return nil }
    return megabytes(usage.xsu_used)
  }

  private static func megabytes<T: BinaryInteger>(_ bytes: T) -> Int {
    let value = UInt64(clamping: bytes)
    let megabytes = value / 1_048_576
    return megabytes > UInt64(Int.max) ? Int.max : Int(megabytes)
  }
}
