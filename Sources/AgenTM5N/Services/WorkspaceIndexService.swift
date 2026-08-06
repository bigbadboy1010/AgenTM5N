import Foundation

public enum WorkspaceIndexError: LocalizedError {
  case invalidWorkspace(String)
  case enumerationFailed(String)
  case noIndexableContent
  case indexNotFound(String)
  case indexWorkspaceMismatch
  case modelRequired(String)
  case modelMismatch(indexed: String, requested: String)
  case embeddingCountMismatch(expected: Int, actual: Int)
  case embeddingDimensionMismatch(expected: Int, actual: Int)
  case emptyQuery

  public var errorDescription: String? {
    switch self {
    case .invalidWorkspace(let path):
      return L10n.text(
        de: "Der Workspace ist kein erreichbares Verzeichnis: \(path)",
        en: "The workspace is not an accessible directory: \(path)",
        fr: "L’espace de travail n’est pas un dossier accessible : \(path)"
      )
    case .enumerationFailed(let path):
      return L10n.text(
        de: "Der Workspace konnte nicht vollständig gelesen werden: \(path)",
        en: "The workspace could not be enumerated completely: \(path)",
        fr: "L’espace de travail n’a pas pu être parcouru complètement : \(path)"
      )
    case .noIndexableContent:
      return L10n.text(
        de: "Im Workspace wurden keine unterstützten UTF-8-Dateien für den Index gefunden.",
        en: "No supported UTF-8 files were found for the workspace index.",
        fr: "Aucun fichier UTF-8 pris en charge n’a été trouvé pour l’index."
      )
    case .indexNotFound(let path):
      return L10n.text(
        de: "Für diesen Workspace existiert noch kein Index: \(path)",
        en: "No index exists for this workspace yet: \(path)",
        fr: "Aucun index n’existe encore pour cet espace de travail : \(path)"
      )
    case .indexWorkspaceMismatch:
      return L10n.text(
        de: "Die Indexdatei gehört nicht zum aktuell ausgewählten Workspace.",
        en: "The index file does not belong to the currently selected workspace.",
        fr: "Le fichier d’index n’appartient pas à l’espace de travail actuellement sélectionné."
      )
    case .modelRequired(let name):
      return L10n.text(
        de: "Der Index wurde mit dem Core-ML-Modell „\(name)“ erstellt, aber dieses Modell ist nicht mehr registriert.",
        en: "The index was built with Core ML model “\(name)”, but that model is no longer registered.",
        fr: "L’index a été créé avec le modèle Core ML « \(name) », mais ce modèle n’est plus enregistré."
      )
    case .modelMismatch(let indexed, let requested):
      return L10n.text(
        de: "Der Workspace wurde mit „\(indexed)“ indexiert, die Suche verwendet aber „\(requested)“. Erstelle den Index mit dem gewünschten Modell neu.",
        en: "The workspace was indexed with “\(indexed)”, but search requested “\(requested)”. Rebuild the index with the desired model.",
        fr: "L’espace de travail a été indexé avec « \(indexed) », mais la recherche utilise « \(requested) ». Reconstruisez l’index avec le modèle souhaité."
      )
    case .embeddingCountMismatch(let expected, let actual):
      return L10n.text(
        de: "Das Embedding-Modell lieferte eine unerwartete Anzahl Vektoren. Erwartet: \(expected), erhalten: \(actual).",
        en: "The embedding model returned an unexpected number of vectors. Expected: \(expected), received: \(actual).",
        fr: "Le modèle d’embedding a renvoyé un nombre inattendu de vecteurs. Attendu : \(expected), reçu : \(actual)."
      )
    case .embeddingDimensionMismatch(let expected, let actual):
      return L10n.text(
        de: "Die Suchanfrage hat eine andere Embedding-Dimension als der Index. Erwartet: \(expected), erhalten: \(actual).",
        en: "The search query has a different embedding dimension than the index. Expected: \(expected), received: \(actual).",
        fr: "La requête de recherche a une dimension d’embedding différente de celle de l’index. Attendu : \(expected), reçu : \(actual)."
      )
    case .emptyQuery:
      return L10n.text(
        de: "Die Suchanfrage darf nicht leer sein.",
        en: "The search query must not be empty.",
        fr: "La requête de recherche ne doit pas être vide."
      )
    }
  }
}

