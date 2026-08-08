import CoreML
import Foundation

/// Executes one Core ML prediction without transferring `MLModel` or
/// `MLFeatureProvider` instances across the `CoreMLService` actor boundary.
///
/// Xcode 27 exposes prediction as an `@concurrent` async operation. Loading the
/// model and creating the feature provider inside the detached task keeps all
/// non-Sendable Core ML objects in one isolated execution region. Only the
/// compiled model URL, JSON text and the Sendable result cross boundaries.
public enum CoreMLPredictionRunner {
  public static func predict(
    compiledURL: URL,
    jsonInput: String
  ) async throws -> CoreMLPredictionResult {
    try await Task.detached(priority: .userInitiated) {
      guard let data = jsonInput.data(using: .utf8) else {
        throw CoreMLServiceError.invalidJSON
      }

      let values: [String: JSONValue]
      do {
        values = try JSONDecoder().decode([String: JSONValue].self, from: data)
      } catch {
        throw CoreMLServiceError.invalidJSON
      }

      let configuration = MLModelConfiguration()
      configuration.computeUnits = .cpuAndNeuralEngine
      let model = try await MLModel.load(
        contentsOf: compiledURL,
        configuration: configuration
      )

      var featureValues: [String: MLFeatureValue] = [:]
      for (name, description) in model.modelDescription.inputDescriptionsByName {
        guard let value = values[name] else { continue }
        featureValues[name] = try makeFeatureValue(
          value,
          name: name,
          description: description
        )
      }

      let input = PredictionFeatureProvider(values: featureValues)
      let clock = ContinuousClock()
      let startedAt = clock.now
      let output = try await model.prediction(from: input)
      let elapsed = startedAt.duration(to: clock.now)

      var resultValues: [String: String] = [:]
      for name in output.featureNames.sorted() {
        guard let value = output.featureValue(for: name) else { continue }
        resultValues[name] = describe(value)
      }

      return CoreMLPredictionResult(
        values: resultValues,
        durationMilliseconds: milliseconds(from: elapsed)
      )
    }.value
  }

  private static func makeFeatureValue(
    _ value: JSONValue,
    name: String,
    description: MLFeatureDescription
  ) throws -> MLFeatureValue {
    switch (description.type, value) {
    case (.double, .number(let number)):
      return MLFeatureValue(double: number)
    case (.int64, .number(let number)):
      return MLFeatureValue(int64: Int64(number))
    case (.string, .string(let text)):
      return MLFeatureValue(string: text)

    case (.multiArray, .array):
      guard let constraint = description.multiArrayConstraint else {
        throw CoreMLServiceError.inputTypeNotSupported(name: name, type: "MultiArray")
      }
      let numbers = try flattenedNumbers(value, inputName: name)
      let array = try MLMultiArray(
        shape: constraint.shape,
        dataType: constraint.dataType
      )
      guard numbers.count == array.count else {
        throw CoreMLServiceError.inputTypeNotSupported(
          name: name,
          type: "MultiArray erwartet \(array.count) Werte, erhalten \(numbers.count)"
        )
      }
      for index in 0..<numbers.count {
        array[index] = NSNumber(value: numbers[index])
      }
      return MLFeatureValue(multiArray: array)

    case (.image, .string(let path)):
      guard let constraint = description.imageConstraint else {
        throw CoreMLServiceError.inputTypeNotSupported(name: name, type: "Image")
      }
      let expanded = NSString(string: path).expandingTildeInPath
      let url = URL(fileURLWithPath: expanded)
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw CoreMLServiceError.inputTypeNotSupported(
          name: name,
          type: "Image-Datei nicht gefunden: \(path)"
        )
      }
      return try MLFeatureValue(
        imageAt: url,
        constraint: constraint,
        options: nil
      )

    default:
      throw CoreMLServiceError.inputTypeNotSupported(
        name: name,
        type: localizedFeatureType(description.type)
      )
    }
  }

  private static func flattenedNumbers(
    _ value: JSONValue,
    inputName: String
  ) throws -> [Double] {
    switch value {
    case .number(let number):
      return [number]
    case .array(let values):
      return try values.flatMap {
        try flattenedNumbers($0, inputName: inputName)
      }
    default:
      throw CoreMLServiceError.inputTypeNotSupported(
        name: inputName,
        type: "MultiArray benötigt verschachtelte numerische JSON-Arrays"
      )
    }
  }

  private static func localizedFeatureType(_ type: MLFeatureType) -> String {
    switch type {
    case .double:
      return "Double"
    case .int64:
      return "Int64"
    case .string:
      return L10n.text(de: "Text", en: "Text", fr: "Texte")
    case .multiArray:
      return "MultiArray"
    case .dictionary:
      return L10n.text(de: "Wörterbuch", en: "Dictionary", fr: "Dictionnaire")
    case .image:
      return L10n.text(de: "Bild", en: "Image", fr: "Image")
    case .sequence:
      return L10n.text(de: "Sequenz", en: "Sequence", fr: "Séquence")
    case .state:
      return "MLState"
    case .invalid:
      return L10n.text(de: "Ungültig", en: "Invalid", fr: "Invalide")
    @unknown default:
      return String(describing: type)
    }
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
      let previewCount = min(array.count, 16)
      let preview = (0..<previewCount)
        .map { String(describing: array[$0]) }
        .joined(separator: ", ")
      return "MultiArray shape=\(array.shape) dataType=\(array.dataType.rawValue) values=[\(preview)\(array.count > previewCount ? ", …" : "")]"
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
      return L10n.text(
        de: "Ungültiger Feature-Wert",
        en: "Invalid feature value",
        fr: "Valeur de caractéristique invalide"
      )
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

private final class PredictionFeatureProvider: NSObject, MLFeatureProvider {
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
