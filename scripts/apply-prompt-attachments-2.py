#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"Expected one match in {path}, found {count}: {old[:160]!r}"
        )
    file.write_text(text.replace(old, new, 1), encoding="utf-8")


chat = "Sources/AgenTM5N/Views/ChatView.swift"
replace_once(
    chat,
    '''import SwiftUI

struct ChatView: View {
  @EnvironmentObject private var appState: AppState
  @ObservedObject private var attachmentStore = PromptAttachmentDraftStore.shared
''',
    '''import AppKit
import SwiftUI

struct ChatView: View {
  @EnvironmentObject private var appState: AppState
  @ObservedObject private var attachmentStore = PromptAttachmentDraftStore.shared
  @State private var isDropTargeted = false
''',
)
replace_once(
    chat,
    '''      }
    }
    .padding(14)
  }

  private var canSend: Bool {''',
    '''      }
    }
    .padding(14)
    .background(
      isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear
    )
    .overlay {
      if isDropTargeted {
        RoundedRectangle(cornerRadius: 12)
          .stroke(
            Color.accentColor,
            style: StrokeStyle(lineWidth: 2, dash: [7, 5])
          )
          .padding(6)
          .allowsHitTesting(false)
      }
    }
    .dropDestination(for: URL.self) { urls, _ in
      importDroppedFiles(urls)
      return true
    } isTargeted: { targeted in
      isDropTargeted = targeted
    }
  }

  private var canSend: Bool {''',
)
replace_once(
    chat,
    '''  private func sendCurrentPrompt() {
    guard canSend else { return }
    appState.inputText = PromptAttachmentService.providerContent(
      prompt: appState.inputText,
      attachments: attachmentStore.attachments
    )
    attachmentStore.removeAll()
    appState.sendMessage()
  }
''',
    '''  private func sendCurrentPrompt() {
    guard canSend else { return }
    do {
      appState.inputText = try PromptAttachmentService.prepareProviderContent(
        prompt: appState.inputText,
        attachments: attachmentStore.attachments
      )
      attachmentStore.removeAll()
      appState.sendMessage()
    } catch {
      appState.errorMessage = error.localizedDescription
    }
  }

  private func importDroppedFiles(_ urls: [URL]) {
    do {
      let imported = try PromptAttachmentService.importPromptFiles(
        urls,
        existingCount: attachmentStore.attachments.count,
        existingCharacterCount: attachmentStore.extractedCharacterCount,
        existingImageCount: attachmentStore.imageCount,
        existingImageBytes: attachmentStore.imageByteCount
      )
      attachmentStore.add(imported)
    } catch {
      appState.errorMessage = error.localizedDescription
    }
  }
''',
)
replace_once(
    chat,
    '''private struct AttachmentDraftChip: View {
  let attachment: PromptAttachment
  let removeAction: () -> Void

  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: attachment.mediaType == "application/pdf" ? "doc.richtext" : "doc.text")
      VStack(alignment: .leading, spacing: 1) {
        Text(attachment.name)
          .font(.caption)
          .lineLimit(1)
        Text(attachment.sizeDescription)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Button(action: removeAction) {
        Image(systemName: "xmark.circle.fill")
      }
      .buttonStyle(.plain)
      .help(L10n.text(de: "Anhang entfernen", en: "Remove Attachment", fr: "Retirer la pièce jointe"))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
  }
}
''',
    '''private struct AttachmentDraftChip: View {
  let attachment: PromptAttachment
  let removeAction: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      if attachment.kind == .image,
        let data = attachment.imageData,
        let image = NSImage(data: data)
      {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: 44, height: 44)
          .clipShape(RoundedRectangle(cornerRadius: 7))
      } else {
        Image(
          systemName: attachment.mediaType == "application/pdf"
            ? "doc.richtext"
            : "doc.text"
        )
        .frame(width: 28)
      }

      VStack(alignment: .leading, spacing: 1) {
        Text(attachment.name)
          .font(.caption)
          .lineLimit(1)
        HStack(spacing: 5) {
          Text(attachment.sizeDescription)
          if let dimensions = attachment.dimensionsDescription {
            Text("·")
            Text(dimensions)
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      Button(action: removeAction) {
        Image(systemName: "xmark.circle.fill")
      }
      .buttonStyle(.plain)
      .help(
        L10n.text(
          de: "Anhang entfernen",
          en: "Remove Attachment",
          fr: "Retirer la pièce jointe"
        )
      )
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
  }
}
''',
)
replace_once(
    chat,
    '''  private var bubble: some View {
    let visibleContent = PromptAttachmentService.visiblePrompt(from: message.content)
    let attachmentNames = PromptAttachmentService.attachmentNames(from: message.content)

    return VStack(alignment: .leading, spacing: 10) {''',
    '''  private var bubble: some View {
    let visibleContent = PromptAttachmentService.visiblePrompt(from: message.content)
    let textAttachmentNames = PromptAttachmentService.textAttachmentNames(
      from: message.content
    )
    let imageReferences = PromptAttachmentService.imageReferences(
      from: message.content
    )

    return VStack(alignment: .leading, spacing: 10) {''',
)
replace_once(
    chat,
    '''      if !attachmentNames.isEmpty {
        FlowLayout(spacing: 6) {
          ForEach(attachmentNames, id: \.self) { name in
            Label(name, systemImage: "paperclip")
              .font(.caption2)
              .lineLimit(1)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(.quaternary, in: Capsule())
          }
        }
      }
''',
    '''      if !textAttachmentNames.isEmpty {
        FlowLayout(spacing: 6) {
          ForEach(textAttachmentNames, id: \.self) { name in
            Label(name, systemImage: "paperclip")
              .font(.caption2)
              .lineLimit(1)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(.quaternary, in: Capsule())
          }
        }
      }

      if !imageReferences.isEmpty {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 180), spacing: 8)],
          alignment: .leading,
          spacing: 8
        ) {
          ForEach(imageReferences, id: \.id) { reference in
            ChatImageAttachmentPreview(reference: reference)
          }
        }
      }
''',
)
replace_once(
    chat,
    '''    .frame(maxWidth: 820, alignment: .leading)
  }
}

private struct FlowLayout<Content: View>: View {''',
    '''    .frame(maxWidth: 820, alignment: .leading)
  }
}

private struct ChatImageAttachmentPreview: View {
  let reference: PromptImageReference
  @State private var image: NSImage?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Group {
        if let image {
          Image(nsImage: image)
            .resizable()
            .scaledToFit()
        } else {
          ZStack {
            Rectangle()
              .fill(.quaternary)
            Image(systemName: "photo.badge.exclamationmark")
              .font(.title2)
              .foregroundStyle(.secondary)
          }
        }
      }
      .frame(maxWidth: 300, minHeight: 110, maxHeight: 230)
      .clipShape(RoundedRectangle(cornerRadius: 9))

      HStack(spacing: 6) {
        Text(reference.name)
          .font(.caption)
          .lineLimit(1)
        Spacer(minLength: 4)
        Text("\(reference.pixelWidth) × \(reference.pixelHeight)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(8)
    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    .task(id: reference.id) {
      guard let url = PromptImageAttachmentStorage.imageURL(for: reference) else {
        return
      }
      image = NSImage(contentsOf: url)
    }
  }
}

private struct FlowLayout<Content: View>: View {''',
)

