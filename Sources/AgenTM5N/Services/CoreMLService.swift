import CoreML
import Foundation

public enum CoreMLServiceError: LocalizedError {
  case modelNotLoaded
  case modelNotFound(String)
  case ambiguousModel(String, [String])
  case invalidJSON
  case unsupportedInputValue(String)
  case unsupportedModelType(String)
  case sourceUnavailable(String)
  case inputTypeNotSupported(name: String, type: String)
  case registryEncodingFailed

  public var errorDescription: String? {
    switch self {
    case .modelNotLoaded:
      return L10n.text(
        de: "Es wurde noch kein Core-ML-Modell geladen.",
        en: "No Core ML model has been loaded yet.",
        fr: "Aucun modèle Core ML n’a encore été chargé."
      )
    case .modelNotFound(let query):
      return L10n.text(
        de: "Kein registriertes Core-ML-Modell passt zu: \(query)",
        en: "No registered Core ML model matches: \(query)",
        fr: "Aucun modèle Core ML enregistré ne correspond à : \(query)"
      )
    case .ambiguousModel(let query, let matches):
      return L10n.text(
        de: "Das Core-ML-Modell ist nicht eindeutig (\(query)): \(matches.joined(separator: ", "))",
        en: "The Core ML model is ambiguous (\(query)): \(matches.joined(separator: ", "))",
        fr: "Le modèle Core ML est ambigu (\(query)) : \(matches.joined(separator: ", "))"
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
    case .registryEncodingFailed:
      return L10n.text(
        de: "Das Core-ML-Modellregister konnte nicht gespeichert werden.",
        en: "The Core ML model registry could not be saved.",
        fr: "Le registre des modèles Core ML n’a pas pu être enregistré."
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
  private static let maximumJSONInputBytes = 1 * 1024 * 1024

  private var registry = CoreMLRegistryDocument()
  private var loadedModels: [UUID: MLModel] = [:]

  public init() {}

  public func bootstrap() async throws -> CoreMLRegistrySnapshot {
    try AppPaths.ensureDirectories()
    registry = try loadRegistry()
    registry.models = registry.models.filter {
      FileManager.default.fileExists(atPath: $0.compiledURL.path)
    }
    if let activeID = registry.activeModelID,
      !registry.models.contains(where: { $0.id == activeID })
    {
      registry.activeModelID = registry.models.first?.id
    }
    if registry.activeModelID == nil {
      registry.activeModelID = registry.models.first?.id
    }
    try saveRegistry()

    if let activeID = registry.activeModelID {
      _ = try await model(for: activeID)
    }
    return snapshot()
  }

  public func loadModel(sourceURL: URL) async throws -> CoreMLRegisteredModel {
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

    let loadedModel = try await Self.loadCompiledModel(at: compiledURL)
    let record = CoreMLRegisteredModel(
      name: uniqueModelName(sourceURL.deletingPathExtension().lastPathComponent),
      sourceURL: importedSourceURL,
      compiledURL: compiledURL,
      inputs: Self.featureDescriptions(
        loadedModel.modelDescription.inputDescriptionsByName
      ),
      outputs: Self.featureDescriptions(
        loadedModel.modelDescription.outputDescriptionsByName
      ),
      computeUnits: Self.computePolicyDescription
    )

    registry.models.append(record)
    registry.models.sort {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    registry.activeModelID = record.id
    loadedModels[record.id] = loadedModel
    try saveRegistry()
    return record
  }

  public func listModels() -> [CoreMLRegisteredModel] {
    registry.models
  }

  public func activeModelID() -> UUID? {
    registry.activeModelID
  }

  public func currentDescriptor() -> CoreMLModelDescriptor? {
    guard let activeID = registry.activeModelID else { return nil }
    return registry.models.first(where: { $0.id == activeID })?.descriptor
  }

  public func registeredModel(query: String? = nil) throws -> CoreMLRegisteredModel {
    try resolveRecord(query: query)
  }

  public func activateModel(query: String) async throws -> CoreMLRegisteredModel {
    let record = try resolveRecord(query: query)
    _ = try await model(for: record.id)
    registry.activeModelID = record.id
    try saveRegistry()
    return record
  }

  public func predict(
    jsonInput: String,
    modelQuery: String? = nil
  ) async throws -> CoreMLPredictionResult {
    guard jsonInput.utf8.count <= Self.maximumJSONInputBytes else {
      throw AgentRuntimeError.inputTooLarge(limit: Self.maximumJSONInputBytes)
    }
    let record = try resolveRecord(query: modelQuery)
    let loadedModel = try await model(for: record.id)
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
    for (name, description) in loadedModel.modelDescription.inputDescriptionsByName {
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
    let output = try await loadedModel.prediction(from: input)
    let elapsed = startedAt.duration(to: clock.now)

    var resultValues: [String: String] = [:]
    for name in output.featureNames.sorted() {
      guard let value = output.featureValue(for: name) else { continue }
      resultValues[name] = Self.describe(value)
    }

    registry.activeModelID = record.id
    try saveRegistry()
    return CoreMLPredictionResult(
      values: resultValues,
      durationMilliseconds: Self.milliseconds(from: elapsed)
    )
  }

  private func model(for id: UUID) async throws -> MLModel {
    if let loaded = loadedModels[id] {
      return loaded
    }
    guard let record = registry.models.first(where: { $0.id == id }) else {
      throw CoreMLServiceError.modelNotFound(id.uuidString)
    }
    let loaded = try await Self.loadCompiledModel(at: record.compiledURL)
    loadedModels[id] = loaded
    return loaded
  }

  private static func loadCompiledModel(at url: URL) async throws -> MLModel {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuAndNeuralEngine
    return try await MLModel.load(contentsOf: url, configuration: configuration)
  }

  private func resolveRecord(query: String?) throws -> CoreMLRegisteredModel {
    let normalized = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if normalized.isEmpty {
      guard let activeID = registry.activeModelID,
        let active = registry.models.first(where: { $0.id == activeID })
      else {
        throw CoreMLServiceError.modelNotLoaded
      }
      return active
    }

    let matches = registry.models.filter { record in
      record.id.uuidString.caseInsensitiveCompare(normalized) == .orderedSame
        || record.name.caseInsensitiveCompare(normalized) == .orderedSame
    }
    guard !matches.isEmpty else {
      throw CoreMLServiceError.modelNotFound(normalized)
    }
    guard matches.count == 1, let record = matches.first else {
      throw CoreMLServiceError.ambiguousModel(normalized, matches.map(\.name))
    }
    return record
  }

  private func uniqueModelName(_ requested: String) -> String {
    let base = requested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "CoreMLModel"
      : requested
    guard registry.models.contains(where: {
      $0.name.caseInsensitiveCompare(base) == .orderedSame
    }) else {
      return base
    }

    var suffix = 2
    while registry.models.contains(where: {
      $0.name.caseInsensitiveCompare("\(base) \(suffix)") == .orderedSame
    }) {
      suffix += 1
    }
    return "\(base) \(suffix)"
  }

  private func snapshot() -> CoreMLRegistrySnapshot {
    CoreMLRegistrySnapshot(
      models: registry.models,
      activeModelID: registry.activeModelID,
      activeDescriptor: currentDescriptor()
    )
  }

  private func loadRegistry() throws -> CoreMLRegistryDocument {
    guard FileManager.default.fileExists(atPath: AppPaths.coreMLRegistryFile.path) else {
      return CoreMLRegistryDocument()
    }
    let data = try Data(contentsOf: AppPaths.coreMLRegistryFile)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(CoreMLRegistryDocument.self, from: data)
  }

  private func saveRegistry() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(registry)
    guard !data.isEmpty else {
      throw CoreMLServiceError.registryEncodingFailed
    }
    try data.write(to: AppPaths.coreMLRegistryFile, options: [.atomic])
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

  private static var computePolicyDescription: String {
    L10n.text(
      de: "CPU + Apple Neural Engine (angefordert)",
      en: "CPU + Apple Neural Engine (requested)",
      fr: "CPU + Apple Neural Engine (demandé)"
    )
  }

  private static func sanitizedBaseName(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
    let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return result.isEmpty ? "CoreMLModel" : result
  }

  private static func featureDescriptions(
    _ descriptions: [String: MLFeatureDescription]
  ) -> [String] {
    descriptions
      .map { name, description in
        describeFeature(name: name, description: description)
      }
      .sorted()
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
