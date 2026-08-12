import CoreML
import Foundation

public enum CoreMLSyntheticPredictionInputError: LocalizedError {
  case unsupportedInput(name: String, type: String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedInput(let name, let type):
      return L10n.text(
        de: "Für den adaptiven Test kann Eingang „\(name)“ vom Typ \(type) noch nicht automatisch erzeugt werden.",
        en: "The adaptive probe cannot yet automatically generate input “\(name)” of type \(type).",
        fr: "Le test adaptatif ne peut pas encore générer automatiquement l’entrée « \(name) » de type \(type)."
      )
    }
  }
}

/// Builds a deterministic JSON input for the generic CoreMLPredictionRunner.
///
/// This is intentionally a diagnostic input generator, not a tokenizer. For
/// transformer-style inputs it mirrors the Runtime Benchmark convention:
/// [CLS]=101, [SEP]=102 and the first two attention-mask positions enabled.
public final class CoreMLSyntheticPredictionInput: @unchecked Sendable {
  public static let shared = CoreMLSyntheticPredictionInput()

  private let queue = DispatchQueue(
    label: "AgenTM5N.CoreMLSyntheticPredictionInput",
    qos: .userInitiated
  )

  public init() {}

  public func makeJSON(compiledURL: URL) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
          continuation.resume(
            returning: try Self.makeJSONOnQueue(compiledURL: compiledURL)
          )
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private static func makeJSONOnQueue(compiledURL: URL) throws -> String {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuOnly
    let model = try MLModel(contentsOf: compiledURL, configuration: configuration)

    var object: [String: Any] = [:]
    for (name, description) in model.modelDescription.inputDescriptionsByName {
      switch description.type {
      case .double:
        object[name] = 0.0
      case .int64:
        object[name] = 0
      case .string:
        object[name] = "AgenTM5N adaptive execution probe"
      case .multiArray:
        guard let constraint = description.multiArrayConstraint else {
          throw CoreMLSyntheticPredictionInputError.unsupportedInput(
            name: name,
            type: "MultiArray"
          )
        }
        let count = constraint.shape.reduce(1) { partial, dimension in
          partial * max(0, dimension.intValue)
        }
        var values = [Double](repeating: 0, count: count)
        let normalized = name.lowercased()
          .replacingOccurrences(of: "-", with: "_")
        if normalized.contains("input_ids") || normalized.contains("inputids") {
          if !values.isEmpty { values[0] = 101 }
          if values.count > 1 { values[1] = 102 }
        } else if normalized.contains("attention_mask")
          || normalized.contains("attentionmask")
        {
          if !values.isEmpty { values[0] = 1 }
          if values.count > 1 { values[1] = 1 }
        }
        object[name] = values
      default:
        throw CoreMLSyntheticPredictionInputError.unsupportedInput(
          name: name,
          type: String(describing: description.type)
        )
      }
    }

    let data = try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys]
    )
    return String(decoding: data, as: UTF8.self)
  }
}
