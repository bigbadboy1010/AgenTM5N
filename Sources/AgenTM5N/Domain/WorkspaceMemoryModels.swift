import Foundation

public struct WorkspaceIndexStatus: Codable, Equatable, Sendable {
  public let workspacePath: String
  public let modelID: UUID
  public let modelName: String
  public let createdAt: Date
  public let fileCount: Int
  public let chunkCount: Int
  public let embeddingDimension: Int
  public let indexedCharacterCount: Int

  public init(
    workspacePath: String,
    modelID: UUID,
    modelName: String,
    createdAt: Date = Date(),
    fileCount: Int,
    chunkCount: Int,
    embeddingDimension: Int,
    indexedCharacterCount: Int
  ) {
    self.workspacePath = workspacePath
    self.modelID = modelID
    self.modelName = modelName
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
  public let embedding: [Float]

  public init(
    id: UUID = UUID(),
    relativePath: String,
    startLine: Int,
    endLine: Int,
    text: String,
    embedding: [Float]
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
    version: Int = 1,
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
