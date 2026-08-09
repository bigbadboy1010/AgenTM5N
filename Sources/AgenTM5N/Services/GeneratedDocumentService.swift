import Foundation

public enum GeneratedDocumentError: LocalizedError {
  case emptyTitle
  case emptyContent
  case contentTooLarge(Int)
  case invalidFileName
  case unsupportedFormat(String)
  case documentNotFound(String)
  case invalidManagedPath(String)

  public var errorDescription: String? {
    switch self {
    case .emptyTitle:
      return L10n.text(
        de: "Der Dokumenttitel darf nicht leer sein.",
        en: "The document title must not be empty.",
        fr: "Le titre du document ne doit pas être vide."
      )
    case .emptyContent:
      return L10n.text(
        de: "Der Dokumentinhalt darf nicht leer sein.",
        en: "The document content must not be empty.",
        fr: "Le contenu du document ne doit pas être vide."
      )
    case .contentTooLarge(let maximum):
      return L10n.text(
        de: "Der Dokumentinhalt überschreitet das Limit von \(maximum) Zeichen.",
        en: "The document content exceeds the \(maximum)-character limit.",
        fr: "Le contenu dépasse la limite de \(maximum) caractères."
      )
    case .invalidFileName:
      return L10n.text(
        de: "Der Dateiname ist ungültig.",
        en: "The file name is invalid.",
        fr: "Le nom de fichier n’est pas valide."
      )
    case .unsupportedFormat(let value):
      return L10n.text(
        de: "Nicht unterstütztes Dokumentformat: \(value).",
        en: "Unsupported document format: \(value).",
        fr: "Format de document non pris en charge : \(value)."
      )
    case .documentNotFound(let query):
      return L10n.text(
        de: "Kein generiertes Dokument passt zu „\(query)“.",
        en: "No generated document matches “\(query)”.",
        fr: "Aucun document généré ne correspond à « \(query) »."
      )
    case .invalidManagedPath(let path):
      return L10n.text(
        de: "Ungültiger interner Dokumentpfad: \(path)",
        en: "Invalid managed document path: \(path)",
        fr: "Chemin interne de document invalide : \(path)"
      )
    }
  }
}

