import Foundation

public enum GeneratedDocumentFormat: String, Codable, CaseIterable, Identifiable, Sendable {
  case docx
  case pdf
  case xlsx
  case pptx

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .docx: "Word (.docx)"
    case .pdf: "PDF (.pdf)"
    case .xlsx: "Excel (.xlsx)"
    case .pptx: "PowerPoint (.pptx)"
    }
  }

  public var fileExtension: String { rawValue }

  public var mediaType: String {
    switch self {
    case .docx:
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    case .pdf:
      "application/pdf"
    case .xlsx:
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    case .pptx:
      "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    }
  }
}

public struct GeneratedDocumentSummary: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var title: String
  public var fileName: String
  public var format: GeneratedDocumentFormat
  public var byteCount: Int
  public var relativePath: String
  public let createdAt: Date

  public init(
    id: UUID = UUID(),
    title: String,
    fileName: String,
    format: GeneratedDocumentFormat,
    byteCount: Int,
    relativePath: String,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.fileName = fileName
    self.format = format
    self.byteCount = byteCount
    self.relativePath = relativePath
    self.createdAt = createdAt
  }

  public var sizeDescription: String {
    ByteCountFormatter.string(
      fromByteCount: Int64(byteCount),
      countStyle: .file
    )
  }
}

public struct GeneratedDocumentRegistry: Codable, Equatable, Sendable {
  public var documents: [GeneratedDocumentSummary]

  public init(documents: [GeneratedDocumentSummary] = []) {
    self.documents = documents
  }
}

public struct GeneratedDocumentRequest: Equatable, Sendable {
  public let format: GeneratedDocumentFormat
  public let title: String
  public let fileName: String?
  public let content: String

  public init(
    format: GeneratedDocumentFormat,
    title: String,
    fileName: String? = nil,
    content: String
  ) {
    self.format = format
    self.title = title
    self.fileName = fileName
    self.content = content
  }
}

public struct GeneratedPresentationSlide: Equatable, Sendable {
  public let title: String
  public let body: String

  public init(title: String, body: String) {
    self.title = title
    self.body = body
  }
}
