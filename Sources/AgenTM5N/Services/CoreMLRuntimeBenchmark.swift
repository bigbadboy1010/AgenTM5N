import CoreML
import Foundation

public struct CoreMLRuntimeBenchmarkModeResult: Codable, Equatable, Sendable, Identifiable {
  public var id: String { mode.rawValue }

  public let mode: CoreMLComputeMode
  public let succeeded: Bool
  public let modelLoadMilliseconds: Double
  public let firstPredictionMilliseconds: Double?
  public let warmMeanMilliseconds: Double?
  public let warmP50Milliseconds: Double?
  public let warmP95Milliseconds: Double?
  public let warmRuns: Int
  public let outputSignature: String?
  public let errorDescription: String?

  public init(
    mode: CoreMLComputeMode,
    succeeded: Bool,
    modelLoadMilliseconds: Double,
    firstPredictionMilliseconds: Double?,
    warmMeanMilliseconds: Double?,
    warmP50Milliseconds: Double?,
    warmP95Milliseconds: Double?,
    warmRuns: Int,
    outputSignature: String?,
    errorDescription: String?
  ) {
    self.mode = mode
    self.succeeded = succeeded
    self.modelLoadMilliseconds = modelLoadMilliseconds
    self.firstPredictionMilliseconds = firstPredictionMilliseconds
    self.warmMeanMilliseconds = warmMeanMilliseconds
    self.warmP50Milliseconds = warmP50Milliseconds
    self.warmP95Milliseconds = warmP95Milliseconds
    self.warmRuns = warmRuns
    self.outputSignature = outputSignature
    self.errorDescription = errorDescription
  }
}

public struct CoreMLRuntimeBenchmarkReport: Codable, Equatable, Sendable {
  public let generatedAt: Date
  public let results: [CoreMLRuntimeBenchmarkModeResult]
  public let fastestMode: CoreMLComputeMode?
  public let outputsStructurallyEquivalent: Bool

  public init(
    generatedAt: Date = Date(),
    results: [CoreMLRuntimeBenchmarkModeResult],
    fastestMode: CoreMLComputeMode?,
    outputsStructurallyEquivalent: Bool
  ) {
    self.generatedAt = generatedAt
    self.results = results
    self.fastestMode = fastestMode
    self.outputsStructurallyEquivalent = outputsStructurallyEquivalent
  }
}

public enum CoreMLRuntimeBenchmarkError: LocalizedError {
  case unsupportedInput(name: String, type: String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedInput(let name, let type):
      return L10n.text(
        de: "Runtime-Benchmark kann den Eingang '\(name)' vom Typ \(type) noch nicht automatisch erzeugen.",
        en: "The runtime benchmark cannot yet automatically generate input '\(name)' of type \(type).",
        fr: "Le benchmark d’exécution ne peut pas encore générer automatiquement l’entrée '\(name)' de type \(type)."
      )
    }
  }
}

/// Executes real Core ML predictions under several compute policies.
///
/// Unlike `MLComputePlan`, these timings measure actual `MLModel.prediction`
/// latency. They still do not expose measured CPU/GPU/ANE utilization; device
/// placement remains the responsibility of Core ML and is diagnosed separately
/// by the ANE Model Lab.
public final class CoreMLRuntimeBenchmark: @unchecked Sendable {
  public static let shared = CoreMLRuntimeBenchmark()

  public static let benchmarkModes: [CoreMLComputeMode] = [
    .automatic,
    .cpuAndGPU,
    .neuralEnginePreferred,
  ]

  private let queue = DispatchQueue(
    label: "AgenTM5N.CoreMLRuntimeBenchmark",
    qos: .userInitiated
  )

  public init() {}

