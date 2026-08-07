import Foundation

public enum KnowledgeLibraryError: LocalizedError {
  case collectionNotFound(String)
  case documentNotFound(String)
  case ambiguousDocument(String, [String])
  case emptyName
  case duplicateCollection(String)
  case unsupportedFile(String)
  case unreadableFile(String)
  case fileTooLarge(String, Int)
  case emptyQuery
  case invalidManagedPath(String)

  public var errorDescription: String? {
    switch self {
    case .collectionNotFound(let query):
      return L10n.text(
        de: "Keine Wissenssammlung passt zu „\(query)“.",
        en: "No knowledge collection matches “\(query)”.",
        fr: "Aucune collection de connaissances ne correspond à « \(query) »."
      )
    case .documentNotFound(let query):
      return L10n.text(
        de: "Kein Wissensdokument passt zu „\(query)“.",
        en: "No knowledge document matches “\(query)”.",
        fr: "Aucun document de connaissances ne correspond à « \(query) »."
      )
    case .ambiguousDocument(let query, let matches):
      return L10n.text(
        de: "Das Wissensdokument „\(query)“ ist nicht eindeutig: \(matches.joined(separator: ", ")). Verwende die Dokument-ID.",
        en: "Knowledge document “\(query)” is ambiguous: \(matches.joined(separator: ", ")). Use the document ID.",
        fr: "Le document « \(query) » est ambigu : \(matches.joined(separator: ", ")). Utilisez son identifiant."
      )
    case .emptyName:
      return L10n.text(
        de: "Der Name darf nicht leer sein.",
        en: "The name must not be empty.",
        fr: "Le nom ne doit pas être vide."
      )
    case .duplicateCollection(let name):
      return L10n.text(
        de: "Die Wissenssammlung „\(name)“ existiert bereits.",
        en: "Knowledge collection “\(name)” already exists.",
        fr: "La collection « \(name) » existe déjà."
      )
    case .unsupportedFile(let name):
      return L10n.text(
        de: "Die Datei \(name) wird von der Wissensbibliothek nicht unterstützt.",
        en: "File \(name) is not supported by the knowledge library.",
        fr: "Le fichier \(name) n’est pas pris en charge par la bibliothèque de connaissances."
      )
    case .unreadableFile(let name):
      return L10n.text(
        de: "Die Datei \(name) konnte nicht gelesen werden.",
        en: "File \(name) could not be read.",
        fr: "Le fichier \(name) n’a pas pu être lu."
      )
    case .fileTooLarge(let name, let limit):
      return L10n.text(
        de: "Die Datei \(name) überschreitet das Wissensbibliothek-Limit von \(limit) Bytes.",
        en: "File \(name) exceeds the knowledge-library limit of \(limit) bytes.",
        fr: "Le fichier \(name) dépasse la limite de \(limit) octets de la bibliothèque."
      )
    case .emptyQuery:
      return L10n.text(
        de: "Die Suchabfrage darf nicht leer sein.",
        en: "The search query must not be empty.",
        fr: "La requête de recherche ne doit pas être vide."
      )
    case .invalidManagedPath(let path):
      return L10n.text(
        de: "Ungültiger interner Wissensbibliothek-Pfad: \(path)",
        en: "Invalid managed knowledge-library path: \(path)",
        fr: "Chemin interne de bibliothèque invalide : \(path)"
      )
    }
  }
}

