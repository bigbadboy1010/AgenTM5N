import CoreML
import Foundation

public enum CoreMLComputeMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case automatic
  case cpuOnly
  case cpuAndGPU
  case neuralEnginePreferred

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .automatic:
      return L10n.text(
        de: "Automatisch",
        en: "Automatic",
        fr: "Automatique"
      )
    case .cpuOnly:
      return L10n.text(
        de: "Nur CPU",
        en: "CPU only",
        fr: "CPU uniquement"
      )
    case .cpuAndGPU:
      return L10n.text(
        de: "CPU + GPU",
        en: "CPU + GPU",
        fr: "CPU + GPU"
      )
    case .neuralEnginePreferred:
      return L10n.text(
        de: "Neural Engine bevorzugt",
        en: "Neural Engine preferred",
        fr: "Neural Engine préféré"
      )
    }
  }

  public var explanation: String {
    switch self {
    case .automatic:
      return L10n.text(
        de: "Core ML darf CPU, GPU und Apple Neural Engine verwenden und entscheidet pro Operator über die Ausführung.",
        en: "Core ML may use CPU, GPU, and Apple Neural Engine and chooses execution per operator.",
        fr: "Core ML peut utiliser le CPU, le GPU et l’Apple Neural Engine et choisit l’exécution par opérateur."
      )
    case .cpuOnly:
      return L10n.text(
        de: "Core ML wird auf die CPU beschränkt. Dieser Modus dient primär als Diagnose- und Vergleichsbasis.",
        en: "Core ML is restricted to the CPU. This mode is mainly useful as a diagnostic and comparison baseline.",
        fr: "Core ML est limité au CPU. Ce mode sert surtout de référence de diagnostic et de comparaison."
      )
    case .cpuAndGPU:
      return L10n.text(
        de: "Core ML darf CPU und GPU verwenden; die Neural Engine ist für diese Ausführung ausgeschlossen.",
        en: "Core ML may use CPU and GPU; the Neural Engine is excluded for this execution.",
        fr: "Core ML peut utiliser le CPU et le GPU ; le Neural Engine est exclu pour cette exécution."
      )
    case .neuralEnginePreferred:
      return L10n.text(
        de: "Core ML darf CPU und Apple Neural Engine verwenden; die GPU ist ausgeschlossen. Das ist kein ANE-Only-Modus: nicht unterstützte Operatoren können auf der CPU laufen.",
        en: "Core ML may use CPU and Apple Neural Engine; the GPU is excluded. This is not ANE-only: unsupported operators may run on the CPU.",
        fr: "Core ML peut utiliser le CPU et l’Apple Neural Engine ; le GPU est exclu. Ce n’est pas un mode ANE uniquement : les opérateurs non pris en charge peuvent s’exécuter sur le CPU."
      )
    }
  }

  public var computeUnits: MLComputeUnits {
    switch self {
    case .automatic:
      return .all
    case .cpuOnly:
      return .cpuOnly
    case .cpuAndGPU:
      return .cpuAndGPU
    case .neuralEnginePreferred:
      return .cpuAndNeuralEngine
    }
  }

  public var computePolicyDescription: String {
    switch self {
    case .automatic:
      return L10n.text(
        de: "Automatisch (CPU + GPU + Neural Engine)",
        en: "Automatic (CPU + GPU + Neural Engine)",
        fr: "Automatique (CPU + GPU + Neural Engine)"
      )
    case .cpuOnly:
      return L10n.text(
        de: "Nur CPU",
        en: "CPU only",
        fr: "CPU uniquement"
      )
    case .cpuAndGPU:
      return L10n.text(
        de: "CPU + GPU (Neural Engine ausgeschlossen)",
        en: "CPU + GPU (Neural Engine excluded)",
        fr: "CPU + GPU (Neural Engine exclu)"
      )
    case .neuralEnginePreferred:
      return L10n.text(
        de: "CPU + Neural Engine (GPU ausgeschlossen)",
        en: "CPU + Neural Engine (GPU excluded)",
        fr: "CPU + Neural Engine (GPU exclu)"
      )
    }
  }
}

public enum CoreMLRuntimePolicyStore {
  private static let defaultsKey = "AgenTM5N.CoreMLComputeMode"

  public static var currentMode: CoreMLComputeMode {
    guard
      let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
      let mode = CoreMLComputeMode(rawValue: rawValue)
    else {
      return .automatic
    }
    return mode
  }

  public static func set(_ mode: CoreMLComputeMode) {
    UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
  }

  public static var computeUnits: MLComputeUnits {
    currentMode.computeUnits
  }

  public static var computePolicyDescription: String {
    currentMode.computePolicyDescription
  }
}
