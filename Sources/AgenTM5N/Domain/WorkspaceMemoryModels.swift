import Foundation

public enum WorkspaceIndexMode: String, Codable, Equatable, Sendable {
  case lexical
  case coreMLEmbedding

  public var displayName: String {
    switch self {
    case .lexical:
      return L10n.text(
        de: "Lexikalisch",
        en: "Lexical",
        fr: "Lexical"
      )
    case .coreMLEmbedding:
      return L10n.text(
        de: "Core ML semantisch",
        en: "Core ML Semantic",
        fr: "Sémantique Core ML"
      )
    }
  }
}

public enum WorkspaceIndexBuildPhase: String, Codable, Equatable, Sendable {
  case preparing
  case scanning
  case savingLexicalIndex
  case embedding
  case savingSemanticIndex
  case completed

  public var displayName: String {
    switch self {
    case .preparing:
      return L10n.text(de: "Vorbereitung", en: "Preparing", fr: "Préparation")
    case .scanning:
      return L10n.text(de: "Dateien werden gelesen", en: "Scanning files", fr: "Lecture des fichiers")
    case .savingLexicalIndex:
      return L10n.text(de: "Textindex wird gespeichert", en: "Saving text index", fr: "Enregistrement de l’index texte")
    case .embedding:
      return L10n.text(de: "Embeddings werden berechnet", en: "Computing embeddings", fr: "Calcul des embeddings")
    case .savingSemanticIndex:
      return L10n.text(de: "Semantischer Index wird gespeichert", en: "Saving semantic index", fr: "Enregistrement de l’index sémantique")
    case .completed:
      return L10n.text(de: "Abgeschlossen", en: "Completed", fr: "Terminé")
    }
  }
}

public struct WorkspaceIndexBuildProgress: Equatable, Sendable {
  public let phase: WorkspaceIndexBuildPhase
  public let completed: Int
  public let total: Int
  public let detail: String

  public init(
    phase: WorkspaceIndexBuildPhase,
    completed: Int = 0,
    total: Int = 0,
    detail: String = ""
  ) {
    self.phase = phase
    self.completed = completed
    self.total = total
    self.detail = detail
  }

  public var fractionCompleted: Double? {
    guard total > 0 else { return nil }
    return min(1, max(0, Double(completed) / Double(total)))
  }
}

public struct WorkspaceIndexStatus: Codable, Equatable, Sendable {
  public let workspacePath: String
  public let mode: WorkspaceIndexMode
  public let modelID: UUID?
  public let modelName: String?
  public let warning: String?
  public let createdAt: Date
  public let fileCount: Int
  public let chunkCount: Int
  public let embeddingDimension: Int?
  public let indexedCharacterCount: Int

  public init(
    workspacePath: String,
    mode: WorkspaceIndexMode,
    modelID: UUID? = nil,
    modelName: String? = nil,
    warning: String? = nil,
    createdAt: Date = Date(),
    fileCount: Int,
    chunkCount: Int,
    embeddingDimension: Int? = nil,
    indexedCharacterCount: Int
  ) {
    self.workspacePath = workspacePath
    self.mode = mode
    self.modelID = modelID
    self.modelName = modelName
    self.warning = warning
    self.createdAt = createdAt
    self.fileCount = fileCount
    self.chunkCount = chunkCount
    self.embeddingDimension = embeddingDimension
    self.indexedCharacterCount = indexedCharacterCount
  }
}

public struct WorkspaceIndexChunk: Codable, Equatable, Sendable {
  public let id: UUID
  public let relativePath: String
  public let startLine: Int
  public let endLine: Int
  public let text: String
  public let embedding: [Float]?

  public init(
    id: UUID = UUID(),
    relativePath: String,
    startLine: Int,
    endLine: Int,
    text: String,
    embedding: [Float]? = nil
  ) {
    self.id = id
    self.relativePath = relativePath
    self.startLine = startLine
    self.endLine = endLine
    self.text = text
    self.embedding = embedding
  }
}

public struct WorkspaceIndexDocument: Codable, Equatable, Sendable {
  public let version: Int
  public let status: WorkspaceIndexStatus
  public let chunks: [WorkspaceIndexChunk]

  public init(
    version: Int = 2,
    status: WorkspaceIndexStatus,
    chunks: [WorkspaceIndexChunk]
  ) {
    self.version = version
    self.status = status
    self.chunks = chunks
  }
}

public struct WorkspaceSemanticMatch: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let relativePath: String
  public let startLine: Int
  public let endLine: Int
  public let score: Double
  public let excerpt: String

  public init(
    id: UUID,
    relativePath: String,
    startLine: Int,
    endLine: Int,
    score: Double,
    excerpt: String
  ) {
    self.id = id
    self.relativePath = relativePath
    self.startLine = startLine
    self.endLine = endLine
    self.score = score
    self.excerpt = excerpt
  }
}
