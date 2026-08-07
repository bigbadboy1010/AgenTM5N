import Foundation

public struct KnowledgeCollection: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var isEnabled: Bool
  public let createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID = UUID(),
    name: String,
    isEnabled: Bool = true,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.isEnabled = isEnabled
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct KnowledgeDocumentSummary: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public let collectionID: UUID
  public var name: String
  public var mediaType: String
  public var byteCount: Int
  public var documentKind: PromptDocumentKind
  public var sectionCount: Int
  public var isEnabled: Bool
  public let importedAt: Date
  public var updatedAt: Date
  public var sourceSHA256: String
  public var sourceRelativePath: String
  public var documentRelativePath: String

  public init(
    id: UUID = UUID(),
    collectionID: UUID,
    name: String,
    mediaType: String,
    byteCount: Int,
    documentKind: PromptDocumentKind,
    sectionCount: Int,
    isEnabled: Bool = true,
    importedAt: Date = Date(),
    updatedAt: Date = Date(),
    sourceSHA256: String,
    sourceRelativePath: String,
    documentRelativePath: String
  ) {
    self.id = id
    self.collectionID = collectionID
    self.name = name
    self.mediaType = mediaType
    self.byteCount = byteCount
    self.documentKind = documentKind
    self.sectionCount = sectionCount
    self.isEnabled = isEnabled
    self.importedAt = importedAt
    self.updatedAt = updatedAt
    self.sourceSHA256 = sourceSHA256
    self.sourceRelativePath = sourceRelativePath
    self.documentRelativePath = documentRelativePath
  }

  public var sizeDescription: String {
    ByteCountFormatter.string(
      fromByteCount: Int64(byteCount),
      countStyle: .file
    )
  }
}

public struct KnowledgeDocumentRecord: Codable, Equatable, Sendable {
  public var summary: KnowledgeDocumentSummary
  public var extractedText: String
  public var sections: [PromptAttachmentSection]
  public var metadata: PromptAttachmentMetadata

  public init(
    summary: KnowledgeDocumentSummary,
    extractedText: String,
    sections: [PromptAttachmentSection],
    metadata: PromptAttachmentMetadata
  ) {
    self.summary = summary
    self.extractedText = extractedText
    self.sections = sections
    self.metadata = metadata
  }
}

public struct KnowledgeLibraryRegistry: Codable, Equatable, Sendable {
  public var collections: [KnowledgeCollection]
  public var documents: [KnowledgeDocumentSummary]

  public init(
    collections: [KnowledgeCollection] = [],
    documents: [KnowledgeDocumentSummary] = []
  ) {
    self.collections = collections
    self.documents = documents
  }
}

public struct KnowledgeLibrarySnapshot: Equatable, Sendable {
  public let collections: [KnowledgeCollection]
  public let documents: [KnowledgeDocumentSummary]

  public init(
    collections: [KnowledgeCollection],
    documents: [KnowledgeDocumentSummary]
  ) {
    self.collections = collections
    self.documents = documents
  }
}

public struct KnowledgeSearchMatch: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let documentID: UUID
  public let collectionID: UUID
  public let documentName: String
  public let collectionName: String
  public let locator: String
  public let score: Int
  public let excerpt: String

  public init(
    id: UUID = UUID(),
    documentID: UUID,
    collectionID: UUID,
    documentName: String,
    collectionName: String,
    locator: String,
    score: Int,
    excerpt: String
  ) {
    self.id = id
    self.documentID = documentID
    self.collectionID = collectionID
    self.documentName = documentName
    self.collectionName = collectionName
    self.locator = locator
    self.score = score
    self.excerpt = excerpt
  }
}

public struct KnowledgeReadResult: Equatable, Sendable {
  public let documentID: UUID
  public let collectionID: UUID
  public let documentName: String
  public let collectionName: String
  public let locator: String
  public let content: String
  public let truncated: Bool

  public init(
    documentID: UUID,
    collectionID: UUID,
    documentName: String,
    collectionName: String,
    locator: String,
    content: String,
    truncated: Bool
  ) {
    self.documentID = documentID
    self.collectionID = collectionID
    self.documentName = documentName
    self.collectionName = collectionName
    self.locator = locator
    self.content = content
    self.truncated = truncated
  }
}

public enum KnowledgeImportStatus: String, Codable, Equatable, Sendable {
  case imported
  case updated
  case duplicate
}

public struct KnowledgeImportResult: Equatable, Sendable {
  public let status: KnowledgeImportStatus
  public let document: KnowledgeDocumentSummary

  public init(status: KnowledgeImportStatus, document: KnowledgeDocumentSummary) {
    self.status = status
    self.document = document
  }
}
