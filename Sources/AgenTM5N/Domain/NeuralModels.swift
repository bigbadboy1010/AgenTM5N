import Foundation

public enum CoreMLModelCapability: String, Equatable, Sendable {
  case directTextEmbedding
  case tokenizedCausalLanguageModel
  case tokenizedTransformer
  case vision
  case generic

  public var displayName: String {
    switch self {
    case .directTextEmbedding:
      return L10n.text(
        de: "Direktes Text-Embedding-Modell",
        en: "Direct Text Embedding Model",
        fr: "Modèle d’embedding de texte direct"
      )
    case .tokenizedCausalLanguageModel:
      return L10n.text(
        de: "Tokenisiertes generatives Sprachmodell",
        en: "Tokenized Generative Language Model",
        fr: "Modèle linguistique génératif tokenisé"
      )
    case .tokenizedTransformer:
      return L10n.text(
        de: "Tokenisiertes Transformer-Modell",
        en: "Tokenized Transformer Model",
        fr: "Modèle Transformer tokenisé"
      )
    case .vision:
      return L10n.text(
        de: "Bild-/Vision-Modell",
        en: "Image/Vision Model",
        fr: "Modèle image/vision"
      )
    case .generic:
      return L10n.text(
        de: "Allgemeines Core-ML-Modell",
        en: "Generic Core ML Model",
        fr: "Modèle Core ML générique"
      )
    }
  }

  public var workspaceMemoryExplanation: String {
    switch self {
    case .directTextEmbedding:
      return L10n.text(
        de: "Direkt kompatibel: Text wird als String übergeben und das Modell liefert einen MultiArray-Embedding-Vektor.",
        en: "Directly compatible: text is passed as a String and the model returns a MultiArray embedding vector.",
        fr: "Compatible directement : le texte est transmis sous forme de String et le modèle renvoie un vecteur MultiArray."
      )
    case .tokenizedCausalLanguageModel:
      return L10n.text(
        de: "Nicht als Workspace-Embedding geeignet: Das Modell erwartet tokenisierte Eingaben wie inputIds und causalMask und erzeugt typischerweise Sprachmodell-Ausgaben. Es benötigt einen modellspezifischen Tokenizer und eine separate Embedding-Ausgabe oder Pooling-Schicht.",
        en: "Not suitable as a workspace embedding model: it expects tokenized inputs such as inputIds and causalMask and typically produces language-model outputs. It requires a model-specific tokenizer and a separate embedding output or pooling layer.",
        fr: "Ne convient pas comme modèle d’embedding de l’espace de travail : il attend des entrées tokenisées telles que inputIds et causalMask et produit généralement des sorties de modèle linguistique. Il nécessite un tokenizer spécifique et une sortie d’embedding ou une couche de pooling distincte."
      )
    case .tokenizedTransformer:
      return L10n.text(
        de: "Noch nicht direkt kompatibel: Das Modell erwartet tokenisierte MultiArray-Eingaben. Dafür werden ein passender Tokenizer, Sequenzlänge, Sondertokens und eine definierte Pooling-Strategie benötigt.",
        en: "Not directly compatible yet: the model expects tokenized MultiArray inputs. It requires a matching tokenizer, sequence length, special tokens, and a defined pooling strategy.",
        fr: "Pas encore compatible directement : le modèle attend des entrées MultiArray tokenisées. Il nécessite un tokenizer adapté, une longueur de séquence, des tokens spéciaux et une stratégie de pooling définie."
      )
    case .vision:
      return L10n.text(
        de: "Nicht für Textindexierung geeignet: Dieses Modell verarbeitet Bilddaten.",
        en: "Not suitable for text indexing: this model processes image data.",
        fr: "Ne convient pas à l’indexation de texte : ce modèle traite des images."
      )
    case .generic:
      return L10n.text(
        de: "Nicht als direktes Text-Embedding-Modell erkannt. Es kann weiterhin über den allgemeinen Core-ML-Pfad verwendet werden.",
        en: "Not recognized as a direct text embedding model. It can still be used through the generic Core ML path.",
        fr: "Non reconnu comme modèle d’embedding de texte direct. Il peut toujours être utilisé via le chemin Core ML générique."
      )
    }
  }
}

public struct CoreMLRegisteredModel: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public let sourceURL: URL
  public let compiledURL: URL
  public let inputs: [String]
  public let outputs: [String]
  public let computeUnits: String
  public let importedAt: Date

  public init(
    id: UUID = UUID(),
    name: String,
    sourceURL: URL,
    compiledURL: URL,
    inputs: [String],
    outputs: [String],
    computeUnits: String,
    importedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.sourceURL = sourceURL
    self.compiledURL = compiledURL
    self.inputs = inputs
    self.outputs = outputs
    self.computeUnits = computeUnits
    self.importedAt = importedAt
  }

  public var descriptor: CoreMLModelDescriptor {
    CoreMLModelDescriptor(
      sourceURL: sourceURL,
      compiledURL: compiledURL,
      inputs: inputs,
      outputs: outputs,
      computeUnits: computeUnits
    )
  }

  public var capability: CoreMLModelCapability {
    let normalizedInputs = inputs.map { $0.lowercased() }
    let normalizedOutputs = outputs.map { $0.lowercased() }

    let hasSingleTextInput = normalizedInputs.count == 1
      && normalizedInputs[0].contains("[text")
    let hasSingleMultiArrayOutput = normalizedOutputs.count == 1
      && normalizedOutputs[0].contains("multiarray")

    if hasSingleTextInput && hasSingleMultiArrayOutput {
      return .directTextEmbedding
    }

    let combinedInputs = normalizedInputs.joined(separator: " ")
    let combinedOutputs = normalizedOutputs.joined(separator: " ")
    let hasInputIDs = combinedInputs.contains("inputids")
      || combinedInputs.contains("input_ids")
    let hasCausalMask = combinedInputs.contains("causalmask")
      || combinedInputs.contains("causal_mask")
    let hasAttentionMask = combinedInputs.contains("attentionmask")
      || combinedInputs.contains("attention_mask")
    let hasLanguageModelOutput = combinedOutputs.contains("logits")
      || combinedOutputs.contains("token")

    if hasInputIDs && (hasCausalMask || hasLanguageModelOutput) {
      return .tokenizedCausalLanguageModel
    }
    if hasInputIDs || hasAttentionMask {
      return .tokenizedTransformer
    }
    if combinedInputs.contains("[bild")
      || combinedInputs.contains("[image")
      || combinedInputs.contains("pixel")
    {
      return .vision
    }
    return .generic
  }

  public var supportsDirectTextEmbedding: Bool {
    capability == .directTextEmbedding
  }
}

public struct CoreMLRegistryDocument: Codable, Equatable, Sendable {
  public var version: Int
  public var activeModelID: UUID?
  public var models: [CoreMLRegisteredModel]

  public init(
    version: Int = 1,
    activeModelID: UUID? = nil,
    models: [CoreMLRegisteredModel] = []
  ) {
    self.version = version
    self.activeModelID = activeModelID
    self.models = models
  }
}

public struct CoreMLRegistrySnapshot: Equatable, Sendable {
  public let models: [CoreMLRegisteredModel]
  public let activeModelID: UUID?
  public let activeDescriptor: CoreMLModelDescriptor?

  public init(
    models: [CoreMLRegisteredModel],
    activeModelID: UUID?,
    activeDescriptor: CoreMLModelDescriptor?
  ) {
    self.models = models
    self.activeModelID = activeModelID
    self.activeDescriptor = activeDescriptor
  }
}
