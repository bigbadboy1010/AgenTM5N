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
        de: "Der Input „\(name)“ vom Typ \(type) kann noch nicht über den generischen Core-ML-Runner erzeugt werden. Das Modell wurde geladen, benötigt aber einen typgerechten Eingabeadapter.",
        en: "Input “\(name)” of type \(type) cannot yet be created by the generic Core ML runner. The model is loaded, but it requires a type-specific input adapter.",
        fr: "L’entrée « \(name) » de type \(type) ne peut pas encore être créée par l’exécuteur Core ML générique. Le modèle est chargé, mais nécessite un adaptateur d’entrée spécifique."
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

    let validIDs = Set(registry.models.map(\.id))
    loadedModels = loadedModels.filter { validIDs.contains($0.key) }
    try saveRegistry()

    // The CoreML Sources/Compiled folders are private managed stores. Remove
    // abandoned copies left by an interrupted or previously failed import, but
    // never touch model paths outside those managed directories.
    let sourceReferences = registry.models.map(\.sourceURL).filter {
      CoreMLManagedStorage.isManaged($0, inside: AppPaths.coreMLSourcesDirectory)
    }
    let compiledReferences = registry.models.flatMap { record -> [URL] in
      var values = [record.compiledURL]
      if CoreMLManagedStorage.isManaged(
        record.sourceURL,
        inside: AppPaths.coreMLCompiledDirectory
      ) {
        values.append(record.sourceURL)
      }
      return values
    }
    do {
      try CoreMLManagedStorage.removeOrphans(
        in: AppPaths.coreMLSourcesDirectory,
        referencedURLs: sourceReferences
      )
      try CoreMLManagedStorage.removeOrphans(
        in: AppPaths.coreMLCompiledDirectory,
        referencedURLs: compiledReferences
      )
    } catch {
      AppLogger.app.error(
        "Core ML orphan cleanup failed: \(error.localizedDescription, privacy: .public)"
      )
    }

    // Keep application startup fast. Large Core ML graphs can require tens of
    // seconds to build their execution plan. Registered models are loaded lazily
    // when activated, predicted with, or used by a semantic workflow.
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

    let sourceDigest = try CoreMLManagedStorage.contentDigest(at: sourceURL)
    if let existing = try existingModel(matchingSourceDigest: sourceDigest) {
      registry.activeModelID = existing.id
      try saveRegistry()
      return existing
    }

    let previousRegistry = registry
    var createdManagedURLs: [URL] = []
    var temporaryCompiledURL: URL?

    do {
      let compiledCandidate: URL
      if sourceExtension == "mlmodelc" {
        compiledCandidate = sourceURL
      } else {
        let temporary = try await compileModel(at: sourceURL)
        temporaryCompiledURL = temporary
        compiledCandidate = temporary
      }
      defer {
        if let temporaryCompiledURL {
          try? FileManager.default.removeItem(at: temporaryCompiledURL)
        }
      }

      let compiledDigest = try CoreMLManagedStorage.contentDigest(at: compiledCandidate)
      let compiledCopy = try CoreMLManagedStorage.persistentCopy(
        of: compiledCandidate,
        in: AppPaths.coreMLCompiledDirectory,
        preferredExtension: "mlmodelc",
        digest: compiledDigest
      )
      if compiledCopy.created {
        createdManagedURLs.append(compiledCopy.url)
      }

      // Validate the final persistent artifact before changing the registry.
      // If Core ML cannot build an execution plan, the transaction rolls back
      // and the copied multi-gigabyte artifact is deleted immediately.
      let loadedModel = try await Self.loadCompiledModel(at: compiledCopy.url)

      let importedSourceURL: URL
      if sourceExtension == "mlmodelc" {
        importedSourceURL = compiledCopy.url
      } else {
        let sourceCopy = try CoreMLManagedStorage.persistentCopy(
          of: sourceURL,
          in: AppPaths.coreMLSourcesDirectory,
          preferredExtension: sourceExtension,
          digest: sourceDigest
        )
        importedSourceURL = sourceCopy.url
        if sourceCopy.created {
          createdManagedURLs.append(sourceCopy.url)
        }
      }

      let record = CoreMLRegisteredModel(
        name: uniqueModelName(sourceURL.deletingPathExtension().lastPathComponent),
        sourceURL: importedSourceURL,
        compiledURL: compiledCopy.url,
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
      try saveRegistry()
      loadedModels[record.id] = loadedModel
      return record
    } catch {
      registry = previousRegistry
      for url in createdManagedURLs.reversed() {
        try? FileManager.default.removeItem(at: url)
      }
      throw error
    }
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
    let result = try await CoreMLPredictionRunner.shared.predict(
      compiledURL: record.compiledURL,
      jsonInput: jsonInput
    )

    registry.activeModelID = record.id
    try saveRegistry()
    return result
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
    // Allow Core ML to schedule each operator across CPU, GPU and ANE. Some
    // large stateful transformer graphs cannot build an execution plan when
    // GPU is excluded by `.cpuAndNeuralEngine`, while `.all` succeeds and
    // still keeps the Neural Engine available for supported operators.
    configuration.computeUnits = .all
    return try await MLModel.load(contentsOf: url, configuration: configuration)
  }

  private func existingModel(
    matchingSourceDigest sourceDigest: String
  ) throws -> CoreMLRegisteredModel? {
    for record in registry.models {
      guard FileManager.default.fileExists(atPath: record.sourceURL.path) else {
        continue
      }
      let fileName = record.sourceURL.lastPathComponent.lowercased()
      if fileName.contains(sourceDigest.lowercased()) {
        return record
      }
      do {
        if try CoreMLManagedStorage.contentDigest(at: record.sourceURL) == sourceDigest {
          return record
        }
      } catch {
        AppLogger.app.error(
          "Core ML duplicate check skipped unreadable source: \(error.localizedDescription, privacy: .public)"
        )
      }
    }
    return nil
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
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: AppPaths.coreMLRegistryFile.path
    )
  }

  private func compileModel(at sourceURL: URL) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      MLModel.compileModel(at: sourceURL) { result in
        continuation.resume(with: result)
      }
    }
  }

  private static var computePolicyDescription: String {
    L10n.text(
      de: "Alle verfügbaren Core-ML-Recheneinheiten (CPU + GPU + Neural Engine)",
      en: "All available Core ML compute units (CPU + GPU + Neural Engine)",
      fr: "Toutes les unités de calcul Core ML disponibles (CPU + GPU + Neural Engine)"
    )
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
      details.append(
        L10n.text(de: "optional", en: "optional", fr: "facultatif")
      )
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
      return L10n.text(
        de: "Wörterbuch",
        en: "Dictionary",
        fr: "Dictionnaire"
      )
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
}