public actor KnowledgeLibraryService {
  public static let shared = KnowledgeLibraryService()

  public static let maximumSourceBytes = 25 * 1024 * 1024
  public static let maximumExtractedCharacters = 240_000
  public static let maximumSearchResults = 20
  public static let maximumReadCharacters = 12_000

  private static let textExtensions: Set<String> = [
    "txt", "md", "markdown", "swift", "m", "mm", "h", "c", "cc", "cpp",
    "py", "js", "ts", "tsx", "jsx", "java", "kt", "kts", "go", "rs",
    "sh", "bash", "zsh", "fish", "ps1", "sql", "html", "htm", "css",
    "scss", "json", "jsonl", "yaml", "yml", "xml", "plist", "toml",
    "ini", "conf", "config", "env", "properties", "csv", "tsv", "log",
    "dockerfile", "gitignore"
  ]

  public init() {}

  public func snapshot() throws -> KnowledgeLibrarySnapshot {
    let registry = try loadRegistry()
    return KnowledgeLibrarySnapshot(
      collections: registry.collections.sorted(by: collectionSort),
      documents: registry.documents.sorted(by: documentSort)
    )
  }

  public func createCollection(name: String) throws -> KnowledgeCollection {
    let normalized = try normalizedName(name)
    var registry = try loadRegistry()
    guard !registry.collections.contains(where: {
      $0.name.caseInsensitiveCompare(normalized) == .orderedSame
    }) else {
      throw KnowledgeLibraryError.duplicateCollection(normalized)
    }

    let collection = KnowledgeCollection(name: normalized)
    registry.collections.append(collection)
    try saveRegistry(registry)
    return collection
  }

  public func renameCollection(id: UUID, name: String) throws -> KnowledgeCollection {
    let normalized = try normalizedName(name)
    var registry = try loadRegistry()
    guard let index = registry.collections.firstIndex(where: { $0.id == id }) else {
      throw KnowledgeLibraryError.collectionNotFound(id.uuidString)
    }
    guard !registry.collections.contains(where: {
      $0.id != id && $0.name.caseInsensitiveCompare(normalized) == .orderedSame
    }) else {
      throw KnowledgeLibraryError.duplicateCollection(normalized)
    }

    registry.collections[index].name = normalized
    registry.collections[index].updatedAt = Date()
    let collection = registry.collections[index]
    try saveRegistry(registry)
    return collection
  }

  public func setCollectionEnabled(id: UUID, enabled: Bool) throws {
    var registry = try loadRegistry()
    guard let index = registry.collections.firstIndex(where: { $0.id == id }) else {
      throw KnowledgeLibraryError.collectionNotFound(id.uuidString)
    }
    registry.collections[index].isEnabled = enabled
    registry.collections[index].updatedAt = Date()
    try saveRegistry(registry)
  }

  public func deleteCollection(id: UUID) throws {
    var registry = try loadRegistry()
    guard registry.collections.contains(where: { $0.id == id }) else {
      throw KnowledgeLibraryError.collectionNotFound(id.uuidString)
    }

    let documents = registry.documents.filter { $0.collectionID == id }
    for document in documents {
      try removeManagedDocument(document)
    }
    registry.documents.removeAll { $0.collectionID == id }
    registry.collections.removeAll { $0.id == id }
    try saveRegistry(registry)
  }

  public func setDocumentEnabled(id: UUID, enabled: Bool) throws {
    var registry = try loadRegistry()
    guard let index = registry.documents.firstIndex(where: { $0.id == id }) else {
      throw KnowledgeLibraryError.documentNotFound(id.uuidString)
    }

    registry.documents[index].isEnabled = enabled
    registry.documents[index].updatedAt = Date()
    var record = try loadDocument(registry.documents[index])
    record.summary = registry.documents[index]
    try saveDocument(record)
    try touchCollection(registry.documents[index].collectionID, registry: &registry)
    try saveRegistry(registry)
  }

  public func deleteDocument(id: UUID) throws {
    var registry = try loadRegistry()
    guard let summary = registry.documents.first(where: { $0.id == id }) else {
      throw KnowledgeLibraryError.documentNotFound(id.uuidString)
    }
    try removeManagedDocument(summary)
    registry.documents.removeAll { $0.id == id }
    try touchCollection(summary.collectionID, registry: &registry)
    try saveRegistry(registry)
  }

  public func importDocuments(
    urls: [URL],
    collectionQuery: String
  ) throws -> [KnowledgeImportResult] {
    var registry = try loadRegistry()
    let collection = try resolveCollection(collectionQuery, in: registry)
    var results: [KnowledgeImportResult] = []

    for url in urls {
      let accessed = url.startAccessingSecurityScopedResource()
      defer {
        if accessed { url.stopAccessingSecurityScopedResource() }
      }
      let result = try importOne(
        url: url,
        collection: collection,
        registry: &registry
      )
      results.append(result)
    }

    try touchCollection(collection.id, registry: &registry)
    try saveRegistry(registry)
    return results
  }

  public func document(id: UUID) throws -> KnowledgeDocumentRecord {
    let registry = try loadRegistry()
    guard let summary = registry.documents.first(where: { $0.id == id }) else {
      throw KnowledgeLibraryError.documentNotFound(id.uuidString)
    }
    return try loadDocument(summary)
  }

  public func search(
    query: String,
    collectionQuery: String? = nil,
    limit: Int = 12
  ) throws -> [KnowledgeSearchMatch] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else {
      throw KnowledgeLibraryError.emptyQuery
    }

    let registry = try loadRegistry()
    let selectedCollection: KnowledgeCollection?
    if let collectionQuery,
      !collectionQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      selectedCollection = try resolveCollection(collectionQuery, in: registry)
    } else {
      selectedCollection = nil
    }

    let enabledCollectionIDs = Set(
      registry.collections.filter(\.isEnabled).map(\.id)
    )
    let collectionNames = Dictionary(
      uniqueKeysWithValues: registry.collections.map { ($0.id, $0.name) }
    )
    let cappedLimit = max(1, min(limit, Self.maximumSearchResults))
    let tokens = searchTokens(normalizedQuery)
    var matches: [KnowledgeSearchMatch] = []

    for summary in registry.documents where summary.isEnabled {
      guard enabledCollectionIDs.contains(summary.collectionID) else { continue }
      if let selectedCollection, summary.collectionID != selectedCollection.id {
        continue
      }

      let record = try loadDocument(summary)
      let sections = record.sections.isEmpty
        ? [PromptAttachmentSection(
          locator: "Datei \(summary.name)",
          text: record.extractedText
        )]
        : record.sections

      for section in sections {
        let score = searchScore(
          query: normalizedQuery,
          tokens: tokens,
          documentName: summary.name,
          locator: section.locator,
          text: section.text
        )
        guard score > 0 else { continue }
        matches.append(
          KnowledgeSearchMatch(
            documentID: summary.id,
            collectionID: summary.collectionID,
            documentName: summary.name,
            collectionName: collectionNames[summary.collectionID] ?? "",
            locator: section.locator,
            score: score,
            excerpt: boundedExcerpt(
              text: section.text,
              query: normalizedQuery,
              tokens: tokens,
              maximumCharacters: 900
            )
          )
        )
      }
    }

    return matches
      .sorted {
        if $0.score != $1.score { return $0.score > $1.score }
        if $0.documentName != $1.documentName {
          return $0.documentName.localizedCaseInsensitiveCompare($1.documentName) == .orderedAscending
        }
        return $0.locator.localizedCaseInsensitiveCompare($1.locator) == .orderedAscending
      }
      .prefix(cappedLimit)
      .map { $0 }
  }

  public func readSource(
    documentQuery: String,
    collectionQuery: String? = nil,
    locatorQuery: String? = nil,
    maximumCharacters: Int = 6_000
  ) throws -> KnowledgeReadResult {
    let registry = try loadRegistry()
    let collection: KnowledgeCollection?
    if let collectionQuery,
      !collectionQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      collection = try resolveCollection(collectionQuery, in: registry)
    } else {
      collection = nil
    }

    let summary = try resolveDocument(
      documentQuery,
      collectionID: collection?.id,
      registry: registry
    )
    let record = try loadDocument(summary)
    let collectionName = registry.collections.first(where: {
      $0.id == summary.collectionID
    })?.name ?? ""
    let cappedMaximum = max(500, min(maximumCharacters, Self.maximumReadCharacters))

    let section: PromptAttachmentSection
    if let locatorQuery,
      !locatorQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      let normalized = locatorQuery.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let match = record.sections.first(where: {
        $0.locator.caseInsensitiveCompare(normalized) == .orderedSame
      }) ?? record.sections.first(where: {
        $0.locator.localizedCaseInsensitiveContains(normalized)
          || normalized.localizedCaseInsensitiveContains($0.locator)
      }) else {
        throw KnowledgeLibraryError.documentNotFound(
          "\(summary.name) / \(normalized)"
        )
      }
      section = match
    } else if let first = record.sections.first {
      section = first
    } else {
      section = PromptAttachmentSection(
        locator: "Datei \(summary.name)",
        text: record.extractedText
      )
    }

    let content = String(section.text.prefix(cappedMaximum))
    return KnowledgeReadResult(
      documentID: summary.id,
      collectionID: summary.collectionID,
      documentName: summary.name,
      collectionName: collectionName,
      locator: section.locator,
      content: content,
      truncated: section.text.count > content.count
    )
  }

  public func resolveCollectionSummary(_ query: String) throws -> KnowledgeCollection {
    try resolveCollection(query, in: loadRegistry())
  }

  private func importOne(
    url: URL,
    collection: KnowledgeCollection,
    registry: inout KnowledgeLibraryRegistry
  ) throws -> KnowledgeImportResult {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else {
      throw KnowledgeLibraryError.unreadableFile(url.lastPathComponent)
    }
    let byteCount = values.fileSize ?? 0
    guard byteCount <= Self.maximumSourceBytes else {
      throw KnowledgeLibraryError.fileTooLarge(
        url.lastPathComponent,
        Self.maximumSourceBytes
      )
    }

    let extensionName = normalizedExtension(url)
    guard Self.textExtensions.contains(extensionName)
      || DocumentIntelligenceService.supportedExtensions.contains(extensionName)
    else {
      throw KnowledgeLibraryError.unsupportedFile(url.lastPathComponent)
    }

    let sha256 = try DocumentExtractionCache.sha256(for: url)
    if let duplicate = registry.documents.first(where: {
      $0.collectionID == collection.id && $0.sourceSHA256 == sha256
    }) {
      return KnowledgeImportResult(status: .duplicate, document: duplicate)
    }

    let extraction = try extract(url: url, extensionName: extensionName, sha256: sha256)
    let existingIndex = registry.documents.firstIndex(where: {
      $0.collectionID == collection.id
        && $0.name.caseInsensitiveCompare(url.lastPathComponent) == .orderedSame
    })
    let id = existingIndex.map { registry.documents[$0].id } ?? UUID()
    let importedAt = existingIndex.map { registry.documents[$0].importedAt } ?? Date()
    let isEnabled = existingIndex.map { registry.documents[$0].isEnabled } ?? true

    let sourceURL = AppPaths.knowledgeSourceFile(
      id: id,
      extensionName: extensionName
    )
    let documentURL = AppPaths.knowledgeDocumentFile(id: id)
    try replaceManagedSource(from: url, to: sourceURL, documentID: id)

    let summary = KnowledgeDocumentSummary(
      id: id,
      collectionID: collection.id,
      name: url.lastPathComponent,
      mediaType: mediaType(extensionName),
      byteCount: byteCount,
      documentKind: extraction.metadata.documentKind,
      sectionCount: extraction.sections.count,
      isEnabled: isEnabled,
      importedAt: importedAt,
      updatedAt: Date(),
      sourceSHA256: sha256,
      sourceRelativePath: relativeManagedPath(sourceURL),
      documentRelativePath: relativeManagedPath(documentURL)
    )
    let record = KnowledgeDocumentRecord(
      summary: summary,
      extractedText: extraction.text,
      sections: extraction.sections,
      metadata: extraction.metadata
    )
    try saveDocument(record)

    if let existingIndex {
      let previous = registry.documents[existingIndex]
      registry.documents[existingIndex] = summary
      if previous.sourceRelativePath != summary.sourceRelativePath {
        try? FileManager.default.removeItem(
          at: try managedURL(relativePath: previous.sourceRelativePath)
        )
      }
      return KnowledgeImportResult(status: .updated, document: summary)
    }

    registry.documents.append(summary)
    return KnowledgeImportResult(status: .imported, document: summary)
  }

  private func extract(
    url: URL,
    extensionName: String,
    sha256: String
  ) throws -> DocumentExtractionResult {
    if DocumentIntelligenceService.supportedExtensions.contains(extensionName) {
      return try DocumentIntelligenceService.extract(url: url)
    }

    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    guard let originalText = String(data: data, encoding: .utf8) else {
      throw KnowledgeLibraryError.unreadableFile(url.lastPathComponent)
    }
    let text = String(originalText.prefix(Self.maximumExtractedCharacters))
    let sections = textSections(name: url.lastPathComponent, text: text)
    let metadata = PromptAttachmentMetadata(
      documentKind: .plainText,
      extractionMethod: .directText,
      sectionCount: sections.count,
      sourceSHA256: sha256
    )
    return DocumentExtractionResult(
      text: text,
      sections: sections,
      metadata: metadata
    )
  }

  private func textSections(name: String, text: String) -> [PromptAttachmentSection] {
    guard !text.isEmpty else { return [] }
    let maximum = 12_000
    var sections: [PromptAttachmentSection] = []
    var cursor = text.startIndex
    var number = 1

    while cursor < text.endIndex {
      let end = text.index(
        cursor,
        offsetBy: maximum,
        limitedBy: text.endIndex
      ) ?? text.endIndex
      let chunk = String(text[cursor..<end])
      sections.append(
        PromptAttachmentSection(
          locator: "Datei \(name), Abschnitt \(number)",
          title: "Abschnitt \(number)",
          text: chunk
        )
      )
      cursor = end
      number += 1
    }
    return sections
  }

  private func loadRegistry() throws -> KnowledgeLibraryRegistry {
    try AppPaths.ensureDirectories()
    let url = AppPaths.knowledgeRegistryFile
    guard FileManager.default.fileExists(atPath: url.path) else {
      let initial = KnowledgeLibraryRegistry(
        collections: [KnowledgeCollection(name: "Allgemein")]
      )
      try saveRegistry(initial)
      return initial
    }
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    return try decoder().decode(KnowledgeLibraryRegistry.self, from: data)
  }

  private func saveRegistry(_ registry: KnowledgeLibraryRegistry) throws {
    try AppPaths.ensureDirectories()
    let data = try encoder().encode(registry)
    try data.write(to: AppPaths.knowledgeRegistryFile, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: AppPaths.knowledgeRegistryFile.path
    )
  }

  private func loadDocument(
    _ summary: KnowledgeDocumentSummary
  ) throws -> KnowledgeDocumentRecord {
    let url = try managedURL(relativePath: summary.documentRelativePath)
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    return try decoder().decode(KnowledgeDocumentRecord.self, from: data)
  }

  private func saveDocument(_ record: KnowledgeDocumentRecord) throws {
    try AppPaths.ensureDirectories()
    let url = AppPaths.knowledgeDocumentFile(id: record.summary.id)
    let data = try encoder().encode(record)
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path
    )
  }

  private func replaceManagedSource(
    from source: URL,
    to destination: URL,
    documentID: UUID
  ) throws {
    try AppPaths.ensureDirectories()
    let manager = FileManager.default
    let existing = try manager.contentsOfDirectory(
      at: AppPaths.knowledgeSourcesDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    let prefix = documentID.uuidString.lowercased() + "."
    for candidate in existing where candidate.lastPathComponent.hasPrefix(prefix) {
      try manager.removeItem(at: candidate)
    }
    if manager.fileExists(atPath: destination.path) {
      try manager.removeItem(at: destination)
    }
    try manager.copyItem(at: source, to: destination)
    try manager.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: destination.path
    )
  }

  private func removeManagedDocument(_ summary: KnowledgeDocumentSummary) throws {
    let manager = FileManager.default
    for relativePath in [summary.sourceRelativePath, summary.documentRelativePath] {
      let url = try managedURL(relativePath: relativePath)
      if manager.fileExists(atPath: url.path) {
        try manager.removeItem(at: url)
      }
    }
  }

  private func resolveCollection(
    _ query: String,
    in registry: KnowledgeLibraryRegistry
  ) throws -> KnowledgeCollection {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if let id = UUID(uuidString: normalized),
      let match = registry.collections.first(where: { $0.id == id })
    {
      return match
    }
    if let match = registry.collections.first(where: {
      $0.name.caseInsensitiveCompare(normalized) == .orderedSame
    }) {
      return match
    }
    throw KnowledgeLibraryError.collectionNotFound(query)
  }

  private func resolveDocument(
    _ query: String,
    collectionID: UUID?,
    registry: KnowledgeLibraryRegistry
  ) throws -> KnowledgeDocumentSummary {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidates = registry.documents.filter {
      collectionID == nil || $0.collectionID == collectionID
    }
    if let id = UUID(uuidString: normalized),
      let match = candidates.first(where: { $0.id == id })
    {
      return match
    }
    let matches = candidates.filter {
      $0.name.caseInsensitiveCompare(normalized) == .orderedSame
    }
    guard !matches.isEmpty else {
      throw KnowledgeLibraryError.documentNotFound(query)
    }
    guard matches.count == 1, let match = matches.first else {
      throw KnowledgeLibraryError.ambiguousDocument(
        query,
        matches.map { "\($0.name) [\($0.id.uuidString)]" }
      )
    }
    return match
  }

  private func normalizedName(_ value: String) throws -> String {
    let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { throw KnowledgeLibraryError.emptyName }
    return String(name.prefix(120))
  }

  private func normalizedExtension(_ url: URL) -> String {
    let raw = url.pathExtension.lowercased()
    if !raw.isEmpty { return raw }
    return url.lastPathComponent.lowercased() == "dockerfile"
      ? "dockerfile"
      : url.lastPathComponent.lowercased().replacingOccurrences(of: ".", with: "")
  }

  private func mediaType(_ extensionName: String) -> String {
    switch extensionName {
    case "pdf": "application/pdf"
    case "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    case "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    case "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    case "json", "jsonl": "application/json"
    case "xml": "application/xml"
    case "csv": "text/csv"
    case "html", "htm": "text/html"
    case "md", "markdown": "text/markdown"
    default: "text/plain"
    }
  }

  private func relativeManagedPath(_ url: URL) -> String {
    let root = AppPaths.knowledgeLibraryDirectory.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    if path.hasPrefix(root + "/") {
      return String(path.dropFirst(root.count + 1))
    }
    return url.lastPathComponent
  }

  private func managedURL(relativePath: String) throws -> URL {
    guard !relativePath.hasPrefix("/"),
      !relativePath.split(separator: "/").contains("..")
    else {
      throw KnowledgeLibraryError.invalidManagedPath(relativePath)
    }
    let root = AppPaths.knowledgeLibraryDirectory.standardizedFileURL
    let url = root.appendingPathComponent(relativePath).standardizedFileURL
    guard url.path.hasPrefix(root.path + "/") else {
      throw KnowledgeLibraryError.invalidManagedPath(relativePath)
    }
    return url
  }

  private func touchCollection(
    _ id: UUID,
    registry: inout KnowledgeLibraryRegistry
  ) throws {
    guard let index = registry.collections.firstIndex(where: { $0.id == id }) else {
      throw KnowledgeLibraryError.collectionNotFound(id.uuidString)
    }
    registry.collections[index].updatedAt = Date()
  }

  private func collectionSort(_ lhs: KnowledgeCollection, _ rhs: KnowledgeCollection) -> Bool {
    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
  }

  private func documentSort(
    _ lhs: KnowledgeDocumentSummary,
    _ rhs: KnowledgeDocumentSummary
  ) -> Bool {
    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
  }

  private func searchTokens(_ query: String) -> [String] {
    query
      .lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { $0.count >= 2 }
      .uniqued()
  }

  private func searchScore(
    query: String,
    tokens: [String],
    documentName: String,
    locator: String,
    text: String
  ) -> Int {
    let loweredText = text.lowercased()
    let loweredName = documentName.lowercased()
    let loweredLocator = locator.lowercased()
    let loweredQuery = query.lowercased()
    var score = 0

    if loweredText.contains(loweredQuery) { score += 25 }
    if loweredName.contains(loweredQuery) { score += 16 }
    if loweredLocator.contains(loweredQuery) { score += 10 }

    for token in tokens {
      score += occurrenceCount(token, in: loweredText) * 3
      if loweredName.contains(token) { score += 7 }
      if loweredLocator.contains(token) { score += 4 }
    }
    return score
  }

  private func occurrenceCount(_ needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var searchRange = haystack.startIndex..<haystack.endIndex
    while let range = haystack.range(of: needle, range: searchRange) {
      count += 1
      if count >= 20 { break }
      searchRange = range.upperBound..<haystack.endIndex
    }
    return count
  }

  private func boundedExcerpt(
    text: String,
    query: String,
    tokens: [String],
    maximumCharacters: Int
  ) -> String {
    guard text.count > maximumCharacters else {
      return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let lowered = text.lowercased()
    let candidates = [query.lowercased()] + tokens
    var matchIndex: String.Index?
    for candidate in candidates where !candidate.isEmpty {
      if let range = lowered.range(of: candidate) {
        matchIndex = range.lowerBound
        break
      }
    }
    guard let matchIndex else {
      return String(text.prefix(maximumCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let position = lowered.distance(from: lowered.startIndex, to: matchIndex)
    let startOffset = max(0, position - maximumCharacters / 3)
    let start = text.index(text.startIndex, offsetBy: startOffset)
    let end = text.index(
      start,
      offsetBy: maximumCharacters,
      limitedBy: text.endIndex
    ) ?? text.endIndex
    return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  private func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

private extension Array where Element == String {
  func uniqued() -> [String] {
    var seen = Set<String>()
    return filter { seen.insert($0).inserted }
  }
}