public actor WorkspaceIndexService {
  public static let maximumFileBytes = 1 * 1024 * 1024
  public static let maximumIndexedCharacters = 2_000_000
  public static let maximumChunks = 1_200
  public static let targetChunkCharacters = 1_600
  public static let overlapLines = 3
  public static let maximumResults = 20

  public typealias ProgressHandler = @Sendable (WorkspaceIndexBuildProgress) async -> Void

  private struct PendingChunk: Sendable {
    let relativePath: String
    let startLine: Int
    let endLine: Int
    let text: String
  }

  private struct LegacyWorkspaceIndexStatus: Codable {
    let workspacePath: String
    let modelID: UUID
    let modelName: String
    let createdAt: Date
    let fileCount: Int
    let chunkCount: Int
    let embeddingDimension: Int
    let indexedCharacterCount: Int
  }

  private struct LegacyWorkspaceIndexChunk: Codable {
    let id: UUID
    let relativePath: String
    let startLine: Int
    let endLine: Int
    let text: String
    let embedding: [Float]
  }

  private struct LegacyWorkspaceIndexDocument: Codable {
    let version: Int
    let status: LegacyWorkspaceIndexStatus
    let chunks: [LegacyWorkspaceIndexChunk]
  }

  private static let excludedDirectoryNames: Set<String> = [
    ".git", ".build", ".swiftpm", ".idea", ".vscode", ".ssh",
    "deriveddata", "dist", "build", "node_modules", "pods", "vendor",
    "coverage", "secrets", "credentials"
  ]

  private static let supportedExtensions: Set<String> = [
    "txt", "md", "markdown", "swift", "m", "mm", "h", "c", "cc", "cpp",
    "py", "js", "ts", "tsx", "jsx", "java", "kt", "kts", "go", "rs",
    "sh", "bash", "zsh", "fish", "ps1", "sql", "html", "htm", "css",
    "scss", "json", "jsonl", "yaml", "yml", "xml", "plist", "toml",
    "ini", "conf", "config", "properties", "csv", "tsv", "log", "rego"
  ]

  private static let supportedFileNames: Set<String> = [
    "dockerfile", "makefile", "gemfile", "rakefile", "podfile",
    "package.swift", "caddyfile", "license", "readme"
  ]

  private var cache: [String: WorkspaceIndexDocument] = [:]

  public init() {}

  public func build(
    workspacePath: String,
    model: CoreMLRegisteredModel?,
    progress: ProgressHandler? = nil
  ) async throws -> WorkspaceIndexStatus {
    await progress?(
      WorkspaceIndexBuildProgress(
        phase: .preparing,
        detail: L10n.text(
          de: "Workspace wird vorbereitet.",
          en: "Preparing workspace.",
          fr: "Préparation de l’espace de travail."
        )
      )
    )

    let workspaceURL = try Self.validatedWorkspaceURL(workspacePath)
    await progress?(
      WorkspaceIndexBuildProgress(
        phase: .scanning,
        detail: workspaceURL.path
      )
    )

    let pending = try Self.collectChunks(in: workspaceURL)
    guard !pending.chunks.isEmpty else {
      throw WorkspaceIndexError.noIndexableContent
    }

    let lexicalChunks = pending.chunks.map { chunk in
      WorkspaceIndexChunk(
        relativePath: chunk.relativePath,
        startLine: chunk.startLine,
        endLine: chunk.endLine,
        text: chunk.text
      )
    }
    var lexicalStatus = WorkspaceIndexStatus(
      workspacePath: workspaceURL.path,
      mode: .lexical,
      fileCount: pending.fileCount,
      chunkCount: lexicalChunks.count,
      indexedCharacterCount: pending.indexedCharacterCount
    )
    var document = WorkspaceIndexDocument(
      status: lexicalStatus,
      chunks: lexicalChunks
    )

    await progress?(
      WorkspaceIndexBuildProgress(
        phase: .savingLexicalIndex,
        completed: lexicalChunks.count,
        total: lexicalChunks.count,
        detail: L10n.text(
          de: "Der lokale Textindex wird sofort gespeichert.",
          en: "Saving the local text index immediately.",
          fr: "Enregistrement immédiat de l’index texte local."
        )
      )
    )
    try Self.save(document, workspacePath: workspaceURL.path)
    cache[workspaceURL.path] = document

    guard let model else {
      await progress?(
        WorkspaceIndexBuildProgress(
          phase: .completed,
          completed: lexicalChunks.count,
          total: lexicalChunks.count,
          detail: L10n.text(
            de: "Lexikalischer Index wurde erstellt.",
            en: "Lexical index created.",
            fr: "Index lexical créé."
          )
        )
      )
      return lexicalStatus
    }

    do {
      await progress?(
        WorkspaceIndexBuildProgress(
          phase: .embedding,
          completed: 0,
          total: pending.chunks.count,
          detail: model.name
        )
      )
      let embeddings = try await CoreMLEmbeddingRunner.embed(
        texts: pending.chunks.map(\.text),
        compiledURL: model.compiledURL,
        progress: { completed, total in
          await progress?(
            WorkspaceIndexBuildProgress(
              phase: .embedding,
              completed: completed,
              total: total,
              detail: model.name
            )
          )
        }
      )
      guard embeddings.count == pending.chunks.count else {
        throw WorkspaceIndexError.embeddingCountMismatch(
          expected: pending.chunks.count,
          actual: embeddings.count
        )
      }
      guard let dimension = embeddings.first?.count, dimension > 0 else {
        throw CoreMLEmbeddingError.emptyEmbedding
      }

      let semanticChunks = zip(pending.chunks, embeddings).map { chunk, embedding in
        WorkspaceIndexChunk(
          relativePath: chunk.relativePath,
          startLine: chunk.startLine,
          endLine: chunk.endLine,
          text: chunk.text,
          embedding: embedding
        )
      }
      let semanticStatus = WorkspaceIndexStatus(
        workspacePath: workspaceURL.path,
        mode: .coreMLEmbedding,
        modelID: model.id,
        modelName: model.name,
        fileCount: pending.fileCount,
        chunkCount: semanticChunks.count,
        embeddingDimension: dimension,
        indexedCharacterCount: pending.indexedCharacterCount
      )
      document = WorkspaceIndexDocument(
        status: semanticStatus,
        chunks: semanticChunks
      )
      await progress?(
        WorkspaceIndexBuildProgress(
          phase: .savingSemanticIndex,
          completed: semanticChunks.count,
          total: semanticChunks.count,
          detail: model.name
        )
      )
      try Self.save(document, workspacePath: workspaceURL.path)
      cache[workspaceURL.path] = document
      await progress?(
        WorkspaceIndexBuildProgress(
          phase: .completed,
          completed: semanticChunks.count,
          total: semanticChunks.count,
          detail: L10n.text(
            de: "Core-ML-Index wurde erstellt.",
            en: "Core ML index created.",
            fr: "Index Core ML créé."
          )
        )
      )
      return semanticStatus
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      let warning = L10n.text(
        de: "Der Textindex wurde erstellt. Core ML konnte nicht ergänzt werden: \(error.localizedDescription)",
        en: "The text index was created. Core ML could not be added: \(error.localizedDescription)",
        fr: "L’index texte a été créé. Core ML n’a pas pu être ajouté : \(error.localizedDescription)"
      )
      lexicalStatus = WorkspaceIndexStatus(
        workspacePath: workspaceURL.path,
        mode: .lexical,
        warning: warning,
        fileCount: pending.fileCount,
        chunkCount: lexicalChunks.count,
        indexedCharacterCount: pending.indexedCharacterCount
      )
      document = WorkspaceIndexDocument(
        status: lexicalStatus,
        chunks: lexicalChunks
      )
      try Self.save(document, workspacePath: workspaceURL.path)
      cache[workspaceURL.path] = document
      await progress?(
        WorkspaceIndexBuildProgress(
          phase: .completed,
          completed: lexicalChunks.count,
          total: lexicalChunks.count,
          detail: warning
        )
      )
      return lexicalStatus
    }
  }

  public func status(workspacePath: String) throws -> WorkspaceIndexStatus? {
    let workspaceURL = try Self.validatedWorkspaceURL(workspacePath)
    return try loadIfPresent(workspacePath: workspaceURL.path)?.status
  }

  public func search(
    query: String,
    workspacePath: String,
    model: CoreMLRegisteredModel?,
    limit: Int = 8
  ) async throws -> [WorkspaceSemanticMatch] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else {
      throw WorkspaceIndexError.emptyQuery
    }

    let workspaceURL = try Self.validatedWorkspaceURL(workspacePath)
    guard let document = try loadIfPresent(workspacePath: workspaceURL.path) else {
      throw WorkspaceIndexError.indexNotFound(workspaceURL.path)
    }
    guard document.status.workspacePath == workspaceURL.path else {
      throw WorkspaceIndexError.indexWorkspaceMismatch
    }

    let boundedLimit = max(1, min(limit, Self.maximumResults))
    switch document.status.mode {
    case .lexical:
      return Self.lexicalSearch(
        query: normalizedQuery,
        chunks: document.chunks,
        limit: boundedLimit
      )

    case .coreMLEmbedding:
      guard let expectedModelID = document.status.modelID,
        let expectedModelName = document.status.modelName
      else {
        return Self.lexicalSearch(
          query: normalizedQuery,
          chunks: document.chunks,
          limit: boundedLimit
        )
      }
      guard let model else {
        throw WorkspaceIndexError.modelRequired(expectedModelName)
      }
      guard model.id == expectedModelID else {
        throw WorkspaceIndexError.modelMismatch(
          indexed: expectedModelName,
          requested: model.name
        )
      }

      let queryEmbeddings = try await CoreMLEmbeddingRunner.embed(
        texts: [normalizedQuery],
        compiledURL: model.compiledURL
      )
      guard let queryEmbedding = queryEmbeddings.first else {
        throw CoreMLEmbeddingError.emptyEmbedding
      }
      guard let expectedDimension = document.status.embeddingDimension,
        queryEmbedding.count == expectedDimension
      else {
        throw WorkspaceIndexError.embeddingDimensionMismatch(
          expected: document.status.embeddingDimension ?? 0,
          actual: queryEmbedding.count
        )
      }

      return document.chunks.compactMap { chunk in
        guard let embedding = chunk.embedding else { return nil }
        return WorkspaceSemanticMatch(
          id: chunk.id,
          relativePath: chunk.relativePath,
          startLine: chunk.startLine,
          endLine: chunk.endLine,
          score: Self.cosineSimilarity(queryEmbedding, embedding),
          excerpt: Self.excerpt(chunk.text)
        )
      }
      .sorted { lhs, rhs in
        if lhs.score == rhs.score {
          if lhs.relativePath == rhs.relativePath {
            return lhs.startLine < rhs.startLine
          }
          return lhs.relativePath < rhs.relativePath
        }
        return lhs.score > rhs.score
      }
      .prefix(boundedLimit)
      .map { $0 }
    }
  }

  public func clear(workspacePath: String) throws {
    let workspaceURL = try Self.validatedWorkspaceURL(workspacePath)
    let indexURL = AppPaths.workspaceIndexFile(for: workspaceURL.path)
    if FileManager.default.fileExists(atPath: indexURL.path) {
      try FileManager.default.removeItem(at: indexURL)
    }
    cache.removeValue(forKey: workspaceURL.path)
  }

  private func loadIfPresent(workspacePath: String) throws -> WorkspaceIndexDocument? {
    if let cached = cache[workspacePath] {
      return cached
    }
    let indexURL = AppPaths.workspaceIndexFile(for: workspacePath)
    guard FileManager.default.fileExists(atPath: indexURL.path) else {
      return nil
    }
    let data = try Data(contentsOf: indexURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let document: WorkspaceIndexDocument
    do {
      document = try decoder.decode(WorkspaceIndexDocument.self, from: data)
    } catch {
      let legacy = try decoder.decode(LegacyWorkspaceIndexDocument.self, from: data)
      let migratedStatus = WorkspaceIndexStatus(
        workspacePath: legacy.status.workspacePath,
        mode: .coreMLEmbedding,
        modelID: legacy.status.modelID,
        modelName: legacy.status.modelName,
        createdAt: legacy.status.createdAt,
        fileCount: legacy.status.fileCount,
        chunkCount: legacy.status.chunkCount,
        embeddingDimension: legacy.status.embeddingDimension,
        indexedCharacterCount: legacy.status.indexedCharacterCount
      )
      document = WorkspaceIndexDocument(
        status: migratedStatus,
        chunks: legacy.chunks.map {
          WorkspaceIndexChunk(
            id: $0.id,
            relativePath: $0.relativePath,
            startLine: $0.startLine,
            endLine: $0.endLine,
            text: $0.text,
            embedding: $0.embedding
          )
        }
      )
      try Self.save(document, workspacePath: workspacePath)
    }
    cache[workspacePath] = document
    return document
  }

  private static func save(
    _ document: WorkspaceIndexDocument,
    workspacePath: String
  ) throws {
    try AppPaths.ensureDirectories()
    let indexURL = AppPaths.workspaceIndexFile(for: workspacePath)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(document)
    try data.write(to: indexURL, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: indexURL.path
    )
  }

  private static func validatedWorkspaceURL(_ workspacePath: String) throws -> URL {
    let expanded = NSString(string: workspacePath).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded, isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(
      atPath: url.path,
      isDirectory: &isDirectory
    ), isDirectory.boolValue else {
      throw WorkspaceIndexError.invalidWorkspace(workspacePath)
    }
    return url
  }

  private static func collectChunks(
    in workspaceURL: URL
  ) throws -> (
    chunks: [PendingChunk],
    fileCount: Int,
    indexedCharacterCount: Int
  ) {
    let keys: Set<URLResourceKey> = [
      .isDirectoryKey,
      .isRegularFileKey,
      .isSymbolicLinkKey,
      .fileSizeKey,
    ]
    var enumerationError: Error?
    guard let enumerator = FileManager.default.enumerator(
      at: workspaceURL,
      includingPropertiesForKeys: Array(keys),
      options: [.skipsHiddenFiles, .skipsPackageDescendants],
      errorHandler: { _, error in
        enumerationError = error
        return true
      }
    ) else {
      throw WorkspaceIndexError.enumerationFailed(workspaceURL.path)
    }

    var chunks: [PendingChunk] = []
    var indexedFiles = Set<String>()
    var indexedCharacterCount = 0
    let rootPrefix = workspaceURL.path.hasSuffix("/")
      ? workspaceURL.path
      : workspaceURL.path + "/"

    while let fileURL = enumerator.nextObject() as? URL {
      try Task.checkCancellation()
      let values = try fileURL.resourceValues(forKeys: keys)

      if values.isDirectory == true {
        if excludedDirectoryNames.contains(fileURL.lastPathComponent.lowercased()) {
          enumerator.skipDescendants()
        }
        continue
      }
      guard values.isRegularFile == true, values.isSymbolicLink != true else {
        continue
      }
      guard (values.fileSize ?? 0) <= maximumFileBytes else {
        continue
      }
      guard isSupported(fileURL), fileURL.path.hasPrefix(rootPrefix) else {
        continue
      }

      let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
      guard !data.contains(0), var text = String(data: data, encoding: .utf8) else {
        continue
      }
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        continue
      }

      let remainingCharacters = maximumIndexedCharacters - indexedCharacterCount
      guard remainingCharacters > 0 else { break }
      if text.count > remainingCharacters {
        text = String(text.prefix(remainingCharacters))
      }

      let relativePath = String(fileURL.path.dropFirst(rootPrefix.count))
      let fileChunks = makeChunks(text: text, relativePath: relativePath)
      if !fileChunks.isEmpty {
        indexedFiles.insert(relativePath)
        chunks.append(contentsOf: fileChunks)
        indexedCharacterCount += text.count
      }
      if chunks.count >= maximumChunks {
        chunks = Array(chunks.prefix(maximumChunks))
        break
      }
    }

    if let enumerationError, chunks.isEmpty {
      throw WorkspaceIndexError.enumerationFailed(
        enumerationError.localizedDescription
      )
    }
    return (chunks, indexedFiles.count, indexedCharacterCount)
  }

  private static func makeChunks(
    text: String,
    relativePath: String
  ) -> [PendingChunk] {
    let lines = text.split(
      separator: "\n",
      omittingEmptySubsequences: false
    ).map(String.init)
    guard !lines.isEmpty else { return [] }

    var result: [PendingChunk] = []
    var startIndex = 0
    while startIndex < lines.count, result.count < maximumChunks {
      var endIndex = startIndex
      var characterCount = 0
      while endIndex < lines.count {
        let nextCount = lines[endIndex].count + (endIndex > startIndex ? 1 : 0)
        if endIndex > startIndex,
          characterCount + nextCount > targetChunkCharacters
        {
          break
        }
        characterCount += nextCount
        endIndex += 1
      }
      if endIndex == startIndex {
        endIndex += 1
      }

      let chunkText = lines[startIndex..<endIndex].joined(separator: "\n")
      if !chunkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result.append(
          PendingChunk(
            relativePath: relativePath,
            startLine: startIndex + 1,
            endLine: endIndex,
            text: chunkText
          )
        )
      }

      if endIndex >= lines.count { break }
      startIndex = max(startIndex + 1, endIndex - overlapLines)
    }
    return result
  }

  private static func isSupported(_ url: URL) -> Bool {
    let name = url.lastPathComponent.lowercased()
    if supportedFileNames.contains(name) {
      return true
    }
    return supportedExtensions.contains(url.pathExtension.lowercased())
  }

  private static func lexicalSearch(
    query: String,
    chunks: [WorkspaceIndexChunk],
    limit: Int
  ) -> [WorkspaceSemanticMatch] {
    let queryTerms = tokenized(query)
    guard !queryTerms.isEmpty else { return [] }
    let normalizedQuery = query.lowercased()

    return chunks.compactMap { chunk -> WorkspaceSemanticMatch? in
      let text = chunk.text.lowercased()
      let path = chunk.relativePath.lowercased()
      let textTerms = tokenized(text)
      guard !textTerms.isEmpty else { return nil }

      var matchedTerms = 0
      var totalOccurrences = 0
      for term in queryTerms {
        let occurrences = textTerms.reduce(0) { count, candidate in
          count + (candidate == term ? 1 : 0)
        }
        if occurrences > 0 {
          matchedTerms += 1
          totalOccurrences += occurrences
        }
      }

      let pathMatches = queryTerms.reduce(0) { count, term in
        count + (path.contains(term) ? 1 : 0)
      }
      let phraseBonus = text.contains(normalizedQuery) ? 0.35 : 0
      let coverage = Double(matchedTerms) / Double(queryTerms.count)
      let frequency = min(0.35, Double(totalOccurrences) * 0.025)
      let pathBonus = min(0.25, Double(pathMatches) * 0.08)
      let score = coverage + frequency + pathBonus + phraseBonus
      guard score > 0 else { return nil }

      return WorkspaceSemanticMatch(
        id: chunk.id,
        relativePath: chunk.relativePath,
        startLine: chunk.startLine,
        endLine: chunk.endLine,
        score: score,
        excerpt: excerpt(chunk.text)
      )
    }
    .sorted { lhs, rhs in
      if lhs.score == rhs.score {
        if lhs.relativePath == rhs.relativePath {
          return lhs.startLine < rhs.startLine
        }
        return lhs.relativePath < rhs.relativePath
      }
      return lhs.score > rhs.score
    }
    .prefix(limit)
    .map { $0 }
  }

  private static func tokenized(_ text: String) -> [String] {
    text.lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { $0.count >= 2 }
  }

  private static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
    guard lhs.count == rhs.count else { return -1 }
    var dot = Float.zero
    for index in lhs.indices {
      dot += lhs[index] * rhs[index]
    }
    return Double(dot)
  }

  private static func excerpt(_ text: String) -> String {
    let compact = text
      .replacingOccurrences(of: "\r", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let limit = 900
    return compact.count > limit
      ? String(compact.prefix(limit)) + "\n…"
      : compact
  }
}
