import Combine
import Foundation

@MainActor
public final class PromptAttachmentDraftStore: ObservableObject {
  public static let shared = PromptAttachmentDraftStore()

  @Published public private(set) var attachments: [PromptAttachment] = []

  private init() {}

  public var extractedCharacterCount: Int {
    attachments.reduce(0) { $0 + $1.extractedText.count }
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
