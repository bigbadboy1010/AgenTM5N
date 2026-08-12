import CoreML
import Foundation

public enum CoreMLEmbeddingError: LocalizedError {
  case incompatibleInput([String])
  case incompatibleOutput([String])
  case missingOutput(String)
  case emptyEmbedding
  case inconsistentDimension(expected: Int, actual: Int)

  public var errorDescription: String? {
    switch self {
    case .incompatibleInput(let inputs):
      return L10n.text(
        de: "Das ausgewählte Core-ML-Modell kann Text nicht direkt einbetten. Erwartet wird genau eine String-Eingabe. Gefunden: \(inputs.joined(separator: ", ")). Transformer-Modelle mit input_ids und attention_mask benötigen einen Tokenizer-Adapter.",
        en: "The selected Core ML model cannot embed text directly. Exactly one String input is required. Found: \(inputs.joined(separator: ", ")). Transformer models with input_ids and attention_mask require a tokenizer adapter.",
        fr: "Le modèle Core ML sélectionné ne peut pas vectoriser directement du texte. Une seule entrée String est requise. Trouvé : \(inputs.joined(separator: ", ")). Les modèles Transformer avec input_ids et attention_mask nécessitent un adaptateur de tokenisation."
      )
    case .incompatibleOutput(let outputs):
      return L10n.text(
        de: "Das ausgewählte Core-ML-Modell muss genau eine MultiArray-Ausgabe für den Embedding-Vektor bereitstellen. Gefunden: \(outputs.joined(separator: ", "))",
        en: "The selected Core ML model must expose exactly one MultiArray output for the embedding vector. Found: \(outputs.joined(separator: ", "))",
        fr: "Le modèle Core ML sélectionné doit fournir exactement une sortie MultiArray pour le vecteur d’embedding. Trouvé : \(outputs.joined(separator: ", "))"
      )
    case .missingOutput(let name):
      return L10n.text(
        de: "Das Core-ML-Modell hat die erwartete Embedding-Ausgabe „\(name)“ nicht geliefert.",
        en: "The Core ML model did not return the expected embedding output “\(name)”.",
        fr: "Le modèle Core ML n’a pas renvoyé la sortie d’embedding attendue « \(name) »."
      )
    case .emptyEmbedding:
      return L10n.text(
        de: "Das Core-ML-Modell hat einen leeren oder nicht normalisierbaren Embedding-Vektor geliefert.",
        en: "The Core ML model returned an empty or non-normalizable embedding vector.",
        fr: "Le modèle Core ML a renvoyé un vecteur d’embedding vide ou non normalisable."
      )
    case .inconsistentDimension(let expected, let actual):
      return L10n.text(
        de: "Das Core-ML-Modell hat uneinheitliche Embedding-Dimensionen geliefert. Erwartet: \(expected), erhalten: \(actual).",
        en: "The Core ML model returned inconsistent embedding dimensions. Expected: \(expected), received: \(actual).",
        fr: "Le modèle Core ML a renvoyé des dimensions d’embedding incohérentes. Attendu : \(expected), reçu : \(actual)."
      )
    }
  }
}

public enum CoreMLEmbeddingRunner {
  private struct MeasuredEmbeddingResult: Sendable {
    let vectors: [[Float]]
    let durationMilliseconds: Double
  }

  public static func embed(
    texts: [String],
    compiledURL: URL,
    workload: CoreMLNeuralWorkload? = nil,
    progress: (@Sendable (Int, Int) async -> Void)? = nil
  ) async throws -> [[Float]] {
    guard !texts.isEmpty else { return [] }

    let effectiveWorkload = workload ?? CoreMLNeuralWorkload(
      kind: .genericPrediction,
      expectedPredictions: texts.count,
      itemCount: texts.count
    )
    let route = await CoreMLNeuralRuntimeOrchestrator.resolve(
      compiledURL: compiledURL,
      workload: effectiveWorkload
    )

    do {
      let measured = try await embed(
        texts: texts,
        compiledURL: compiledURL,
        mode: route.mode,
        progress: progress
      )
      recordTelemetry(
        compiledURL: compiledURL,
        workload: effectiveWorkload,
        route: route,
        actualMode: route.mode,
        durationMilliseconds: measured.durationMilliseconds,
        fallbackUsed: false
      )
      return measured.vectors
    } catch {
      let primaryError = error
      guard route.allowsAutomaticFailover else {
        throw primaryError
      }

      let fallbackRoute = CoreMLAdaptiveExecutionPolicy.automaticFailover(
        from: route,
        error: primaryError
      )
      let measured = try await embed(
        texts: texts,
        compiledURL: compiledURL,
        mode: .automatic,
        progress: progress
      )
      recordTelemetry(
        compiledURL: compiledURL,
        workload: effectiveWorkload,
        route: fallbackRoute,
        actualMode: .automatic,
        durationMilliseconds: measured.durationMilliseconds,
        fallbackUsed: true
      )
      return measured.vectors
    }
  }