  public func run(
    compiledURL: URL,
    warmRuns: Int = 10
  ) async -> CoreMLRuntimeBenchmarkReport {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        let count = max(3, min(warmRuns, 50))
        var results: [CoreMLRuntimeBenchmarkModeResult] = []
        for mode in Self.benchmarkModes {
          results.append(
            runModeOnQueue(
              compiledURL: compiledURL,
              mode: mode,
              warmRuns: count
            )
          )
        }
        continuation.resume(returning: Self.evaluate(results: results))
      }
    }
  }

  public static func evaluate(
    results: [CoreMLRuntimeBenchmarkModeResult]
  ) -> CoreMLRuntimeBenchmarkReport {
    let successful = results.filter {
      $0.succeeded && $0.warmP50Milliseconds != nil
    }
    let fastest = successful.min {
      ($0.warmP50Milliseconds ?? .greatestFiniteMagnitude)
        < ($1.warmP50Milliseconds ?? .greatestFiniteMagnitude)
    }?.mode

    let signatures = Set(successful.compactMap(\.outputSignature))
    let equivalent = !successful.isEmpty
      && successful.allSatisfy { $0.outputSignature != nil }
      && signatures.count == 1

    return CoreMLRuntimeBenchmarkReport(
      results: benchmarkModes.compactMap { mode in
        results.first(where: { $0.mode == mode })
      },
      fastestMode: fastest,
      outputsStructurallyEquivalent: equivalent
    )
  }

  private func runModeOnQueue(
    compiledURL: URL,
    mode: CoreMLComputeMode,
    warmRuns: Int
  ) -> CoreMLRuntimeBenchmarkModeResult {
    dispatchPrecondition(condition: .onQueue(queue))

    let loadStarted = ContinuousClock().now
    do {
      let configuration = MLModelConfiguration()
      configuration.computeUnits = mode.computeUnits
      let model = try MLModel(
        contentsOf: compiledURL,
        configuration: configuration
      )
      let loadMilliseconds = Self.milliseconds(
        from: loadStarted.duration(to: ContinuousClock().now)
      )

      let input = try Self.makeSyntheticInput(for: model)
      let state: AnyObject?
      if #available(macOS 15.0, *),
        !model.modelDescription.stateDescriptionsByName.isEmpty
      {
        state = model.makeState()
      } else {
        state = nil
      }

      let firstStarted = ContinuousClock().now
      let firstOutput = try Self.predict(
        model: model,
        input: input,
        state: state
      )
      let firstMilliseconds = Self.milliseconds(
        from: firstStarted.duration(to: ContinuousClock().now)
      )

      var warmLatencies: [Double] = []
      warmLatencies.reserveCapacity(warmRuns)
      for _ in 0..<warmRuns {
        let started = ContinuousClock().now
        _ = try Self.predict(model: model, input: input, state: state)
        warmLatencies.append(
          Self.milliseconds(
            from: started.duration(to: ContinuousClock().now)
          )
        )
      }

      let sorted = warmLatencies.sorted()
      let mean = warmLatencies.reduce(0, +) / Double(warmLatencies.count)

      return CoreMLRuntimeBenchmarkModeResult(
        mode: mode,
        succeeded: true,
        modelLoadMilliseconds: loadMilliseconds,
        firstPredictionMilliseconds: firstMilliseconds,
        warmMeanMilliseconds: mean,
        warmP50Milliseconds: Self.percentile(sorted, fraction: 0.50),
        warmP95Milliseconds: Self.percentile(sorted, fraction: 0.95),
        warmRuns: warmRuns,
        outputSignature: Self.outputSignature(firstOutput),
        errorDescription: nil
      )
    } catch {
      return CoreMLRuntimeBenchmarkModeResult(
        mode: mode,
        succeeded: false,
        modelLoadMilliseconds: Self.milliseconds(
          from: loadStarted.duration(to: ContinuousClock().now)
        ),
        firstPredictionMilliseconds: nil,
        warmMeanMilliseconds: nil,
        warmP50Milliseconds: nil,
        warmP95Milliseconds: nil,
        warmRuns: 0,
        outputSignature: nil,
        errorDescription: error.localizedDescription
      )
    }
  }

  private static func predict(
    model: MLModel,
    input: any MLFeatureProvider,
    state: AnyObject?
  ) throws -> any MLFeatureProvider {
    if #available(macOS 15.0, *), let state = state as? MLState {
      return try model.prediction(from: input, using: state)
    }
    return try model.prediction(from: input)
  }

  private static func makeSyntheticInput(
    for model: MLModel
  ) throws -> RuntimeBenchmarkFeatureProvider {
    var values: [String: MLFeatureValue] = [:]

    for (name, description) in model.modelDescription.inputDescriptionsByName {
      switch description.type {
      case .double:
        values[name] = MLFeatureValue(double: 0)
      case .int64:
        values[name] = MLFeatureValue(int64: 0)
      case .string:
        values[name] = MLFeatureValue(string: "AgenTM5N benchmark")
      case .multiArray:
        guard let constraint = description.multiArrayConstraint else {
          throw CoreMLRuntimeBenchmarkError.unsupportedInput(
            name: name,
            type: "MultiArray"
          )
        }
        let array = try MLMultiArray(
          shape: constraint.shape,
          dataType: constraint.dataType
        )
        for index in 0..<array.count {
          array[index] = NSNumber(value: 0)
        }

        let normalized = name.lowercased()
          .replacingOccurrences(of: "-", with: "_")
        if normalized.contains("input_ids") || normalized.contains("inputids") {
          if array.count > 0 { array[0] = NSNumber(value: 101) }
          if array.count > 1 { array[1] = NSNumber(value: 102) }
        } else if normalized.contains("attention_mask")
          || normalized.contains("attentionmask")
        {
          if array.count > 0 { array[0] = NSNumber(value: 1) }
          if array.count > 1 { array[1] = NSNumber(value: 1) }
        }
        values[name] = MLFeatureValue(multiArray: array)
      default:
        throw CoreMLRuntimeBenchmarkError.unsupportedInput(
          name: name,
          type: String(describing: description.type)
        )
      }
    }

    return RuntimeBenchmarkFeatureProvider(values: values)
  }

  private static func outputSignature(
    _ output: any MLFeatureProvider
  ) -> String {
    output.featureNames.sorted().map { name in
      guard let value = output.featureValue(for: name) else {
        return "\(name):nil"
      }
      if value.type == .multiArray, let array = value.multiArrayValue {
        return "\(name):multiArray:\(array.shape):\(array.dataType.rawValue)"
      }
      return "\(name):\(value.type.rawValue)"
    }
    .joined(separator: "|")
  }

  private static func percentile(
    _ sortedValues: [Double],
    fraction: Double
  ) -> Double? {
    guard !sortedValues.isEmpty else { return nil }
    if sortedValues.count == 1 { return sortedValues[0] }
    let clamped = max(0, min(fraction, 1))
    let position = clamped * Double(sortedValues.count - 1)
    let lower = Int(position.rounded(.down))
    let upper = Int(position.rounded(.up))
    if lower == upper { return sortedValues[lower] }
    let weight = position - Double(lower)
    return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight
  }

  private static func milliseconds(from duration: Duration) -> Double {
    let components = duration.components
    let seconds = Double(components.seconds)
    let attoseconds = Double(components.attoseconds)
    return seconds * 1_000 + attoseconds / 1_000_000_000_000_000
  }
}

private final class RuntimeBenchmarkFeatureProvider: NSObject, MLFeatureProvider {
  private let values: [String: MLFeatureValue]

  init(values: [String: MLFeatureValue]) {
    self.values = values
    super.init()
  }

  var featureNames: Set<String> {
    Set(values.keys)
  }

  func featureValue(for featureName: String) -> MLFeatureValue? {
    values[featureName]
  }
}
