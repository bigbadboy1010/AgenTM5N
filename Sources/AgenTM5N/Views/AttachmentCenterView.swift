import AppKit
import SwiftUI

struct AttachmentCenterView: View {
  @EnvironmentObject private var appState: AppState
  @ObservedObject private var attachmentStore = PromptAttachmentDraftStore.shared
  @State private var inspectedAttachment: PromptAttachment?
  @State private var isImporting = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
    }
    .navigationTitle(
      L10n.text(
        de: "Anhangscenter",
        en: "Attachment Center",
        fr: "Centre des pièces jointes"
      )
    )
    .sheet(item: $inspectedAttachment) { attachment in
      AttachmentInspectorView(attachment: attachment)
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(
          L10n.text(
            de: "Anhänge des aktuellen Promptentwurfs",
            en: "Attachments in the Current Prompt Draft",
            fr: "Pièces jointes du brouillon actuel"
          )
        )
        .font(.headline)

        Text(statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button {
        importFiles()
      } label: {
        if isImporting {
          ProgressView()
            .controlSize(.small)
        } else {
          Label(
            L10n.text(de: "Anhängen", en: "Attach", fr: "Joindre"),
            systemImage: "paperclip"
          )
        }
      }
      .disabled(isImporting || appState.isGenerating)

      Button {
        appState.selectedSection = .chat
      } label: {
        Label(
          L10n.text(de: "Zum Chat", en: "Back to Chat", fr: "Retour au chat"),
          systemImage: "bubble.left.and.bubble.right"
        )
      }
    }
    .padding(18)
  }

  @ViewBuilder
  private var content: some View {
    if attachmentStore.attachments.isEmpty {
      ContentUnavailableView(
        L10n.text(
          de: "Keine Anhänge im Entwurf",
          en: "No Draft Attachments",
          fr: "Aucune pièce jointe dans le brouillon"
        ),
        systemImage: "paperclip",
        description: Text(
          L10n.text(
            de: "Füge Text-, PDF-, Word-, Excel-, PowerPoint- oder Bilddateien hinzu. Die Dateien bleiben im Promptentwurf, wenn du zwischen Chat und Anhangscenter wechselst.",
            en: "Add text, PDF, Word, Excel, PowerPoint, or image files. Files remain in the prompt draft when switching between Chat and Attachment Center.",
            fr: "Ajoutez des fichiers texte, PDF, Word, Excel, PowerPoint ou image. Ils restent dans le brouillon lorsque vous changez de vue."
          )
        )
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(attachmentStore.attachments) { attachment in
            attachmentCard(attachment)
          }
        }
        .padding(18)
      }
    }
  }

  private func attachmentCard(_ attachment: PromptAttachment) -> some View {
    HStack(alignment: .top, spacing: 14) {
      preview(for: attachment)

      VStack(alignment: .leading, spacing: 7) {
        Text(attachment.name)
          .font(.headline)
          .textSelection(.enabled)

        HStack(spacing: 8) {
          Text(attachment.mediaType)
          Text("·")
          Text(attachment.sizeDescription)
          if let dimensions = attachment.dimensionsDescription {
            Text("·")
            Text(dimensions)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        if let metadata = attachment.metadata {
          HStack(spacing: 8) {
            Label(metadata.documentKind.displayName, systemImage: "doc.text.magnifyingglass")
            if let sourceDescription = attachment.sourceCountDescription {
              Text("·")
              Text(sourceDescription)
            }
            if metadata.ocrUsed {
              Text("· OCR")
            }
            if metadata.cacheHit {
              Text("· Cache")
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        if attachment.wasTruncated {
          Label(
            L10n.text(
              de: "Extrahierter Inhalt wurde begrenzt.",
              en: "Extracted content was truncated.",
              fr: "Le contenu extrait a été limité."
            ),
            systemImage: "scissors"
          )
          .font(.caption)
          .foregroundStyle(.orange)
        }
      }

      Spacer(minLength: 12)

      VStack(alignment: .trailing, spacing: 8) {
        Button {
          inspectedAttachment = attachment
        } label: {
          Label(
            L10n.text(de: "Prüfen", en: "Inspect", fr: "Inspecter"),
            systemImage: "info.circle"
          )
        }

        Button(role: .destructive) {
          attachmentStore.remove(id: attachment.id)
        } label: {
          Label(
            L10n.text(de: "Entfernen", en: "Remove", fr: "Retirer"),
            systemImage: "trash"
          )
        }
      }
    }
    .padding(14)
    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
  }

  @ViewBuilder
  private func preview(for attachment: PromptAttachment) -> some View {
    if attachment.kind == .image,
      let data = attachment.imageData,
      let image = NSImage(data: data)
    {
      Image(nsImage: image)
        .resizable()
        .scaledToFill()
        .frame(width: 110, height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    } else {
      Image(systemName: documentIcon(for: attachment))
        .font(.system(size: 30))
        .frame(width: 76, height: 76)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
  }

  private var statusText: String {
    let count = attachmentStore.attachments.count
    let characters = attachmentStore.extractedCharacterCount
    let images = attachmentStore.imageCount
    return L10n.text(
      de: "\(count) Anhänge · \(characters) extrahierte Zeichen · \(images) Bilder",
      en: "\(count) attachments · \(characters) extracted characters · \(images) images",
      fr: "\(count) pièces jointes · \(characters) caractères extraits · \(images) images"
    )
  }

  private func documentIcon(for attachment: PromptAttachment) -> String {
    switch attachment.metadata?.documentKind {
    case .pdf:
      return "doc.richtext"
    case .docx:
      return "doc.text"
    case .xlsx:
      return "tablecells"
    case .pptx:
      return "rectangle.on.rectangle.angled"
    case .plainText, nil:
      return "doc.plaintext"
    }
  }

  private func importFiles() {
    guard !isImporting else { return }
    isImporting = true
    defer { isImporting = false }

    do {
      guard let imported = try PromptAttachmentService.selectPromptFiles(
        existingCount: attachmentStore.attachments.count,
        existingCharacterCount: attachmentStore.extractedCharacterCount,
        existingImageCount: attachmentStore.imageCount,
        existingImageBytes: attachmentStore.imageByteCount
      ) else {
        return
      }
      attachmentStore.add(imported)
    } catch {
      appState.errorMessage = error.localizedDescription
    }
  }
}
