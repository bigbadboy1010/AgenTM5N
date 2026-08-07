import AppKit
import SwiftUI

@MainActor
final class KnowledgeLibraryViewModel: ObservableObject {
  @Published var snapshot = KnowledgeLibrarySnapshot(collections: [], documents: [])
  @Published var selectedCollectionID: UUID?
  @Published var selectedDocumentID: UUID?
  @Published var selectedRecord: KnowledgeDocumentRecord?
  @Published var searchQuery = ""
  @Published var searchResults: [KnowledgeSearchMatch] = []
  @Published var isWorking = false
  @Published var errorMessage: String?
  @Published var statusMessage: String?

  private let service: KnowledgeLibraryService

  init(service: KnowledgeLibraryService = .shared) {
    self.service = service
  }

  var selectedCollection: KnowledgeCollection? {
    snapshot.collections.first { $0.id == selectedCollectionID }
  }

  var documentsForSelectedCollection: [KnowledgeDocumentSummary] {
    guard let selectedCollectionID else { return [] }
    return snapshot.documents.filter { $0.collectionID == selectedCollectionID }
  }

  func refresh() async {
    do {
      let refreshed = try await service.snapshot()
      snapshot = refreshed
      if selectedCollectionID == nil
        || !refreshed.collections.contains(where: { $0.id == selectedCollectionID })
      {
        selectedCollectionID = refreshed.collections.first?.id
      }
      if let selectedDocumentID,
        !refreshed.documents.contains(where: { $0.id == selectedDocumentID })
      {
        self.selectedDocumentID = nil
        selectedRecord = nil
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func selectCollection(_ id: UUID) {
    selectedCollectionID = id
    selectedDocumentID = nil
    selectedRecord = nil
    searchResults = []
  }

  func createCollection(name: String) async {
    await perform {
      let collection = try await service.createCollection(name: name)
      await refresh()
      selectedCollectionID = collection.id
      statusMessage = L10n.text(
        de: "Wissenssammlung „\(collection.name)“ wurde erstellt.",
        en: "Knowledge collection “\(collection.name)” was created.",
        fr: "La collection « \(collection.name) » a été créée."
      )
    }
  }

  func renameSelectedCollection(name: String) async {
    guard let selectedCollectionID else { return }
    await perform {
      let collection = try await service.renameCollection(
        id: selectedCollectionID,
        name: name
      )
      await refresh()
      self.selectedCollectionID = collection.id
      statusMessage = L10n.text(
        de: "Wissenssammlung wurde umbenannt.",
        en: "Knowledge collection was renamed.",
        fr: "La collection a été renommée."
      )
    }
  }

  func toggleSelectedCollection() async {
    guard let collection = selectedCollection else { return }
    await perform {
      try await service.setCollectionEnabled(
        id: collection.id,
        enabled: !collection.isEnabled
      )
      await refresh()
      selectedCollectionID = collection.id
    }
  }

  func deleteSelectedCollection() async {
    guard let collection = selectedCollection else { return }
    await perform {
      try await service.deleteCollection(id: collection.id)
      selectedCollectionID = nil
      selectedDocumentID = nil
      selectedRecord = nil
      await refresh()
      statusMessage = L10n.text(
        de: "Wissenssammlung „\(collection.name)“ wurde gelöscht.",
        en: "Knowledge collection “\(collection.name)” was deleted.",
        fr: "La collection « \(collection.name) » a été supprimée."
      )
    }
  }

  func importFiles() async {
    guard let collection = selectedCollection else { return }
    let panel = NSOpenPanel()
    panel.title = L10n.text(
      de: "Dokumente in die Wissensbibliothek importieren",
      en: "Import Documents into Knowledge Library",
      fr: "Importer des documents dans la bibliothèque"
    )
    panel.prompt = L10n.text(de: "Importieren", en: "Import", fr: "Importer")
    panel.message = L10n.text(
      de: "Unterstützt werden Text-, Code-, PDF-, Word-, Excel- und PowerPoint-Dateien bis 25 MiB.",
      en: "Text, code, PDF, Word, Excel, and PowerPoint files up to 25 MiB are supported.",
      fr: "Les fichiers texte, code, PDF, Word, Excel et PowerPoint jusqu’à 25 Mio sont pris en charge."
    )
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.resolvesAliases = true

    guard panel.runModal() == .OK else { return }
    let urls = panel.urls
    await perform {
      let results = try await service.importDocuments(
        urls: urls,
        collectionQuery: collection.id.uuidString
      )
      await refresh()
      self.selectedCollectionID = collection.id
      let imported = results.filter { $0.status == .imported }.count
      let updated = results.filter { $0.status == .updated }.count
      let duplicates = results.filter { $0.status == .duplicate }.count
      statusMessage = L10n.text(
        de: "Import abgeschlossen: \(imported) neu, \(updated) aktualisiert, \(duplicates) Dubletten.",
        en: "Import complete: \(imported) new, \(updated) updated, \(duplicates) duplicates.",
        fr: "Import terminé : \(imported) nouveaux, \(updated) mis à jour, \(duplicates) doublons."
      )
    }
  }

  func selectDocument(_ id: UUID) async {
    selectedDocumentID = id
    do {
      selectedRecord = try await service.document(id: id)
      errorMessage = nil
    } catch {
      selectedRecord = nil
      errorMessage = error.localizedDescription
    }
  }

  func toggleDocument(_ document: KnowledgeDocumentSummary) async {
    await perform {
      try await service.setDocumentEnabled(
        id: document.id,
        enabled: !document.isEnabled
      )
      await refresh()
      selectedCollectionID = document.collectionID
      if selectedDocumentID == document.id {
        selectedRecord = try await service.document(id: document.id)
      }
    }
  }

  func deleteDocument(_ document: KnowledgeDocumentSummary) async {
    await perform {
      try await service.deleteDocument(id: document.id)
      selectedDocumentID = nil
      selectedRecord = nil
      await refresh()
      selectedCollectionID = document.collectionID
      statusMessage = L10n.text(
        de: "Wissensdokument „\(document.name)“ wurde gelöscht.",
        en: "Knowledge document “\(document.name)” was deleted.",
        fr: "Le document « \(document.name) » a été supprimé."
      )
    }
  }

  func search() async {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      searchResults = []
      return
    }
    do {
      searchResults = try await service.search(
        query: query,
        collectionQuery: selectedCollectionID?.uuidString,
        limit: 20
      )
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func openSearchResult(_ result: KnowledgeSearchMatch) async {
    selectedCollectionID = result.collectionID
    await selectDocument(result.documentID)
  }

  private func perform(_ operation: @escaping @MainActor () async throws -> Void) async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      try await operation()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

struct KnowledgeLibraryView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model = KnowledgeLibraryViewModel()
  @State private var showingCreateCollection = false
  @State private var showingRenameCollection = false
  @State private var collectionName = ""
  @State private var collectionPendingDeletion: KnowledgeCollection?
  @State private var documentPendingDeletion: KnowledgeDocumentSummary?

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      HSplitView {
        collectionsPane
          .frame(minWidth: 210, idealWidth: 240, maxWidth: 300)
        documentsPane
          .frame(minWidth: 360, idealWidth: 460)
        detailPane
          .frame(minWidth: 360, idealWidth: 480)
      }
    }
    .frame(minWidth: 1_050, minHeight: 700)
    .task {
      await model.refresh()
    }
    .sheet(isPresented: $showingCreateCollection) {
      collectionEditor(
        title: L10n.text(
          de: "Wissenssammlung erstellen",
          en: "Create Knowledge Collection",
          fr: "Créer une collection"
        ),
        actionTitle: L10n.text(de: "Erstellen", en: "Create", fr: "Créer")
      ) {
        let name = collectionName
        showingCreateCollection = false
        Task { await model.createCollection(name: name) }
      }
    }
    .sheet(isPresented: $showingRenameCollection) {
      collectionEditor(
        title: L10n.text(
          de: "Wissenssammlung umbenennen",
          en: "Rename Knowledge Collection",
          fr: "Renommer la collection"
        ),
        actionTitle: L10n.text(de: "Umbenennen", en: "Rename", fr: "Renommer")
      ) {
        let name = collectionName
        showingRenameCollection = false
        Task { await model.renameSelectedCollection(name: name) }
      }
    }
    .confirmationDialog(
      L10n.text(
        de: "Wissenssammlung wirklich löschen?",
        en: "Delete knowledge collection?",
        fr: "Supprimer la collection ?"
      ),
      isPresented: Binding(
        get: { collectionPendingDeletion != nil },
        set: { if !$0 { collectionPendingDeletion = nil } }
      ),
      titleVisibility: .visible
    ) {
      if let collectionPendingDeletion {
        Button(role: .destructive) {
          self.collectionPendingDeletion = nil
          Task { await model.deleteSelectedCollection() }
        } label: {
          Text(
            L10n.text(
              de: "„\(collectionPendingDeletion.name)“ und alle Dokumente löschen",
              en: "Delete “\(collectionPendingDeletion.name)” and all documents",
              fr: "Supprimer « \(collectionPendingDeletion.name) » et tous ses documents"
            )
          )
        }
      }
    }
    .confirmationDialog(
      L10n.text(
        de: "Wissensdokument wirklich löschen?",
        en: "Delete knowledge document?",
        fr: "Supprimer le document ?"
      ),
      isPresented: Binding(
        get: { documentPendingDeletion != nil },
        set: { if !$0 { documentPendingDeletion = nil } }
      ),
      titleVisibility: .visible
    ) {
      if let documentPendingDeletion {
        Button(role: .destructive) {
          self.documentPendingDeletion = nil
          Task { await model.deleteDocument(documentPendingDeletion) }
        } label: {
          Text(
            L10n.text(
              de: "„\(documentPendingDeletion.name)“ löschen",
              en: "Delete “\(documentPendingDeletion.name)”",
              fr: "Supprimer « \(documentPendingDeletion.name) »"
            )
          )
        }
      }
    }
    .alert(
      L10n.text(de: "Fehler", en: "Error", fr: "Erreur"),
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {
        model.errorMessage = nil
      }
    } message: {
      Text(model.errorMessage ?? "")
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "books.vertical.fill")
        .font(.title2)
      VStack(alignment: .leading, spacing: 3) {
        Text(
          L10n.text(
            de: "Wissensbibliothek",
            en: "Knowledge Library",
            fr: "Bibliothèque de connaissances"
          )
        )
        .font(.title2.bold())
        Text(
          L10n.text(
            de: "Dauerhaftes, lokales Projektwissen mit nachvollziehbaren Quellen.",
            en: "Persistent local project knowledge with traceable sources.",
            fr: "Connaissances locales persistantes avec sources traçables."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer()

      if model.isWorking {
        ProgressView()
          .controlSize(.small)
      }

      Button {
        Task { await model.refresh() }
      } label: {
        Label(
          L10n.text(de: "Aktualisieren", en: "Refresh", fr: "Actualiser"),
          systemImage: "arrow.clockwise"
        )
      }

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
    .padding(18)
  }

  private var collectionsPane: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(
          L10n.text(
            de: "Sammlungen",
            en: "Collections",
            fr: "Collections"
          )
        )
        .font(.headline)
        Spacer()
        Button {
          collectionName = ""
          showingCreateCollection = true
        } label: {
          Image(systemName: "plus")
        }
        .help(L10n.text(de: "Sammlung erstellen", en: "Create collection", fr: "Créer une collection"))
      }

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
          ForEach(model.snapshot.collections) { collection in
            Button {
              model.selectCollection(collection.id)
            } label: {
              HStack(spacing: 8) {
                Image(systemName: collection.isEnabled ? "books.vertical.fill" : "books.vertical")
                VStack(alignment: .leading, spacing: 2) {
                  Text(collection.name)
                    .lineLimit(1)
                  Text("\(model.snapshot.documents.filter { $0.collectionID == collection.id }.count) Dokumente")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
              }
              .padding(8)
              .background(
                model.selectedCollectionID == collection.id
                  ? Color.accentColor.opacity(0.14)
                  : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
              )
            }
            .buttonStyle(.plain)
          }
        }
      }

      Divider()

      HStack {
        Button {
          guard let collection = model.selectedCollection else { return }
          collectionName = collection.name
          showingRenameCollection = true
        } label: {
          Image(systemName: "pencil")
        }
        .disabled(model.selectedCollection == nil)

        Button {
          Task { await model.toggleSelectedCollection() }
        } label: {
          Image(systemName: model.selectedCollection?.isEnabled == false ? "play.circle" : "pause.circle")
        }
        .disabled(model.selectedCollection == nil)

        Spacer()

        Button(role: .destructive) {
          collectionPendingDeletion = model.selectedCollection
        } label: {
          Image(systemName: "trash")
        }
        .disabled(model.selectedCollection == nil)
      }
    }
    .padding(14)
  }

  private var documentsPane: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(model.selectedCollection?.name ?? L10n.text(de: "Dokumente", en: "Documents", fr: "Documents"))
          .font(.headline)
          .lineLimit(1)
        Spacer()
        Button {
          Task { await model.importFiles() }
        } label: {
          Label(
            L10n.text(de: "Importieren", en: "Import", fr: "Importer"),
            systemImage: "square.and.arrow.down"
          )
        }
        .disabled(model.selectedCollection == nil || model.isWorking)
      }

