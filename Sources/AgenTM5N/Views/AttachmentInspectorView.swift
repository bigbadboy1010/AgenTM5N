import AppKit
import SwiftUI

struct AttachmentInspectorView: View {
  @Environment(\.dismiss) private var dismiss
  let attachment: PromptAttachment

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          header
          metadataCard
          previewCard
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .navigationTitle(
        L10n.text(
          de: "Anhang prüfen",
          en: "Inspect Attachment",
          fr: "Inspecter la pièce jointe"
        )
      )
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(
            L10n.text(de: "Fertig", en: "Done", fr: "Terminé")
          ) {
            dismiss()
          }
        }
      }
    }
    .frame(minWidth: 720, minHeight: 620)
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      previewIcon
      VStack(alignment: .leading, spacing: 5) {
        Text(attachment.name)
          .font(.title3.bold())
          .textSelection(.enabled)
        Text(attachment.mediaType)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
        Text(attachment.sizeDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
  }

  @ViewBuilder
  private var previewIcon: some View {
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
      Image(systemName: documentIcon)
        .font(.system(size: 34))
        .frame(width: 76, height: 76)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
  }

  private var metadataCard: some View {
    GroupBox(
      L10n.text(
        de: "Extraktionsdetails",
        en: "Extraction Details",
        fr: "Détails de l’extraction"
      )
    ) {
      Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
        detailRow(
          L10n.text(de: "Typ", en: "Type", fr: "Type"),
          attachment.metadata?.documentKind.displayName
            ?? (attachment.kind == .image ? "Bild" : "Text")
        )
        detailRow(
          L10n.text(de: "Methode", en: "Method", fr: "Méthode"),
          extractionMethodTitle
        )
        detailRow(
          L10n.text(de: "Abschnitte", en: "Sections", fr: "Sections"),
          "\(attachment.sections.count)"
        )
        if let pages = attachment.metadata?.pageCount {
          detailRow(
            L10n.text(de: "Seiten", en: "Pages", fr: "Pages"),
            "\(pages)"
          )
        }
        if let sheets = attachment.metadata?.sheetCount {
          detailRow(
            L10n.text(de: "Tabellenblätter", en: "Worksheets", fr: "Feuilles"),
            "\(sheets)"
          )
        }
        if let slides = attachment.metadata?.slideCount {
          detailRow(
            L10n.text(de: "Folien", en: "Slides", fr: "Diapositives"),
            "\(slides)"
          )
        }
        detailRow(
          "OCR",
          yesNo(attachment.metadata?.ocrUsed == true)
        )
        detailRow(
          L10n.text(de: "Cache-Treffer", en: "Cache Hit", fr: "Cache utilisé"),
          yesNo(attachment.metadata?.cacheHit == true)
        )
        detailRow(
          L10n.text(de: "Gekürzt", en: "Truncated", fr: "Tronqué"),
          yesNo(attachment.wasTruncated)
        )
        detailRow(
          L10n.text(de: "Extrahierte Zeichen", en: "Extracted Characters", fr: "Caractères extraits"),
          "\(attachment.extractedText.count)"
        )
        if let dimensions = attachment.dimensionsDescription {
          detailRow(
            L10n.text(de: "Bildgröße", en: "Image Size", fr: "Taille d’image"),
            dimensions
          )
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  private var previewCard: some View {
    GroupBox(
      L10n.text(
        de: "Extrahierter Inhalt",
        en: "Extracted Content",
        fr: "Contenu extrait"
      )
    ) {
      VStack(alignment: .leading, spacing: 12) {
        if attachment.sections.isEmpty {
          Text(
            attachment.kind == .image
              ? L10n.text(
                de: "Im Bild wurde kein OCR-Text erkannt. Die Bilddaten werden direkt an ein visionfähiges Ollama-Modell übertragen.",
                en: "No OCR text was recognized in the image. Image data is sent directly to a vision-capable Ollama model.",
                fr: "Aucun texte OCR n’a été reconnu dans l’image. Les données sont envoyées directement à un modèle Ollama compatible vision."
              )
              : L10n.text(
                de: "Kein extrahierter Inhalt vorhanden.",
                en: "No extracted content is available.",
                fr: "Aucun contenu extrait n’est disponible."
              )
          )
          .foregroundStyle(.secondary)
        } else {
          ForEach(attachment.sections) { section in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(section.locator)
                  .font(.caption.bold())
                if let title = section.title, !title.isEmpty {
                  Text("— \(title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer()
              }
              Text(section.text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  private func detailRow(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label)
        .foregroundStyle(.secondary)
      Text(value)
        .textSelection(.enabled)
    }
  }

  private func yesNo(_ value: Bool) -> String {
    value
      ? L10n.text(de: "Ja", en: "Yes", fr: "Oui")
      : L10n.text(de: "Nein", en: "No", fr: "Non")
  }

  private var extractionMethodTitle: String {
    switch attachment.metadata?.extractionMethod {
    case .some(.directText):
      return L10n.text(de: "Direkter Text", en: "Direct Text", fr: "Texte direct")
    case .some(.pdfText):
      return L10n.text(de: "PDF-Textebene", en: "PDF Text Layer", fr: "Couche texte PDF")
    case .some(.officeOpenXML):
      return "Office Open XML"
    case .some(.visionOCR):
      return "Apple Vision OCR"
    case .none:
      return L10n.text(de: "Keine", en: "None", fr: "Aucune")
    }
  }

  private var documentIcon: String {
    switch attachment.metadata?.documentKind {
    case .some(.pdf): "doc.richtext"
    case .some(.docx): "doc.text"
    case .some(.xlsx): "tablecells"
    case .some(.pptx): "rectangle.on.rectangle.angled"
    case .some(.plainText), .none: "doc.plaintext"
    }
  }
}
