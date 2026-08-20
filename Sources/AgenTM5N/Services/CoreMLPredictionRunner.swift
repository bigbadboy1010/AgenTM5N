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
  private var sessionModes: [String: CoreMLComputeMode] = [:]

  public init() {}

  public func predict(
    compiledURL: URL,
    jsonInput: String,
    sessionID: String? = nil,
    resetSession: Bool = false
  ) async throws -> CoreMLPredictionResult {
    let route = await CoreMLAdaptiveExecutionPolicy.resolve(
      compiledURL: compiledURL
    )

    return try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          continuation.resume(
            returning: try predictWithFailoverOnQueue(
              compiledURL: compiledURL,
              jsonInput: jsonInput,
              sessionID: sessionID,
              resetSession: resetSession,
              route: route
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
        clearSessionOnQueue(
          compiledURL: compiledURL,
          sessionID: sessionID
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
        sessionModes.removeAll(keepingCapacity: false)
        CoreMLAdaptiveExecutionTelemetry.shared.clear()
        continuation.resume()
      }
    }
  }

  private func predictWithFailoverOnQueue(
    compiledURL: URL,
    jsonInput: String,
    sessionID: String?,
    resetSession: Bool,
    route: CoreMLExecutionRoute
  ) throws -> CoreMLPredictionResult {
    dispatchPrecondition(condition: .onQueue(queue))

    do {
      return try predictOnQueue(
        compiledURL: compiledURL,
        jsonInput: jsonInput,
        sessionID: sessionID,
        resetSession: resetSession,
        route: route
      )
    } catch {
      let primaryError = error
      guard route.allowsAutomaticFailover else {
        throw primaryError
      }

      // A failed specialized execution must not leave a partially mutated
      // MLState session behind. Drop the failed model instance/session state and
      // retry exactly once with Core ML Automatic.
      discardModelOnQueue(at: compiledURL, mode: route.mode)
      if let normalizedSessionID = normalizedSessionID(sessionID) {
        clearSessionOnQueue(
          compiledURL: compiledURL,
          sessionID: normalizedSessionID
        )
      }

      let fallbackRoute = CoreMLAdaptiveExecutionPolicy.automaticFailover(
        from: route,
        error: primaryError
      )

      return try predictOnQueue(
        compiledURL: compiledURL,
        jsonInput: jsonInput,
        sessionID: sessionID,
        resetSession: true,
        route: fallbackRoute
      )
    }
  }

  private func predictOnQueue(
    compiledURL: URL,
    jsonInput: String,
    sessionID: String?,
    resetSession: Bool,
    route: CoreMLExecutionRoute
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

    let normalizedSession = normalizedSessionID(sessionID)
    if resetSession, let normalizedSession {
      clearSessionOnQueue(
        compiledURL: compiledURL,
        sessionID: normalizedSession
      )
    }

    let effectiveMode = selectedModeOnQueue(
      compiledURL: compiledURL,
      sessionID: normalizedSession,
      requestedMode: route.mode
    )
    let model = try cachedModelOnQueue(
      at: compiledURL,
      mode: effectiveMode
    )

    if let normalizedSession {
      // Route locking is deliberately committed only after the model loaded
      // successfully. A persistent session therefore cannot be stranded on a
      // compute mode that failed during model construction.
      sessionModes[
        sessionSelectionKey(
          compiledURL: compiledURL,
          sessionID: normalizedSession
        )
      ] = effectiveMode
    }

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
      // buffers across calls. The selected compute route is locked for that
      // session until reset so an active KV/state context cannot silently move
      // between backends.
      let state: MLState
      if let normalizedSession {
        let key = sessionStateKey(
          compiledURL: compiledURL,
          mode: effectiveMode,
          sessionID: normalizedSession
        )
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
    let predictionMilliseconds = Self.milliseconds(from: elapsed)

    var resultValues: [String: String] = [:]
    for name in output.featureNames.sorted() {
      guard let value = output.featureValue(for: name) else { continue }
      resultValues[name] = Self.describe(value)
    }

    let sessionWasLocked = effectiveMode != route.mode
    let routingReason: String
    if sessionWasLocked {
      routingReason = route.reason + " " + L10n.text(
        de: "Die bestehende MLState-Session bleibt bis zum Reset auf \(effectiveMode.displayName) fixiert.",
        en: "The existing MLState session remains pinned to \(effectiveMode.displayName) until reset.",
        fr: "La session MLState existante reste fixée sur \(effectiveMode.displayName) jusqu’à sa réinitialisation."
      )
    } else {
      routingReason = route.reason
    }

    CoreMLAdaptiveExecutionTelemetry.shared.record(
      CoreMLExecutionTelemetrySnapshot(
        compiledPath: compiledURL.standardizedFileURL.path,
        mode: effectiveMode,
        source: sessionWasLocked ? .manual : route.source,
        adaptiveRoutingApplied: route.adaptiveRoutingApplied && !sessionWasLocked,
        reason: routingReason,
        predictionMilliseconds: predictionMilliseconds
      )
    )

    return CoreMLPredictionResult(
      values: resultValues,
      durationMilliseconds: predictionMilliseconds
    )
  }

  private func cachedModelOnQueue(
    at url: URL,
    mode: CoreMLComputeMode
  ) throws -> MLModel {
    dispatchPrecondition(condition: .onQueue(queue))
    let key = modelKey(url: url, mode: mode)
    if let existing = loadedModels[key] {
      return existing
    }

    // Models are cached per compiled artifact and compute policy. Build 34 no
    // longer globally destroys every model/session merely because another mode
    // is requested; explicit policy/workload changes clear the cache from the
    // UI, while persistent MLState sessions remain stable on their pinned mode.
    let configuration = MLModelConfiguration()
    configuration.computeUnits = mode.computeUnits
    let model = try MLModel(contentsOf: url, configuration: configuration)
    loadedModels[key] = model
    return model
  }

  private func selectedModeOnQueue(
    compiledURL: URL,
    sessionID: String?,
    requestedMode: CoreMLComputeMode
  ) -> CoreMLComputeMode {
    dispatchPrecondition(condition: .onQueue(queue))
    guard let sessionID else { return requestedMode }
    return sessionModes[
      sessionSelectionKey(
        compiledURL: compiledURL,
        sessionID: sessionID
      )
    ] ?? requestedMode
  }

  private func discardModelOnQueue(
    at url: URL,
    mode: CoreMLComputeMode
  ) {
    dispatchPrecondition(condition: .onQueue(queue))
    loadedModels.removeValue(forKey: modelKey(url: url, mode: mode))

    let statePrefix = "\(url.standardizedFileURL.path)|\(mode.rawValue)|"
    sessionStates = sessionStates.filter { key, _ in
      !key.hasPrefix(statePrefix)
    }
  }

  private func clearSessionOnQueue(
    compiledURL: URL,
    sessionID: String
  ) {
    dispatchPrecondition(condition: .onQueue(queue))
    let path = compiledURL.standardizedFileURL.path
    let suffix = "|\(sessionID)"
    sessionStates = sessionStates.filter { key, _ in
      !(key.hasPrefix("\(path)|") && key.hasSuffix(suffix))
    }
    sessionModes.removeValue(
      forKey: sessionSelectionKey(
        compiledURL: compiledURL,
        sessionID: sessionID
      )
    )
  }

  private func modelKey(
    url: URL,
    mode: CoreMLComputeMode
  ) -> String {
    "\(url.standardizedFileURL.path)|\(mode.rawValue)"
  }

  private func sessionStateKey(
    compiledURL: URL,
    mode: CoreMLComputeMode,
    sessionID: String
  ) -> String {
    "\(compiledURL.standardizedFileURL.path)|\(mode.rawValue)|\(sessionID)"
  }

  private func sessionSelectionKey(
    compiledURL: URL,
    sessionID: String
  ) -> String {
    "\(compiledURL.standardizedFileURL.path)|session|\(sessionID)"
  }

  private func normalizedSessionID(_ sessionID: String?) -> String? {
    guard let sessionID else { return nil }
    let normalized = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
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
