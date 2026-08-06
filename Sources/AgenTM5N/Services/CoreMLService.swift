import CoreML
import Foundation

public enum CoreMLServiceError: LocalizedError {
  case modelNotLoaded
  case invalidJSON
  case unsupportedInputValue(String)
  case unsupportedModelType(String)
  case sourceUnavailable(String)
  case inputTypeNotSupported(name: String, type: String)

  public var errorDescription: String? {
    switch self {
    case .modelNotLoaded:
      return L10n.text(
        de: "Es wurde noch kein Core-ML-Modell geladen.",
        en: "No Core ML model has been loaded yet.",
        fr: "Aucun modèle Core ML n’a encore été chargé."
      )
    case .invalidJSON:
      return L10n.text(
        de: "Die Vorhersage-Eingabe muss ein gültiges JSON-Objekt sein.",
        en: "The prediction input must be a valid JSON object.",
        fr: "L’entrée de prédiction doit être un objet JSON valide."
      )
    case .unsupportedInputValue(let key):
      return L10n.text(
        de: "Der Wert für „\(key)“ wird vom generischen Core-ML-Runner nicht unterstützt.",
        en: "The value for “\(key)” is not supported by the generic Core ML runner.",
        fr: "La valeur de « \(key) » n’est pas prise en charge par l’exécuteur Core ML générique."
      )
    case .unsupportedModelType(let value):
      return L10n.text(
        de: "Nicht unterstützter Core-ML-Modelltyp: \(value). Erlaubt sind .mlmodel, .mlpackage und .mlmodelc.",
        en: "Unsupported Core ML model type: \(value). Supported types are .mlmodel, .mlpackage, and .mlmodelc.",
        fr: "Type de modèle Core ML non pris en charge : \(value). Les types acceptés sont .mlmodel, .mlpackage et .mlmodelc."
      )
    case .sourceUnavailable(let path):
      return L10n.text(
        de: "Das ausgewählte Core-ML-Modell ist nicht erreichbar: \(path)",
        en: "The selected Core ML model is not accessible: \(path)",
        fr: "Le modèle Core ML sélectionné n’est pas accessible : \(path)"
      )
    case .inputTypeNotSupported(let name, let type):
      return L10n.text(
        de: "Der Input „\(name)“ vom Typ \(type) kann noch nicht über den generischen JSON-Runner erzeugt werden. Das Modell wurde geladen, benötigt aber einen typgerechten Eingabeadapter.",
        en: "Input “\(name)” of type \(type) cannot yet be created by the generic JSON runner. The model is loaded, but it requires a type-specific input adapter.",
        fr: "L’entrée « \(name) » de type \(type) ne peut pas encore être créée par l’exécuteur JSON générique. Le modèle est chargé, mais nécessite un adaptateur d’entrée spécifique."
      )
    }
  }
}

public actor CoreMLService {
  private static let supportedExtensions: Set<String> = [
    "mlmodel",
    "mlpackage",
    "mlmodelc",
  ]

  private var model: MLModel?
  private var descriptor: CoreMLModelDescriptor?

  public init() {}

  public func loadModel(sourceURL: URL) async throws -> CoreMLModelDescriptor {
    let sourceExtension = sourceURL.pathExtension.lowercased()
    guard Self.supportedExtensions.contains(sourceExtension) else {
      throw CoreMLServiceError.unsupportedModelType(
        sourceExtension.isEmpty ? sourceURL.lastPathComponent : ".\(sourceExtension)"
      )
    }
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      throw CoreMLServiceError.sourceUnavailable(sourceURL.path)
    }

    try AppPaths.ensureDirectories()

    let importedSourceURL: URL
    let compiledURL: URL
    if sourceExtension == "mlmodelc" {
      importedSourceURL = try persistentCopy(
        of: sourceURL,
        in: AppPaths.coreMLCompiledDirectory,
        preferredExtension: "mlmodelc"
      )
      compiledURL = importedSourceURL
    } else {
      importedSourceURL = try persistentCopy(
        of: sourceURL,
        in: AppPaths.coreMLSourcesDirectory,
        preferredExtension: sourceExtension
      )
      let temporaryCompiledURL = try await compileModel(at: importedSourceURL)
      compiledURL = try persistentCopy(
        of: temporaryCompiledURL,
        in: AppPaths.coreMLCompiledDirectory,
        preferredExtension: "mlmodelc"
      )
    }

    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuAndNeuralEngine
    let loadedModel = try await MLModel.load(
      contentsOf: compiledURL,
      configuration: configuration
    )

    let inputs = loadedModel.modelDescription.inputDescriptionsByName
      .map { name, description in
        Self.describeFeature(name: name, description: description)
      }
      .sorted()
    let outputs = loadedModel.modelDescription.outputDescriptionsByName
      .map { name, description in
        Self.describeFeature(name: name, description: description)
      }
      .sorted()

    let descriptor = CoreMLModelDescriptor(
      sourceURL: importedSourceURL,
      compiledURL: compiledURL,
      inputs: inputs,
      outputs: outputs,
      computeUnits: L10n.text(
        de: "CPU + Apple Neural Engine (angefordert)",
        en: "CPU + Apple Neural Engine (requested)",
        fr: "CPU + Apple Neural Engine (demandé)"
      )
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

    let values: [String: JSONValue]
    do {
      values = try JSONDecoder().decode([String: JSONValue].self, from: data)
    } catch {
      throw CoreMLServiceError.invalidJSON
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

    let input = DictionaryFeatureProvider(values: featureValues)
    let clock = ContinuousClock()
    let startedAt = clock.now
    let output = try model.prediction(from: input)
    let elapsed = startedAt.duration(to: clock.now)

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

  private func compileModel(at sourceURL: URL) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      MLModel.compileModel(at: sourceURL) { result in
        continuation.resume(with: result)
      }
    }
  }

  private func persistentCopy(
    of sourceURL: URL,
    in directory: URL,
    preferredExtension: String
  ) throws -> URL {
    let manager = FileManager.default
    let baseName = Self.sanitizedBaseName(sourceURL.deletingPathExtension().lastPathComponent)
    let suffix = String(UUID().uuidString.prefix(8)).lowercased()
    let destination = directory.appendingPathComponent(
      "\(baseName)-\(suffix).\(preferredExtension)",
      isDirectory: preferredExtension == "mlpackage" || preferredExtension == "mlmodelc"
    )
    try manager.copyItem(at: sourceURL, to: destination)
    return destination
  }

  private static func sanitizedBaseName(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
    let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return result.isEmpty ? "CoreMLModel" : result
  }

  private static func describeFeature(
    name: String,
    description: MLFeatureDescription
  ) -> String {
    var details = [localizedFeatureType(description.type)]
    if let constraint = description.multiArrayConstraint {
      let shape = constraint.shape.map(\.stringValue).joined(separator: " × ")
      if !shape.isEmpty {
        details.append(shape)
      }
    }
    if let constraint = description.imageConstraint {
      details.append("\(constraint.pixelsWide) × \(constraint.pixelsHigh)")
    }
    if description.isOptional {
      details.append(L10n.text(de: "optional", en: "optional", fr: "facultatif"))
    }
    return "\(name) [\(details.joined(separator: ", "))]"
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
    default:
      throw CoreMLServiceError.inputTypeNotSupported(
        name: name,
        type: localizedFeatureType(description.type)
      )
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

private final class DictionaryFeatureProvider: NSObject, MLFeatureProvider {
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
