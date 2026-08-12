import CoreML
import Foundation

public enum CoreMLComputeDeviceKind: String, Codable, CaseIterable, Sendable {
  case cpu
  case gpu
  case neuralEngine
  case unknown

  public var displayName: String {
    switch self {
    case .cpu: "CPU"
    case .gpu: "GPU"
    case .neuralEngine: "Apple Neural Engine"
    case .unknown: "Unbekannt"
    }
  }
}

public struct CoreMLComputeOperationSummary: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let name: String
  public let preferredDevice: CoreMLComputeDeviceKind
  public let supportedDevices: [CoreMLComputeDeviceKind]
  public let estimatedWeight: Double?

  public init(
    id: String,
    name: String,
    preferredDevice: CoreMLComputeDeviceKind,
    supportedDevices: [CoreMLComputeDeviceKind],
    estimatedWeight: Double?
  ) {
    self.id = id
    self.name = name
    self.preferredDevice = preferredDevice
    self.supportedDevices = supportedDevices
    self.estimatedWeight = estimatedWeight
  }
}

public struct CoreMLComputePlanReport: Codable, Equatable, Sendable {
  public let modelType: String
  public let computeMode: CoreMLComputeMode
  public let totalOperations: Int
  public let preferredCPUOperations: Int
  public let preferredGPUOperations: Int
  public let preferredNeuralEngineOperations: Int
  public let unknownPreferredOperations: Int
  public let neuralEngineSupportedOperations: Int
  public let cpuEstimatedWeight: Double
  public let gpuEstimatedWeight: Double
  public let neuralEngineEstimatedWeight: Double
  public let unknownEstimatedWeight: Double
  public let availableDevices: [CoreMLComputeDeviceKind]
  public let stateful: Bool
  public let stateFeatureNames: [String]
  public let topOperations: [CoreMLComputeOperationSummary]

  public init(
    modelType: String,
    computeMode: CoreMLComputeMode,
    totalOperations: Int,
    preferredCPUOperations: Int,
    preferredGPUOperations: Int,
    preferredNeuralEngineOperations: Int,
    unknownPreferredOperations: Int,
    neuralEngineSupportedOperations: Int,
    cpuEstimatedWeight: Double,
    gpuEstimatedWeight: Double,
    neuralEngineEstimatedWeight: Double,
    unknownEstimatedWeight: Double,
    availableDevices: [CoreMLComputeDeviceKind],
    stateful: Bool,
    stateFeatureNames: [String],
    topOperations: [CoreMLComputeOperationSummary]
  ) {
    self.modelType = modelType
    self.computeMode = computeMode
    self.totalOperations = totalOperations
    self.preferredCPUOperations = preferredCPUOperations
    self.preferredGPUOperations = preferredGPUOperations
    self.preferredNeuralEngineOperations = preferredNeuralEngineOperations
    self.unknownPreferredOperations = unknownPreferredOperations
    self.neuralEngineSupportedOperations = neuralEngineSupportedOperations
    self.cpuEstimatedWeight = cpuEstimatedWeight
    self.gpuEstimatedWeight = gpuEstimatedWeight
    self.neuralEngineEstimatedWeight = neuralEngineEstimatedWeight
    self.unknownEstimatedWeight = unknownEstimatedWeight
    self.availableDevices = availableDevices
    self.stateful = stateful
    self.stateFeatureNames = stateFeatureNames
    self.topOperations = topOperations
  }

  public var neuralEnginePreferredPercentage: Double {
    guard totalOperations > 0 else { return 0 }
    return Double(preferredNeuralEngineOperations) / Double(totalOperations) * 100
  }

  public var neuralEngineSupportedPercentage: Double {
    guard totalOperations > 0 else { return 0 }
    return Double(neuralEngineSupportedOperations) / Double(totalOperations) * 100
  }
}

public enum CoreMLComputePlanAnalyzerError: LocalizedError {
  case unavailable

  public var errorDescription: String? {
    switch self {
    case .unavailable:
      return L10n.text(
        de: "MLComputePlan ist auf dieser macOS-Version nicht verfügbar.",
        en: "MLComputePlan is not available on this macOS version.",
        fr: "MLComputePlan n’est pas disponible sur cette version de macOS."
      )
    }
  }
}

