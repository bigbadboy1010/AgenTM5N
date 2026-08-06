import Foundation

public enum PromptAttachmentKind: String, Codable, Equatable, Sendable {
  case text
  case image
}

public enum PromptDocumentKind: String, Codable, Equatable, Sendable {
  case plainText
  case pdf
  case docx
  case xlsx
  case pptx

  public var displayName: String {
    switch self {
    case .plainText: "Text"
    case .pdf: "PDF"
    case .docx: "Word"
    case .xlsx: "Excel"
    case .pptx: "PowerPoint"
    }
  }
}

public enum PromptExtractionMethod: String, Codable, Equatable, Sendable {
  case directText
  case pdfText
  case officeOpenXML
  case visionOCR
}

public struct PromptAttachmentSection: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public let locator: String
  public let title: String?
  public let text: String

  public init(
    id: UUID = UUID(),
    locator: String,
    title: String? = nil,
    text: String
  ) {
    self.id = id
    self.locator = locator
    self.title = title
    self.text = text
  }
}

public struct PromptAttachmentMetadata: Codable, Equatable, Sendable {
  public let documentKind: PromptDocumentKind
  public let extractionMethod: PromptExtractionMethod
  public let sectionCount: Int
  public let pageCount: Int?
  public let sheetCount: Int?
  public let slideCount: Int?
  public let ocrUsed: Bool
  public let cacheHit: Bool
  public let sourceSHA256: String?

  public init(
    documentKind: PromptDocumentKind,
    extractionMethod: PromptExtractionMethod,
    sectionCount: Int,
    pageCount: Int? = nil,
    sheetCount: Int? = nil,
    slideCount: Int? = nil,
    ocrUsed: Bool = false,
    cacheHit: Bool = false,
    sourceSHA256: String? = nil
  ) {
    self.documentKind = documentKind
    self.extractionMethod = extractionMethod
    self.sectionCount = sectionCount
    self.pageCount = pageCount
    self.sheetCount = sheetCount
    self.slideCount = slideCount
    self.ocrUsed = ocrUsed
    self.cacheHit = cacheHit
    self.sourceSHA256 = sourceSHA256
  }

  public func withCacheHit(_ cacheHit: Bool) -> PromptAttachmentMetadata {
    PromptAttachmentMetadata(
      documentKind: documentKind,
      extractionMethod: extractionMethod,
      sectionCount: sectionCount,
      pageCount: pageCount,
      sheetCount: sheetCount,
      slideCount: slideCount,
      ocrUsed: ocrUsed,
      cacheHit: cacheHit,
      sourceSHA256: sourceSHA256
    )
  }
}

public struct PromptAttachment: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let name: String
  public let byteCount: Int
  public let mediaType: String
  public let kind: PromptAttachmentKind
  public let extractedText: String
  public let imageData: Data?
  public let pixelWidth: Int?
  public let pixelHeight: Int?
  public let wasTruncated: Bool
  public let sections: [PromptAttachmentSection]
  public let metadata: PromptAttachmentMetadata?

  public init(
    id: UUID = UUID(),
    name: String,
    byteCount: Int,
    mediaType: String,
    kind: PromptAttachmentKind = .text,
    extractedText: String = "",
    imageData: Data? = nil,
    pixelWidth: Int? = nil,
    pixelHeight: Int? = nil,
    wasTruncated: Bool = false,
    sections: [PromptAttachmentSection] = [],
    metadata: PromptAttachmentMetadata? = nil
  ) {
    self.id = id
    self.name = name
    self.byteCount = byteCount
    self.mediaType = mediaType
    self.kind = kind
    self.extractedText = extractedText
    self.imageData = imageData
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.wasTruncated = wasTruncated
    self.sections = sections
    self.metadata = metadata
  }

  public var isImage: Bool {
    kind == .image
  }

  public var sizeDescription: String {
    ByteCountFormatter.string(
      fromByteCount: Int64(byteCount),
      countStyle: .file
    )
  }

  public var dimensionsDescription: String? {
    guard let pixelWidth, let pixelHeight else { return nil }
    return "\(pixelWidth) × \(pixelHeight)"
  }

  public var sourceCountDescription: String? {
    guard let metadata else { return nil }
    switch metadata.documentKind {
    case .docx, .plainText:
      return "\(metadata.sectionCount) Abschnitte"
    case .pdf:
      return metadata.pageCount.map { "\($0) Seiten" }
    case .xlsx:
      return metadata.sheetCount.map { "\($0) Tabellenblätter" }
    case .pptx:
      return metadata.slideCount.map { "\($0) Folien" }
    }
  }
}

public struct PromptImageReference: Equatable, Sendable {
  public let id: UUID
  public let name: String
  public let mediaType: String
  public let byteCount: Int
  public let relativePath: String
  public let pixelWidth: Int
  public let pixelHeight: Int

  public init(
    id: UUID,
    name: String,
    mediaType: String,
    byteCount: Int,
    relativePath: String,
    pixelWidth: Int,
    pixelHeight: Int
  ) {
    self.id = id
    self.name = name
    self.mediaType = mediaType
    self.byteCount = byteCount
    self.relativePath = relativePath
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }
}
