import Combine
import Foundation

@MainActor
public final class PromptAttachmentDraftStore: ObservableObject {
  public static let shared = PromptAttachmentDraftStore()

  @Published public private(set) var attachments: [PromptAttachment] = []

  private init() {}

  public var extractedCharacterCount: Int {
    attachments.reduce(0) { partial, attachment in
      partial + (attachment.kind == .text ? attachment.extractedText.count : 0)
    }
  }

  public var imageByteCount: Int {
    attachments.reduce(0) { partial, attachment in
      partial + (attachment.kind == .image ? attachment.byteCount : 0)
    }
  }

  public var imageCount: Int {
    attachments.filter { $0.kind == .image }.count
  }

  public func add(_ newAttachments: [PromptAttachment]) {
    attachments.append(contentsOf: newAttachments)
  }

  public func remove(id: UUID) {
    attachments.removeAll { $0.id == id }
  }

  public func removeAll() {
    attachments.removeAll()
  }
}
