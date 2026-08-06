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
        de: "Das ausgewählte Core-ML-Modell ist kein kompatibles Text-Embedding-Modell. Erwartet wird genau eine Text-Eingabe. Gefunden: \(inputs.joined(separator: ", "))",
        en: "The selected Core ML model is not a compatible text embedding model. Exactly one text input is required. Found: \(inputs.joined(separator: ", "))",
        fr: "Le modèle Core ML sélectionné n’est pas un modèle d’embedding de texte compatible. Une seule entrée texte est requise. Trouvé : \(inputs.joined(separator: ", "))"
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

/// Runs a complete embedding batch in one isolated execution region.
///
/// Xcode 27 exposes Core ML prediction as an `@concurrent` operation. The model,
/// feature provider and output arrays therefore remain inside this detached task.
/// Only URLs, strings and normalized `[Float]` vectors cross isolation boundaries.
public enum CoreMLEmbeddingRunner {
  public static func embed(
    texts: [String],
    compiledURL: URL
  ) async throws -> [[Float]] {
    guard !texts.isEmpty else { return [] }

    return try await Task.detached(priority: .userInitiated) {
      let configuration = MLModelConfiguration()
      configuration.computeUnits = .cpuAndNeuralEngine
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

      for text in texts {
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
      }

      return result
    }.value
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