      HStack {
        TextField(
          L10n.text(
            de: "Diese Sammlung durchsuchen",
            en: "Search this collection",
            fr: "Rechercher dans cette collection"
          ),
          text: $model.searchQuery
        )
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          Task { await model.search() }
        }

        Button {
          Task { await model.search() }
        } label: {
          Image(systemName: "magnifyingglass")
        }

        if !model.searchQuery.isEmpty {
          Button {
            model.searchQuery = ""
            model.searchResults = []
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.plain)
        }
      }

      if let statusMessage = model.statusMessage {
        Text(statusMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }

      Divider()

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          if !model.searchResults.isEmpty {
            ForEach(model.searchResults) { result in
              searchResultRow(result)
            }
          } else if model.documentsForSelectedCollection.isEmpty {
            ContentUnavailableView(
              L10n.text(
                de: "Noch keine Wissensdokumente",
                en: "No Knowledge Documents Yet",
                fr: "Aucun document de connaissances"
              ),
              systemImage: "doc.badge.plus",
              description: Text(
                L10n.text(
                  de: "Importiere Dokumente in die ausgewählte Sammlung.",
                  en: "Import documents into the selected collection.",
                  fr: "Importez des documents dans la collection sélectionnée."
                )
              )
            )
          } else {
            ForEach(model.documentsForSelectedCollection) { document in
              documentRow(document)
            }
          }
        }
      }
    }
    .padding(14)
  }

  @ViewBuilder
  private var detailPane: some View {
    if let record = model.selectedRecord {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .top) {
            Image(systemName: icon(for: record.summary.documentKind))
              .font(.system(size: 32))
            VStack(alignment: .leading, spacing: 4) {
              Text(record.summary.name)
                .font(.title3.bold())
                .textSelection(.enabled)
              Text("\(record.summary.documentKind.displayName) · \(record.summary.sizeDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
          }

          Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
            GridRow {
              Text(L10n.text(de: "Status", en: "Status", fr: "État"))
                .foregroundStyle(.secondary)
              Text(record.summary.isEnabled
                ? L10n.text(de: "Aktiv", en: "Enabled", fr: "Actif")
                : L10n.text(de: "Deaktiviert", en: "Disabled", fr: "Désactivé"))
            }
            GridRow {
              Text(L10n.text(de: "Extraktion", en: "Extraction", fr: "Extraction"))
                .foregroundStyle(.secondary)
              Text(record.metadata.extractionMethod.rawValue)
            }
            GridRow {
              Text(L10n.text(de: "Abschnitte", en: "Sections", fr: "Sections"))
                .foregroundStyle(.secondary)
              Text("\(record.sections.count)")
            }
            GridRow {
              Text(L10n.text(de: "Zeichen", en: "Characters", fr: "Caractères"))
                .foregroundStyle(.secondary)
              Text("\(record.extractedText.count)")
            }
            if let pages = record.metadata.pageCount {
              GridRow {
                Text(L10n.text(de: "Seiten", en: "Pages", fr: "Pages"))
                  .foregroundStyle(.secondary)
                Text("\(pages)")
              }
            }
            if let sheets = record.metadata.sheetCount {
              GridRow {
                Text(L10n.text(de: "Blätter", en: "Sheets", fr: "Feuilles"))
                  .foregroundStyle(.secondary)
                Text("\(sheets)")
              }
            }
            if let slides = record.metadata.slideCount {
              GridRow {
                Text(L10n.text(de: "Folien", en: "Slides", fr: "Diapositives"))
                  .foregroundStyle(.secondary)
                Text("\(slides)")
              }
            }
            GridRow {
              Text("OCR")
                .foregroundStyle(.secondary)
              Text(record.metadata.ocrUsed ? "Ja" : "Nein")
            }
          }
          .font(.caption)

          HStack {
            Button {
              Task { await model.toggleDocument(record.summary) }
            } label: {
              Label(
                record.summary.isEnabled
                  ? L10n.text(de: "Deaktivieren", en: "Disable", fr: "Désactiver")
                  : L10n.text(de: "Aktivieren", en: "Enable", fr: "Activer"),
                systemImage: record.summary.isEnabled ? "pause.circle" : "play.circle"
              )
            }

            Spacer()

            Button(role: .destructive) {
              documentPendingDeletion = record.summary
            } label: {
              Label(
                L10n.text(de: "Löschen", en: "Delete", fr: "Supprimer"),
                systemImage: "trash"
              )
            }
          }

          Divider()

          Text(
            L10n.text(
              de: "Quellenabschnitte",
              en: "Source Sections",
              fr: "Sections sources"
            )
          )
          .font(.headline)

          ForEach(record.sections) { section in
            VStack(alignment: .leading, spacing: 6) {
              Text(section.locator)
                .font(.caption.bold())
                .textSelection(.enabled)
              if let title = section.title, !title.isEmpty {
                Text(title)
                  .font(.caption)
              }
              Text(String(section.text.prefix(1_200)))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(14)
            }
            .padding(10)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
          }
        }
        .padding(16)
      }
    } else {
      ContentUnavailableView(
        L10n.text(
          de: "Kein Dokument ausgewählt",
          en: "No Document Selected",
          fr: "Aucun document sélectionné"
        ),
        systemImage: "doc.text.magnifyingglass",
        description: Text(
          L10n.text(
            de: "Wähle ein Wissensdokument aus, um seine Quellen zu prüfen.",
            en: "Select a knowledge document to inspect its sources.",
            fr: "Sélectionnez un document pour inspecter ses sources."
          )
        )
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func documentRow(_ document: KnowledgeDocumentSummary) -> some View {
    Button {
      Task { await model.selectDocument(document.id) }
    } label: {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: icon(for: document.documentKind))
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 3) {
          Text(document.name)
            .lineLimit(2)
          Text("\(document.documentKind.displayName) · \(document.sizeDescription) · \(document.sectionCount) Quellen")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: document.isEnabled ? "checkmark.circle.fill" : "pause.circle")
          .foregroundStyle(document.isEnabled ? .secondary : .orange)
      }
      .padding(9)
      .background(
        model.selectedDocumentID == document.id
          ? Color.accentColor.opacity(0.12)
          : Color.clear,
        in: RoundedRectangle(cornerRadius: 8)
      )
    }
    .buttonStyle(.plain)
  }

  private func searchResultRow(_ result: KnowledgeSearchMatch) -> some View {
    Button {
      Task { await model.openSearchResult(result) }
    } label: {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(result.documentName)
            .font(.subheadline.bold())
          Spacer()
          Text("Score \(result.score)")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Text(result.locator)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(result.excerpt)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(5)
      }
      .padding(9)
      .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
  }

  private func collectionEditor(
    title: String,
    actionTitle: String,
    action: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(title)
        .font(.headline)
      TextField(
        L10n.text(de: "Name", en: "Name", fr: "Nom"),
        text: $collectionName
      )
      .textFieldStyle(.roundedBorder)

      HStack {
        Spacer()
        Button(L10n.text(de: "Abbrechen", en: "Cancel", fr: "Annuler")) {
          showingCreateCollection = false
          showingRenameCollection = false
        }
        Button(actionTitle, action: action)
          .keyboardShortcut(.defaultAction)
          .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 420)
  }

  private func icon(for kind: PromptDocumentKind) -> String {
    switch kind {
    case .plainText: "doc.plaintext"
    case .pdf: "doc.richtext"
    case .docx: "doc.text"
    case .xlsx: "tablecells"
    case .pptx: "rectangle.on.rectangle.angled"
    }
  }
}