app = "Sources/AgenTM5N/App/AppState.swift"
replace_once(
    app,
    '''  public func resetConversation() async {
    stopGeneration()
    messages = []
    latestMetrics = nil
    do {
      try await conversationStore.save(messages)
    } catch {
      present(error)
    }
  }''',
    '''  public func resetConversation() async {
    stopGeneration()
    messages = []
    latestMetrics = nil
    do {
      try PromptImageAttachmentStorage.removeAll()
      try await conversationStore.save(messages)
    } catch {
      present(error)
    }
  }''',
)
replace_once(
    app,
    '''      case .appleOnDevice:
        let providerMessages = makeAppleMessages(excludingAssistantID: assistantID)
        let event = try await appleProvider.complete(''',
    '''      case .appleOnDevice:
        if PromptAttachmentService.hasImageAttachments(in: text) {
          throw PromptAttachmentError.imageProviderUnsupported
        }
        let providerMessages = makeAppleMessages(excludingAssistantID: assistantID)
        let event = try await appleProvider.complete(''',
)
replace_once(
    app,
    '''  private func performOllamaSend(assistantID: UUID) async throws {
    let apiKey = try await configuredAPIKey()
    var providerMessages = makeOllamaMessages(excludingAssistantID: assistantID)
    let tools = configuration.agentEnabled''',
    '''  private func performOllamaSend(assistantID: UUID) async throws {
    let apiKey = try await configuredAPIKey()
    var providerMessages = makeOllamaMessages(excludingAssistantID: assistantID)

    if providerMessages.contains(where: {
      PromptAttachmentService.hasImageAttachments(in: $0.content)
    }) {
      let capabilities = try await ollamaProvider.modelCapabilities(
        configuration: configuration,
        apiKey: apiKey
      )
      guard capabilities.contains("vision") else {
        throw PromptAttachmentError.modelDoesNotSupportVision(
          configuration.model
        )
      }
    }

    let tools = configuration.agentEnabled''',
)

