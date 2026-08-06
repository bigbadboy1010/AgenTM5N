import Foundation

public enum PromptAttachmentKind: String, Codable, Equatable, Sendable {
  case text
  case image
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
    wasTruncated: Bool = false
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