public enum CoreMLComputePlanAnalyzer {
  public static func analyze(
    compiledURL: URL,
    mode: CoreMLComputeMode = CoreMLRuntimePolicyStore.currentMode
  ) async throws -> CoreMLComputePlanReport {
    guard #available(macOS 15.0, *) else {
      throw CoreMLComputePlanAnalyzerError.unavailable
    }
    return try await analyzeAvailable(compiledURL: compiledURL, mode: mode)
  }

  @available(macOS 15.0, *)
  private static func analyzeAvailable(
    compiledURL: URL,
    mode: CoreMLComputeMode
  ) async throws -> CoreMLComputePlanReport {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = mode.computeUnits

    let plan = try await MLComputePlan.load(
      contentsOf: compiledURL,
      configuration: configuration
    )

    var accumulator = Accumulator()
    inspect(
      structure: plan.modelStructure,
      plan: plan,
      path: "model",
      accumulator: &accumulator
    )

    let model = try await MLModel.load(
      contentsOf: compiledURL,
      configuration: configuration
    )
    let stateNames = model.modelDescription.stateDescriptionsByName.keys.sorted()

    let availableDevices = MLComputeDevice.allComputeDevices
      .map(deviceKind)
      .deduplicated()

    let topOperations = accumulator.operations
      .sorted { lhs, rhs in
        let lhsWeight = lhs.estimatedWeight ?? -1
        let rhsWeight = rhs.estimatedWeight ?? -1
        if lhsWeight == rhsWeight {
          return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhsWeight > rhsWeight
      }
      .prefix(20)

    return CoreMLComputePlanReport(
      modelType: accumulator.modelTypes.isEmpty
        ? "unknown"
        : accumulator.modelTypes.sorted().joined(separator: " + "),
      computeMode: mode,
      totalOperations: accumulator.totalOperations,
      preferredCPUOperations: accumulator.preferredCounts[.cpu, default: 0],
      preferredGPUOperations: accumulator.preferredCounts[.gpu, default: 0],
      preferredNeuralEngineOperations: accumulator.preferredCounts[.neuralEngine, default: 0],
      unknownPreferredOperations: accumulator.preferredCounts[.unknown, default: 0],
      neuralEngineSupportedOperations: accumulator.neuralEngineSupportedOperations,
      cpuEstimatedWeight: accumulator.estimatedWeights[.cpu, default: 0],
      gpuEstimatedWeight: accumulator.estimatedWeights[.gpu, default: 0],
      neuralEngineEstimatedWeight: accumulator.estimatedWeights[.neuralEngine, default: 0],
      unknownEstimatedWeight: accumulator.estimatedWeights[.unknown, default: 0],
      availableDevices: availableDevices,
      stateful: !stateNames.isEmpty,
      stateFeatureNames: stateNames,
      topOperations: Array(topOperations)
    )
  }

  @available(macOS 15.0, *)
  private static func inspect(
    structure: MLModelStructure,
    plan: MLComputePlan,
    path: String,
    accumulator: inout Accumulator
  ) {
    switch structure {
    case .program(let program):
      accumulator.modelTypes.insert("ML Program")
      for functionName in program.functions.keys.sorted() {
        guard let function = program.functions[functionName] else { continue }
        inspect(
          block: function.block,
          plan: plan,
          path: "\(path).\(functionName)",
          accumulator: &accumulator
        )
      }

    case .neuralNetwork(let network):
      accumulator.modelTypes.insert("Neural Network")
      for (index, layer) in network.layers.enumerated() {
        let usage = plan.deviceUsage(for: layer)
        let preferred = usage.map { deviceKind($0.preferred) } ?? .unknown
        let supported = usage?.supported.map(deviceKind).deduplicated() ?? []
        accumulator.record(
          id: "\(path).layer.\(index)",
          name: layer.name.isEmpty ? layer.type : layer.name,
          preferred: preferred,
          supported: supported,
          weight: nil
        )
      }

    case .pipeline(let pipeline):
      accumulator.modelTypes.insert("Pipeline")
      for index in pipeline.subModels.indices {
        let name = index < pipeline.subModelNames.count
          ? pipeline.subModelNames[index]
          : "submodel-\(index)"
        inspect(
          structure: pipeline.subModels[index],
          plan: plan,
          path: "\(path).\(name)",
          accumulator: &accumulator
        )
      }

    case .unsupported:
      accumulator.modelTypes.insert("Unsupported")

    @unknown default:
      accumulator.modelTypes.insert("Unknown")
    }
  }

  @available(macOS 15.0, *)
  private static func inspect(
    block: MLModelStructure.Program.Block,
    plan: MLComputePlan,
    path: String,
    accumulator: inout Accumulator
  ) {
    for (index, operation) in block.operations.enumerated() {
      let usage = plan.deviceUsage(for: operation)
      let preferred = usage.map { deviceKind($0.preferred) } ?? .unknown
      let supported = usage?.supported.map(deviceKind).deduplicated() ?? []
      let weight = plan.estimatedCost(of: operation)?.weight
      let operationPath = "\(path).op.\(index).\(operation.operatorName)"

      accumulator.record(
        id: operationPath,
        name: operation.operatorName,
        preferred: preferred,
        supported: supported,
        weight: weight
      )

      for (blockIndex, nestedBlock) in operation.blocks.enumerated() {
        inspect(
          block: nestedBlock,
          plan: plan,
          path: "\(operationPath).block.\(blockIndex)",
          accumulator: &accumulator
        )
      }
    }
  }

  @available(macOS 15.0, *)
  private static func deviceKind(_ device: MLComputeDevice) -> CoreMLComputeDeviceKind {
    switch device {
    case .cpu:
      return .cpu
    case .gpu:
      return .gpu
    case .neuralEngine:
      return .neuralEngine
    @unknown default:
      return .unknown
    }
  }

  private struct Accumulator {
    var modelTypes: Set<String> = []
    var totalOperations = 0
    var preferredCounts: [CoreMLComputeDeviceKind: Int] = [:]
    var estimatedWeights: [CoreMLComputeDeviceKind: Double] = [:]
    var neuralEngineSupportedOperations = 0
    var operations: [CoreMLComputeOperationSummary] = []

    mutating func record(
      id: String,
      name: String,
      preferred: CoreMLComputeDeviceKind,
      supported: [CoreMLComputeDeviceKind],
      weight: Double?
    ) {
      totalOperations += 1
      preferredCounts[preferred, default: 0] += 1
      if supported.contains(.neuralEngine) {
        neuralEngineSupportedOperations += 1
      }
      if let weight {
        estimatedWeights[preferred, default: 0] += weight
      }
      operations.append(
        CoreMLComputeOperationSummary(
          id: id,
          name: name,
          preferredDevice: preferred,
          supportedDevices: supported,
          estimatedWeight: weight
        )
      )
    }
  }
}

private extension Sequence where Element: Hashable {
  func deduplicated() -> [Element] {
    var seen: Set<Element> = []
    return filter { seen.insert($0).inserted }
  }
}
