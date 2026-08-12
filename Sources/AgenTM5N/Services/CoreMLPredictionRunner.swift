import CoreML
import Foundation

/// Serial Core ML prediction engine with an in-process model cache.
///
/// Xcode 27 exposes async Core ML entry points with strict Sendability rules,
/// while `MLModel`, `MLFeatureValue`, and `MLFeatureProvider` remain reference
/// types that should not be transferred between concurrency regions. AgenTM5N
/// therefore keeps loading, the cache, feature construction, synchronous
/// prediction and optional stateful sessions on one dedicated background queue.
/// Only URLs/JSON input, session identifiers and the Sendable result cross the
/// async boundary.
public final class CoreMLPredictionRunner: @unchecked Sendable {
  public static let shared = CoreMLPredictionRunner()

  private let queue = DispatchQueue(
    label: "AgenTM5N.CoreMLPredictionRunner",
    qos: .userInitiated
  )
  private var loadedModels: [String: MLModel] = [:]
  private var sessionStates: [String: AnyObject] = [:]

  public init() {}

  public func predict(
    compiledURL: URL,
    jsonInput: String,
    sessionID: String? = nil,
    resetSession: Bool = false
  ) async throws -> CoreMLPredictionResult {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          continuation.resume(
            returning: try predictOnQueue(
              compiledURL: compiledURL,
              jsonInput: jsonInput,
              sessionID: sessionID,
              resetSession: resetSession
            )
          )
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func resetSession(
    compiledURL: URL,
    sessionID: String
  ) async {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        sessionStates.removeValue(
          forKey: sessionKey(compiledURL: compiledURL, sessionID: sessionID)
        )
        continuation.resume()
      }
    }
  }

  public func clearCache() async {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        loadedModels.removeAll(keepingCapacity: false)
        sessionStates.removeAll(keepingCapacity: false)
        continuation.resume()
      }
    }
  }

  private func predictOnQueue(
    compiledURL: URL,
    jsonInput: String,
    sessionID: String?,
    resetSession: Bool
  ) throws -> CoreMLPredictionResult {
    dispatchPrecondition(condition: .onQueue(queue))

    guard let data = jsonInput.data(using: .utf8) else {
      throw CoreMLServiceError.invalidJSON
    }

    let values: [String: JSONValue]
    do {
      values = try JSONDecoder().decode([String: JSONValue].self, from: data)
    } catch {
      throw CoreMLServiceError.invalidJSON
    }

    let model = try cachedModelOnQueue(at: compiledURL)

    var featureValues: [String: MLFeatureValue] = [:]
    for (name, description) in model.modelDescription.inputDescriptionsByName {
      guard let value = values[name] else { continue }
      featureValues[name] = try Self.makeFeatureValue(
        value,
        name: name,
        description: description
      )
    }

    let input = PredictionFeatureProvider(values: featureValues)
    let startedAt = ContinuousClock().now

    let output: any MLFeatureProvider
    if #available(macOS 15.0, *),
      !model.modelDescription.stateDescriptionsByName.isEmpty
    {
      // Generic calls remain isolated by default. Supplying a sessionID creates
      // an explicit stateful Core ML session and retains MLState/KV-style model
      // buffers across calls. This is the substrate required for later
      // tokenizer-aware autoregressive language-model generation.
      let state: MLState
      if let sessionID,
        !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        let key = sessionKey(compiledURL: compiledURL, sessionID: sessionID)
        if resetSession {
          sessionStates.removeValue(forKey: key)
        }
        if let existing = sessionStates[key] as? MLState {
          state = existing
        } else {
          let created = model.makeState()
          sessionStates[key] = created
          state = created
        }
      } else {
        state = model.makeState()
      }
      output = try model.prediction(from: input, using: state)
    } else {
      output = try model.prediction(from: input)
    }

    let elapsed = startedAt.duration(to: ContinuousClock().now)

    var resultValues: [String: String] = [:]
    for name in output.featureNames.sorted() {
      guard let value = output.featureValue(for: name) else { continue }
      resultValues[name] = Self.describe(value)
    }

    return CoreMLPredictionResult(
      values: resultValues,
      durationMilliseconds: Self.milliseconds(from: elapsed)
    )
  }

  private func cachedModelOnQueue(at url: URL) throws -> MLModel {
    dispatchPrecondition(condition: .onQueue(queue))
    let mode = CoreMLRuntimePolicyStore.currentMode
    let key = "\(url.standardizedFileURL.path)|\(mode.rawValue)"
    if let existing = loadedModels[key] {
      return existing
    }

    // Remove models created with another compute policy. This keeps memory
    // bounded and guarantees a policy switch actually rebuilds Core ML's
    // execution plan rather than reusing an incompatible cached instance.
    loadedModels.removeAll(keepingCapacity: false)
    sessionStates.removeAll(keepingCapacity: false)

    let configuration = MLModelConfiguration()
    configuration.computeUnits = mode.computeUnits
    let model = try MLModel(contentsOf: url, configuration: configuration)
    loadedModels[key] = model
    return model
  }

  private func sessionKey(
    compiledURL: URL,
    sessionID: String
  ) -> String {
    "\(compiledURL.standardizedFileURL.path)|\(CoreMLRuntimePolicyStore.currentMode.rawValue)|\(sessionID)"
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