ollama = "Sources/AgenTM5N/Providers/OllamaProvider.swift"
replace_once(
    ollama,
    '''  private struct ChatRequestBody: Encodable {
    let model: String
    let messages: [ProviderMessage]
    let tools: [ProviderToolDefinition]?
    let stream: Bool
    let think: Bool
  }
''',
    '''  private struct ChatRequestBody: Encodable {
    let model: String
    let messages: [OllamaRequestMessage]
    let tools: [ProviderToolDefinition]?
    let stream: Bool
    let think: Bool
  }

  private struct OllamaRequestMessage: Encodable {
    let role: ProviderMessageRole
    let content: String
    let thinking: String?
    let toolCalls: [ProviderToolCall]?
    let toolName: String?
    let images: [String]?

    init(_ message: ProviderMessage) throws {
      role = message.role
      content = message.content
      thinking = message.thinking
      toolCalls = message.toolCalls
      toolName = message.toolName

      let references = PromptAttachmentService.imageReferences(
        from: message.content
      )
      images = references.isEmpty
        ? nil
        : try references.map { reference in
          try PromptImageAttachmentStorage.data(for: reference)
            .base64EncodedString()
        }
    }

    private enum CodingKeys: String, CodingKey {
      case role
      case content
      case thinking
      case toolCalls = "tool_calls"
      case toolName = "tool_name"
      case images
    }
  }
''',
)
replace_once(
    ollama,
    '''  private struct TagsResponse: Decodable {
    let models: [Model]

    struct Model: Decodable {
      let name: String
    }
  }

  private let session: URLSession''',
    '''  private struct TagsResponse: Decodable {
    let models: [Model]

    struct Model: Decodable {
      let name: String
    }
  }

  private struct ShowRequest: Encodable {
    let model: String
    let verbose = false
  }

  private struct ShowResponse: Decodable {
    let capabilities: [String]?
  }

  private let session: URLSession''',
)
replace_once(
    ollama,
    '''    let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
    return decoded.models.map(\.name).sorted()
  }

  public func streamChat(''',
    '''    let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
    return decoded.models.map(\.name).sorted()
  }

  public func modelCapabilities(
    configuration: AppConfiguration,
    apiKey: String?
  ) async throws -> Set<String> {
    let model = configuration.model.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !model.isEmpty else {
      throw OllamaProviderError.emptyModel
    }

    let url = try endpointURL(
      baseURL: configuration.baseURL,
      path: "/api/show"
    )
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    applyAuthorization(apiKey: apiKey, to: &request)
    request.httpBody = try JSONEncoder().encode(ShowRequest(model: model))

    let (data, response) = try await session.data(for: request)
    try validate(response: response, body: data)
    let decoded = try JSONDecoder().decode(ShowResponse.self, from: data)
    return Set((decoded.capabilities ?? []).map { $0.lowercased() })
  }

  public func streamChat(''',
)
replace_once(
    ollama,
    '''          let requestMessages = enrichedMessages(
            messages,
            configuration: configuration,
            tools: tools
          )
          let body = ChatRequestBody(''',
    '''          let providerMessages = enrichedMessages(
            messages,
            configuration: configuration,
            tools: tools
          )
          let requestMessages = try providerMessages.map(
            OllamaRequestMessage.init
          )
          let body = ChatRequestBody(''',
)

build = "scripts/build-app.sh"
replace_once(build, 'VERSION="0.4.2"', 'VERSION="0.5.0"')
replace_once(build, 'BUILD_NUMBER="14"', 'BUILD_NUMBER="15"')
