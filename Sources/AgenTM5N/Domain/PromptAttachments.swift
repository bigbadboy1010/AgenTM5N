import Foundation

public struct PromptAttachment: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let name: String
  public let byteCount: Int
  public let mediaType: String
  public let extractedText: String
  public let wasTruncated: Bool

  public init(
    id: UUID = UUID(),
    name: String,
    byteCount: Int,
    mediaType: String,
    extractedText: String,
    wasTruncated: Bool
  ) {
    self.id = id
    self.name = name
    self.byteCount = byteCount
    self.mediaType = mediaType
    self.extractedText = extractedText
    self.wasTruncated = wasTruncated
  }

  public var sizeDescription: String {
    ByteCountFormatter.string(
      fromByteCount: Int64(byteCount),
      countStyle: .file
    )
  }
}