  private static func embed(
    texts: [String],
    compiledURL: URL,
    mode: CoreMLComputeMode,
    progress: (@Sendable (Int, Int) async -> Void)?
  ) async throws -> MeasuredEmbeddingResult {
    try await Task.detached(priority: .userInitiated) {
      let startedAt = ContinuousClock().now
      let configuration = MLModelConfiguration()
      configuration.computeUnits = mode.computeUnits
      let model = try await MLModel.load(
        contentsOf: compiledURL,
        configuration: configuration
      )

      let inputDescriptions = model.modelDescription.inputDescriptionsByName
      let textInputs = inputDescriptions.filter { $0.value.type == .string }
      guard inputDescriptions.count == 1,
        textInputs.count == 1,
        let inputName = textInputs.first?.key
      else {
        throw CoreMLEmbeddingError.incompatibleInput(
          inputDescriptions
            .map { "\($0.key) [\(String(describing: $0.value.type))]" }
            .sorted()
        )
      }

      let outputDescriptions = model.modelDescription.outputDescriptionsByName
      let vectorOutputs = outputDescriptions.filter { $0.value.type == .multiArray }
      guard outputDescriptions.count == 1,
        vectorOutputs.count == 1,
        let outputName = vectorOutputs.first?.key
      else {
        throw CoreMLEmbeddingError.incompatibleOutput(
          outputDescriptions
            .map { "\($0.key) [\(String(describing: $0.value.type))]" }
            .sorted()
        )
      }

      var result: [[Float]] = []
      result.reserveCapacity(texts.count)
      var expectedDimension: Int?

      for (offset, text) in texts.enumerated() {
        try Task.checkCancellation()
        let input = TextEmbeddingFeatureProvider(
          name: inputName,
          text: text
        )
        let output = try await model.prediction(from: input)
        guard let array = output.featureValue(for: outputName)?.multiArrayValue else {
          throw CoreMLEmbeddingError.missingOutput(outputName)
        }

        var vector = [Float]()
        vector.reserveCapacity(array.count)
        for index in 0..<array.count {
          vector.append(array[index].floatValue)
        }
        vector = try normalized(vector)

        if let expectedDimension, expectedDimension != vector.count {
          throw CoreMLEmbeddingError.inconsistentDimension(
            expected: expectedDimension,
            actual: vector.count
          )
        }
        expectedDimension = vector.count
        result.append(vector)
        await progress?(offset + 1, texts.count)
      }

      let duration = startedAt.duration(to: ContinuousClock().now)
      return MeasuredEmbeddingResult(
        vectors: result,
        durationMilliseconds: milliseconds(from: duration)
      )
    }.value
  }

  private static func recordTelemetry(
    compiledURL: URL,
    workload: CoreMLNeuralWorkload,
    route: CoreMLExecutionRoute,
    actualMode: CoreMLComputeMode,
    durationMilliseconds: Double,
    fallbackUsed: Bool
  ) {
    CoreMLNeuralRuntimeTelemetry.shared.record(
      CoreMLNeuralRuntimeEvent(
        workload: workload.kind,
        compiledPath: compiledURL.standardizedFileURL.path,
        mode: actualMode,
        source: route.source,
        itemCount: workload.itemCount,
        expectedPredictions: route.expectedPredictions,
        durationMilliseconds: durationMilliseconds,
        fallbackUsed: fallbackUsed,
        reason: route.reason
      )
    )
  }

  private static func normalized(_ vector: [Float]) throws -> [Float] {
    guard !vector.isEmpty else {
      throw CoreMLEmbeddingError.emptyEmbedding
    }
    let squaredNorm = vector.reduce(Float.zero) { partial, value in
      partial + value * value
    }
    let norm = sqrt(squaredNorm)
    guard norm.isFinite, norm > 0 else {
      throw CoreMLEmbeddingError.emptyEmbedding
    }
    return vector.map { $0 / norm }
  }

  private static func milliseconds(from duration: Duration) -> Double {
    let components = duration.components
    let seconds = Double(components.seconds)
    let attoseconds = Double(components.attoseconds)
    return seconds * 1_000 + attoseconds / 1_000_000_000_000_000
  }
}

private final class TextEmbeddingFeatureProvider: NSObject, MLFeatureProvider {
  private let name: String
  private let value: MLFeatureValue

  init(name: String, text: String) {
    self.name = name
    self.value = MLFeatureValue(string: text)
    super.init()
  }

  var featureNames: Set<String> {
    [name]
  }

  func featureValue(for featureName: String) -> MLFeatureValue? {
    featureName == name ? value : nil
  }
}
