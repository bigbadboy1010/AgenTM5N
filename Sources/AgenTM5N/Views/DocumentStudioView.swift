import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class DocumentStudioModel: ObservableObject {
  @Published var documents: [GeneratedDocumentSummary] = []
  @Published var selectedDocumentID: UUID?
  @Published var format: GeneratedDocumentFormat = .docx
  @Published var title = ""
  @Published var fileName = ""
  @Published var content = ""
  @Published var isWorking = false
  @Published var errorMessage: String?

  private let service: GeneratedDocumentService

  init(service: GeneratedDocumentService = .shared) {
    self.service = service
    Task { await reload() }
  }

  var selectedDocument: GeneratedDocumentSummary? {
    documents.first(where: { $0.id == selectedDocumentID })
  }

  var contentHint: String {
    switch format {
    case .docx, .pdf:
      return L10n.text(
        de: "Text oder einfaches Markdown: # Überschrift, ## Untertitel, - Aufzählung",
        en: "Text or simple Markdown: # Heading, ## Subheading, - Bullet",
        fr: "Texte ou Markdown simple : # Titre, ## Sous-titre, - Puce"
      )
    case .xlsx:
      return L10n.text(
        de: "Tabelleninhalt als TSV oder CSV. Die erste Zeile wird als Kopfzeile formatiert.",
        en: "Spreadsheet content as TSV or CSV. The first row is formatted as a header.",
        fr: "Contenu du tableur au format TSV ou CSV. La première ligne devient l’en-tête."
      )
    case .pptx:
      return L10n.text(
        de: "Folien mit einer Zeile --- trennen. Erste Zeile = Folientitel, danach Inhalt.",
        en: "Separate slides with a line containing ---. First line = slide title, remaining lines = body.",
        fr: "Séparez les diapositives par une ligne ---. Première ligne = titre, puis contenu."
      )
    }
  }

  func reload() async {
    do {
      documents = try await service.list()
      if let selectedDocumentID,
        !documents.contains(where: { $0.id == selectedDocumentID })
      {
        self.selectedDocumentID = documents.first?.id
      } else if selectedDocumentID == nil {
        selectedDocumentID = documents.first?.id
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func generate() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let request = GeneratedDocumentRequest(
        format: format,
        title: title,
        fileName: fileName.isEmpty ? nil : fileName,
        content: content
      )
      let generated = try await service.generate(request: request)
      await reload()
      selectedDocumentID = generated.id
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func deleteSelected() async {
    guard let selectedDocumentID, !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      try await service.delete(id: selectedDocumentID)
      self.selectedDocumentID = nil
      await reload()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func exportSelected() async {
    guard let selected = selectedDocument, !isWorking else { return }
    let panel = NSSavePanel()
    panel.title = L10n.text(
      de: "Dokument exportieren",
      en: "Export Document",
      fr: "Exporter le document"
    )
    panel.nameFieldStringValue = selected.fileName
    if let type = UTType(filenameExtension: selected.format.fileExtension) {
      panel.allowedContentTypes = [type]
    }
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }

    isWorking = true
    defer { isWorking = false }
    do {
      try await service.export(id: selected.id, to: url)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func loadExample() {
    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      title = L10n.text(
        de: "AgenTM5N Beispieldokument",
        en: "AgenTM5N Example Document",
        fr: "Document d’exemple AgenTM5N"
      )
    }
    switch format {
    case .docx, .pdf:
      content = """
      # Zusammenfassung
      Dieses Dokument wurde lokal mit AgenTM5N erzeugt.

      ## Funktionen
      - Lokale Dokumentgenerierung
      - Kein Cloud-Dateidienst erforderlich
      - Export über den macOS-Speicherdialog
      """
    case .xlsx:
      content = """
      Bereich\tStatus\tWert
      Dokumente\tFertig\t4
      Kontext\tFertig\t3
      Agent\tAktiv\t1
      """
    case .pptx:
      content = """
      AgenTM5N Document Studio
      Lokale Dokumentgenerierung
      ---
      Unterstützte Formate
      - DOCX
      - PDF
      - XLSX
      - PPTX
      ---
      Sicherheit
      - Lokale Verarbeitung
      - Keine Makros
      - Keine externen Links
      """
    }
  }
}

struct DocumentStudioView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model = DocumentStudioModel()

  var body: some View {
    NavigationSplitView {
      documentList
        .navigationTitle(
          L10n.text(
            de: "Generierte Dokumente",
            en: "Generated Documents",
            fr: "Documents générés"
          )
        )
        .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 380)
    } detail: {
      editor
    }
    .navigationSplitViewStyle(.balanced)
    .toolbar {
      ToolbarItemGroup {
        Button {
          Task { await model.reload() }
        } label: {
          Label(
            L10n.text(de: "Aktualisieren", en: "Refresh", fr: "Actualiser"),
            systemImage: "arrow.clockwise"
          )
        }
        .disabled(model.isWorking)

        Button {
          Task { await model.exportSelected() }
        } label: {
          Label(
            L10n.text(de: "Exportieren…", en: "Export…", fr: "Exporter…"),
            systemImage: "square.and.arrow.down"
          )
        }
        .disabled(model.selectedDocument == nil || model.isWorking)

        Button(role: .destructive) {
          Task { await model.deleteSelected() }
        } label: {
          Label(
            L10n.text(de: "Löschen", en: "Delete", fr: "Supprimer"),
            systemImage: "trash"
          )
        }
        .disabled(model.selectedDocument == nil || model.isWorking)

        Button {
          dismiss()
        } label: {
          Label(
            L10n.text(de: "Zum Chat", en: "Back to Chat", fr: "Retour au chat"),
            systemImage: "bubble.left.and.bubble.right"
          )
        }
        .keyboardShortcut(.cancelAction)
      }
    }
    .alert(
      L10n.text(de: "Fehler", en: "Error", fr: "Erreur"),
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { visible in if !visible { model.errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
  }

  private var documentList: some View {
    List(selection: $model.selectedDocumentID) {
      if model.documents.isEmpty {
        VStack(spacing: 10) {
          Image(systemName: "doc.badge.plus")
            .font(.title)
          Text(
            L10n.text(
              de: "Noch keine Dokumente",
              en: "No Documents Yet",
              fr: "Aucun document"
            )
          )
          .font(.headline)
          Text(
            L10n.text(
              de: "Erzeuge rechts ein Dokument oder lasse den Agent document_generate verwenden.",
              en: "Create a document on the right or let the agent use document_generate.",
              fr: "Créez un document à droite ou laissez l’agent utiliser document_generate."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
      } else {
        ForEach(model.documents) { document in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Image(systemName: icon(for: document.format))
              Text(document.fileName)
                .font(.headline)
                .lineLimit(2)
            }
            Text("\(document.format.rawValue.uppercased()) · \(document.sizeDescription)")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(document.createdAt, style: .date)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 4)
          .tag(document.id)
        }
      }
    }
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(
          L10n.text(
            de: "Document Studio",
            en: "Document Studio",
            fr: "Document Studio"
          )
        )
        .font(.title2.bold())
        Spacer()
        if model.isWorking {
          ProgressView()
            .controlSize(.small)
        }
      }

      Picker(
        L10n.text(de: "Format", en: "Format", fr: "Format"),
        selection: $model.format
      ) {
        ForEach(GeneratedDocumentFormat.allCases) { format in
          Text(format.displayName).tag(format)
        }
      }
      .pickerStyle(.segmented)

      HStack {
        TextField(
          L10n.text(de: "Dokumenttitel", en: "Document title", fr: "Titre du document"),
          text: $model.title
        )
        TextField(
          L10n.text(
            de: "Dateiname optional",
            en: "Optional file name",
            fr: "Nom de fichier facultatif"
          ),
          text: $model.fileName
        )
        .frame(maxWidth: 260)
      }

      Text(model.contentHint)
        .font(.caption)
        .foregroundStyle(.secondary)

      TextEditor(text: $model.content)
        .font(.system(.body, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.25))
        }

      HStack {
        Button {
          model.loadExample()
        } label: {
          Label(
            L10n.text(de: "Beispiel", en: "Example", fr: "Exemple"),
            systemImage: "text.badge.plus"
          )
        }

        Spacer()

        Button {
          Task { await model.generate() }
        } label: {
          Label(
            L10n.text(de: "Dokument erzeugen", en: "Generate Document", fr: "Générer le document"),
            systemImage: "doc.badge.plus"
          )
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          model.isWorking
            || model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || model.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
      }

      if let selected = model.selectedDocument {
        Divider()
        HStack(spacing: 18) {
          Label(selected.fileName, systemImage: icon(for: selected.format))
          Text(selected.sizeDescription)
          Text(selected.format.mediaType)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Spacer()
          Text(selected.id.uuidString)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
    }
    .padding(20)
  }

  private func icon(for format: GeneratedDocumentFormat) -> String {
    switch format {
    case .docx: "doc.richtext"
    case .pdf: "doc.text"
    case .xlsx: "tablecells"
    case .pptx: "rectangle.on.rectangle"
    }
  }
}