public actor GeneratedDocumentService {
  public static let shared = GeneratedDocumentService()
  public static let maximumContentCharacters = 240_000

  public init() {}

  public func list() throws -> [GeneratedDocumentSummary] {
    try loadRegistry().documents.sorted { lhs, rhs in
      if lhs.createdAt == rhs.createdAt { return lhs.fileName < rhs.fileName }
      return lhs.createdAt > rhs.createdAt
    }
  }

  public func generate(
    request: GeneratedDocumentRequest
  ) throws -> GeneratedDocumentSummary {
    let normalized = try normalizedRequest(request)
    try AppPaths.ensureDirectories()

    let id = UUID()
    let managedName = "\(id.uuidString.lowercased()).\(normalized.format.fileExtension)"
    let destinationURL = AppPaths.generatedDocumentsDirectory.appendingPathComponent(managedName)
    try GeneratedDocumentWriters.write(request: normalized, to: destinationURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: destinationURL.path
    )

    let values = try destinationURL.resourceValues(forKeys: [.fileSizeKey])
    let summary = GeneratedDocumentSummary(
      id: id,
      title: normalized.title,
      fileName: displayFileName(for: normalized),
      format: normalized.format,
      byteCount: values.fileSize ?? 0,
      relativePath: managedName
    )

    var registry = try loadRegistry()
    registry.documents.append(summary)
    try saveRegistry(registry)
    return summary
  }

  public func delete(id: UUID) throws {
    var registry = try loadRegistry()
    guard let summary = registry.documents.first(where: { $0.id == id }) else {
      throw GeneratedDocumentError.documentNotFound(id.uuidString)
    }
    let sourceURL = try managedURL(for: summary)
    if FileManager.default.fileExists(atPath: sourceURL.path) {
      try FileManager.default.removeItem(at: sourceURL)
    }
    registry.documents.removeAll { $0.id == id }
    try saveRegistry(registry)
  }

  public func export(
    id: UUID,
    to destinationURL: URL
  ) throws {
    let registry = try loadRegistry()
    guard let summary = registry.documents.first(where: { $0.id == id }) else {
      throw GeneratedDocumentError.documentNotFound(id.uuidString)
    }
    let sourceURL = try managedURL(for: summary)
    let manager = FileManager.default
    let parent = destinationURL.deletingLastPathComponent()
    try manager.createDirectory(
      at: parent,
      withIntermediateDirectories: true,
      attributes: nil
    )
    if manager.fileExists(atPath: destinationURL.path) {
      try manager.removeItem(at: destinationURL)
    }
    try manager.copyItem(at: sourceURL, to: destinationURL)
  }

  public func resolve(_ query: String) throws -> GeneratedDocumentSummary {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let documents = try list()
    if let id = UUID(uuidString: trimmed),
      let match = documents.first(where: { $0.id == id })
    {
      return match
    }
    let exact = documents.filter {
      $0.fileName.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        || $0.title.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
    if let first = exact.first { return first }
    throw GeneratedDocumentError.documentNotFound(trimmed)
  }

  private func loadRegistry() throws -> GeneratedDocumentRegistry {
    try AppPaths.ensureDirectories()
    let url = AppPaths.generatedDocumentsRegistryFile
    guard FileManager.default.fileExists(atPath: url.path) else {
      return GeneratedDocumentRegistry()
    }
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(GeneratedDocumentRegistry.self, from: data)
  }

  private func saveRegistry(_ registry: GeneratedDocumentRegistry) throws {
    try AppPaths.ensureDirectories()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(registry)
    try data.write(to: AppPaths.generatedDocumentsRegistryFile, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: AppPaths.generatedDocumentsRegistryFile.path
    )
  }

  private func normalizedRequest(
    _ request: GeneratedDocumentRequest
  ) throws -> GeneratedDocumentRequest {
    let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { throw GeneratedDocumentError.emptyTitle }
    let content = request.content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else { throw GeneratedDocumentError.emptyContent }
    guard content.count <= Self.maximumContentCharacters else {
      throw GeneratedDocumentError.contentTooLarge(Self.maximumContentCharacters)
    }

    let fileName: String?
    if let provided = request.fileName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !provided.isEmpty
    {
      fileName = try sanitizedFileName(provided, format: request.format)
    } else {
      fileName = nil
    }
    return GeneratedDocumentRequest(
      format: request.format,
      title: String(title.prefix(200)),
      fileName: fileName,
      content: content
    )
  }

  private func displayFileName(for request: GeneratedDocumentRequest) -> String {
    if let fileName = request.fileName { return fileName }
    let base = request.title
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .replacingOccurrences(of: "[^A-Za-z0-9._ -]", with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: " ", with: "-")
    let safeBase = base.isEmpty ? "AgenTM5N-Dokument" : String(base.prefix(80))
    return "\(safeBase).\(request.format.fileExtension)"
  }

  private func sanitizedFileName(
    _ value: String,
    format: GeneratedDocumentFormat
  ) throws -> String {
    let last = URL(fileURLWithPath: value).lastPathComponent
    guard last == value,
      !last.contains("/"),
      !last.contains("\\"),
      last != ".",
      last != ".."
    else {
      throw GeneratedDocumentError.invalidFileName
    }

    let stem = URL(fileURLWithPath: last).deletingPathExtension().lastPathComponent
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !stem.isEmpty else { throw GeneratedDocumentError.invalidFileName }
    return "\(String(stem.prefix(120))).\(format.fileExtension)"
  }

  private func managedURL(for summary: GeneratedDocumentSummary) throws -> URL {
    let relative = summary.relativePath
    guard !relative.contains("/"),
      !relative.contains("\\"),
      !relative.contains(".."),
      !relative.hasPrefix(".")
    else {
      throw GeneratedDocumentError.invalidManagedPath(relative)
    }
    let root = AppPaths.generatedDocumentsDirectory.standardizedFileURL
    let url = root.appendingPathComponent(relative).standardizedFileURL
    guard url.deletingLastPathComponent() == root else {
      throw GeneratedDocumentError.invalidManagedPath(relative)
    }
    return url
  }
}
