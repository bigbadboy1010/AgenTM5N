import CoreML
import Foundation

public enum CoreMLServiceError: LocalizedError {
  case modelNotLoaded
  case invalidJSON
  case unsupportedInputValue(String)

  public var errorDescription: String? {
    switch self {
    case .modelNotLoaded:
      "Es wurde noch kein Core-ML-Modell geladen."
    case .invalidJSON:
      "Die Prediction-Eingabe muss ein JSON-Objekt mit numerischen Werten sein."
    case .unsupportedInputValue(let key):
      "Der Wert für \(key) ist nicht numerisch."
    }
  }
}

public actor CoreMLService {
  private var model: MLModel?
  private var descriptor: CoreMLModelDescriptor?

  public init() {}

  public func loadModel(sourceURL: URL) throws -> CoreMLModelDescriptor {
    let compiledURL: URL
    if sourceURL.pathExtension.lowercased() == "mlmodelc" {
      compiledURL = sourceURL
    } else {
      compiledURL = try MLModel.compileModel(at: sourceURL)
    }

    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuAndNeuralEngine
    let loadedModel = try MLModel(contentsOf: compiledURL, configuration: configuration)
    let inputs = loadedModel.modelDescription.inputDescriptionsByName
      .map { name, description in
        "\(name) [\(description.type)]"
      }
      .sorted()
    let outputs = loadedModel.modelDescription.outputDescriptionsByName
      .map { name, description in
        "\(name) [\(description.type)]"
      }
      .sorted()

    let descriptor = CoreMLModelDescriptor(
      sourceURL: sourceURL,
      compiledURL: compiledURL,
      inputs: inputs,
      outputs: outputs,
      computeUnits: "CPU + Apple Neural Engine"
    )
    self.model = loadedModel
    self.descriptor = descriptor
    return descriptor
  }

  public func currentDescriptor() -> CoreMLModelDescriptor? {
    descriptor
  }

  public func predict(jsonInput: String) throws -> CoreMLPredictionResult {
    guard let model else {
      throw CoreMLServiceError.modelNotLoaded
    }
    guard let data = jsonInput.data(using: .utf8) else {
      throw CoreMLServiceError.invalidJSON
    }
    let numericValues: [String: Double]
    do {
      numericValues = try JSONDecoder().decode([String: Double].self, from: data)
    } catch {
      throw CoreMLServiceError.invalidJSON
    }

    let input = NumericFeatureProvider(values: numericValues)
    let clock = ContinuousClock()
    let startedAt = clock.now
    let output = try model.prediction(from: input)
    let elapsed = startedAt.duration(to: clock.now)

    var values: [String: String] = [:]
    for name in output.featureNames.sorted() {
      guard let value = output.featureValue(for: name) else { continue }
      values[name] = Self.describe(value)
    }

    return CoreMLPredictionResult(
      values: values,
      durationMilliseconds: Self.milliseconds(from: elapsed)
    )
  }

  private static func describe(_ value: MLFeatureValue) -> String {
    switch value.type {
    case .double:
      return String(value.doubleValue)
    case .int64:
      return String(value.int64Value)
    case .string:
      return value.stringValue
    case .multiArray:
      guard let array = value.multiArrayValue else { return "MultiArray(nil)" }
      return "MultiArray shape=\(array.shape) dataType=\(array.dataType.rawValue)"
    case .dictionary:
      return String(describing: value.dictionaryValue)
    case .image:
      guard let image = value.imageBufferValue else { return "Image(nil)" }
      return "Image \(CVPixelBufferGetWidth(image))×\(CVPixelBufferGetHeight(image))"
    case .sequence:
      return String(describing: value.sequenceValue)
    case .state:
      return "MLState"
    case .invalid:
      return "Ungültiger Feature-Wert"
    @unknown default:
      return String(describing: value)
    }
  }

  private static func milliseconds(from duration: Duration) -> Double {
    let components = duration.components
    let seconds = Double(components.seconds)
    let attoseconds = Double(components.attoseconds)
    return seconds * 1_000 + attoseconds / 1_000_000_000_000_000
  }
}

private final class NumericFeatureProvider: NSObject, MLFeatureProvider {
  private let values: [String: MLFeatureValue]

  init(values: [String: Double]) {
    self.values = values.mapValues(MLFeatureValue.init(double:))
    super.init()
  }

  var featureNames: Set<String> {
    Set(values.keys)
  }

  func featureValue(for featureName: String) -> MLFeatureValue? {
    values[featureName]
  }
}
