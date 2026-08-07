import Foundation

public enum UnifiedContextSourceKind: String, Codable, Sendable {
  case workspace
  case attachment
  case knowledge
}

public enum UnifiedContextToolError: LocalizedError {
  case missingArgument(tool: String, name: String)
  case emptyQuery
  case sourceNotFound(String)
  case invalidSourceID(String)

  public var errorDescription: String? {
    switch self {
    case .missingArgument(let tool, let name):
      return L10n.text(
        de: "Werkzeug \(tool) benötigt das Argument \(name).",
        en: "Tool \(tool) requires argument \(name).",
        fr: "L’outil \(tool) nécessite l’argument \(name)."
      )
    case .emptyQuery:
      return L10n.text(
        de: "Die Kontextsuche darf nicht leer sein.",
        en: "The context search query must not be empty.",
        fr: "La recherche de contexte ne doit pas être vide."
      )
    case .sourceNotFound(let sourceID):
      return L10n.text(
        de: "Die Kontextquelle wurde nicht gefunden: \(sourceID)",
        en: "The context source was not found: \(sourceID)",
        fr: "La source de contexte est introuvable : \(sourceID)"
      )
    case .invalidSourceID(let sourceID):
      return L10n.text(
        de: "Ungültige Kontext-Source-ID: \(sourceID)",
        en: "Invalid context source ID: \(sourceID)",
        fr: "Identifiant de source de contexte invalide : \(sourceID)"
      )
    }
  }
}

public enum UnifiedContextAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "context_search",
      description: "Search AgenTM5N context across the current conversation attachments, the persistent Knowledge Library, and the existing Workspace Memory index. Returns ranked bounded excerpts with stable source IDs and never exposes internal paths, hashes, embeddings, or binary data.",
      parameters: objectSchema(
        required: ["query"],
        properties: [
          "query": stringSchema("Natural-language or literal search query."),
          "scope": stringSchema("Optional scope: all, attachments, knowledge, or workspace. Defaults to all."),
          "limit": integerSchema(
            description: "Optional total result count from 1 to 20.",
            minimum: 1,
            maximum: 20
          )
        ]
      )
    ),
    ProviderToolDefinition(
      name: "context_read_source",
      description: "Read one bounded source returned by context_search using its stable source_id. The source is re-resolved locally from the current conversation, Knowledge Library, or Workspace Memory index.",
      parameters: objectSchema(
        required: ["source_id"],
        properties: [
          "source_id": stringSchema("Exact source_id returned by context_search."),
          "maximum_characters": integerSchema(
            description: "Optional content limit from 500 to 12000 characters.",
            minimum: 500,
            maximum: 12_000
          )
        ]
      )
    )
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for _: ProviderToolCall) -> ToolRisk {
    .read
  }

  public static func summary(for call: ProviderToolCall) -> String {
    let values = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      let description = value.compactDescription
      return description.count > 180
        ? "\(key): \(description.prefix(180))…"
        : "\(key): \(description)"
    }
    return values.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(values.joined(separator: ", "))"
  }

  public static func execute(
    call: ProviderToolCall,
    messages: [ChatMessage]
  ) -> ToolExecutionResult {
    do {
      switch call.function.name {
      case "context_search":
        return try search(call: call, messages: messages)
      case "context_read_source":
        return try readSource(call: call, messages: messages)
      default:
        return ToolExecutionResult(
          success: false,
          output: "Unsupported unified context tool: \(call.function.name)"
        )
      }
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private enum SearchScope: String {
    case all
    case attachments
    case knowledge
    case workspace
  }

  private struct Candidate: Sendable {
    let sourceID: String
    let kind: UnifiedContextSourceKind
    let title: String
    let locator: String
    let text: String
  }

  private struct MatchDescriptor: Encodable {
    let sourceID: String
    let sourceKind: String
    let title: String
    let locator: String
    let score: Int
    let excerpt: String
  }

  private struct SearchEnvelope: Encodable {
    let query: String
    let requestedScope: String
    let searchedSources: [String]
    let warnings: [String]
    let matches: [MatchDescriptor]
  }

  private struct ReadDescriptor: Encodable {
    let sourceID: String
    let sourceKind: String
    let title: String
    let locator: String
    let content: String
    let truncated: Bool
  }

  private struct AttachmentRecord: Sendable {
    let id: String
    let name: String
    let content: String
  }

  private static func search(
    call: ProviderToolCall,
    messages: [ChatMessage]
  ) throws -> ToolExecutionResult {
    let query = try requiredString("query", in: call)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { throw UnifiedContextToolError.emptyQuery }

    let scope = SearchScope(
      rawValue: optionalString("scope", in: call)?.lowercased() ?? "all"
    ) ?? .all
    let limit = max(1, min(optionalInt("limit", in: call) ?? 10, 20))

    var candidates: [Candidate] = []
    var searchedSources: [String] = []
    var warnings: [String] = []

    if scope == .all || scope == .attachments {
      searchedSources.append(UnifiedContextSourceKind.attachment.rawValue)
      candidates.append(contentsOf: attachmentCandidates(messages: messages))
    }

    if scope == .all || scope == .knowledge {
      searchedSources.append(UnifiedContextSourceKind.knowledge.rawValue)
      do {
        candidates.append(contentsOf: try knowledgeCandidates())
      } catch {
        warnings.append(
          L10n.text(
            de: "Knowledge Library konnte nicht gelesen werden: \(error.localizedDescription)",
            en: "Knowledge Library could not be read: \(error.localizedDescription)",
            fr: "La bibliothèque de connaissances n’a pas pu être lue : \(error.localizedDescription)"
          )
        )
      }
    }

    if scope == .all || scope == .workspace {
      searchedSources.append(UnifiedContextSourceKind.workspace.rawValue)
      do {
        candidates.append(contentsOf: try workspaceCandidates())
      } catch {
        warnings.append(
          L10n.text(
            de: "Workspace Memory konnte nicht gelesen werden: \(error.localizedDescription)",
            en: "Workspace Memory could not be read: \(error.localizedDescription)",
            fr: "La mémoire de l’espace de travail n’a pas pu être lue : \(error.localizedDescription)"
          )
        )
      }
    }

    let terms = searchTerms(query)
    let matches = candidates.compactMap { candidate -> MatchDescriptor? in
      let score = lexicalScore(
        query: query,
        terms: terms,
        title: candidate.title,
        locator: candidate.locator,
        text: candidate.text
      )
      guard score > 0 else { return nil }
      return MatchDescriptor(
        sourceID: candidate.sourceID,
        sourceKind: candidate.kind.rawValue,
        title: candidate.title,
        locator: candidate.locator,
        score: score,
        excerpt: excerpt(
          text: candidate.text,
          query: query,
          terms: terms,
          maximumCharacters: 900
        )
      )
    }
    .sorted { lhs, rhs in
      if lhs.score != rhs.score { return lhs.score > rhs.score }
      if lhs.sourceKind != rhs.sourceKind { return lhs.sourceKind < rhs.sourceKind }
      if lhs.title != rhs.title { return lhs.title < rhs.title }
      return lhs.locator < rhs.locator
    }

    return encoded(
      SearchEnvelope(
        query: query,
        requestedScope: scope.rawValue,
        searchedSources: searchedSources,
        warnings: warnings,
        matches: Array(matches.prefix(limit))
      )
    )
  }

  private static func readSource(
    call: ProviderToolCall,
    messages: [ChatMessage]
  ) throws -> ToolExecutionResult {
    let sourceID = try requiredString("source_id", in: call)
    let maximum = max(
      500,
      min(optionalInt("maximum_characters", in: call) ?? 6_000, 12_000)
    )

    let candidate: Candidate?
    if sourceID.hasPrefix("context://attachment/") {
      candidate = attachmentCandidates(messages: messages).first {
        $0.sourceID == sourceID
      }
    } else if sourceID.hasPrefix("context://knowledge/") {
      candidate = try knowledgeCandidate(sourceID: sourceID)
    } else if sourceID.hasPrefix("context://workspace/") {
      candidate = try workspaceCandidate(sourceID: sourceID)
    } else {
      throw UnifiedContextToolError.invalidSourceID(sourceID)
    }

    guard let candidate else {
      throw UnifiedContextToolError.sourceNotFound(sourceID)
    }

    let content = String(candidate.text.prefix(maximum))
    return encoded(
      ReadDescriptor(
        sourceID: candidate.sourceID,
        sourceKind: candidate.kind.rawValue,
        title: candidate.title,
        locator: candidate.locator,
        content: content,
        truncated: candidate.text.count > content.count
      )
    )
  }

  private static func attachmentCandidates(messages: [ChatMessage]) -> [Candidate] {
    var result: [Candidate] = []
    for message in messages where message.role == .user {
      for record in parseTextAttachments(
        content: message.content,
        messageID: message.id
      ) {
        let sections = splitAttachmentSections(record.content)
        if sections.isEmpty {
          guard !record.content.isEmpty else { continue }
          result.append(
            Candidate(
              sourceID: "context://attachment/\(safeComponent(record.id))/body",
              kind: .attachment,
              title: record.name,
              locator: record.name,
              text: record.content
            )
          )
        } else {
          for (index, section) in sections.enumerated() {
            result.append(
              Candidate(
                sourceID: "context://attachment/\(safeComponent(record.id))/\(index + 1)",
                kind: .attachment,
                title: record.name,
                locator: section.locator,
                text: section.text
              )
            )
          }
        }
      }
    }
    return result
  }

  private static func knowledgeCandidates() throws -> [Candidate] {
    guard FileManager.default.fileExists(atPath: AppPaths.knowledgeRegistryFile.path) else {
      return []
    }
    let data = try Data(contentsOf: AppPaths.knowledgeRegistryFile, options: [.mappedIfSafe])
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let registry = try decoder.decode(KnowledgeLibraryRegistry.self, from: data)
    let enabledCollections = Set(registry.collections.filter(\.isEnabled).map(\.id))
    let collectionNames = Dictionary(
      uniqueKeysWithValues: registry.collections.map { ($0.id, $0.name) }
    )

    var result: [Candidate] = []
    for summary in registry.documents where summary.isEnabled {
      guard enabledCollections.contains(summary.collectionID) else { continue }
      let recordURL = AppPaths.knowledgeDocumentFile(id: summary.id)
      guard FileManager.default.fileExists(atPath: recordURL.path) else { continue }
      let recordData = try Data(contentsOf: recordURL, options: [.mappedIfSafe])
      let record = try decoder.decode(KnowledgeDocumentRecord.self, from: recordData)
      let collectionName = collectionNames[summary.collectionID] ?? ""
      let sections = record.sections.isEmpty
        ? [PromptAttachmentSection(locator: summary.name, text: record.extractedText)]
        : record.sections
      for section in sections {
        result.append(
          Candidate(
            sourceID: "context://knowledge/\(summary.id.uuidString.lowercased())/\(section.id.uuidString.lowercased())",
            kind: .knowledge,
            title: collectionName.isEmpty
              ? summary.name
              : "\(collectionName) / \(summary.name)",
            locator: section.locator,
            text: section.text
          )
        )
      }
    }
    return result
  }

  private static func knowledgeCandidate(sourceID: String) throws -> Candidate? {
    let parts = sourceParts(sourceID)
    guard parts.count == 5,
      parts[2] == "knowledge",
      let documentID = UUID(uuidString: parts[3]),
      let sectionID = UUID(uuidString: parts[4])
    else {
      throw UnifiedContextToolError.invalidSourceID(sourceID)
    }

    let recordURL = AppPaths.knowledgeDocumentFile(id: documentID)
    guard FileManager.default.fileExists(atPath: recordURL.path) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let recordData = try Data(contentsOf: recordURL, options: [.mappedIfSafe])
    let record = try decoder.decode(KnowledgeDocumentRecord.self, from: recordData)
    guard record.summary.isEnabled else { return nil }

    let registryData = try Data(contentsOf: AppPaths.knowledgeRegistryFile, options: [.mappedIfSafe])
    let registry = try decoder.decode(KnowledgeLibraryRegistry.self, from: registryData)
    guard let collection = registry.collections.first(where: {
      $0.id == record.summary.collectionID && $0.isEnabled
    }) else {
      return nil
    }
    guard let section = record.sections.first(where: { $0.id == sectionID }) else {
      return nil
    }
    return Candidate(
      sourceID: sourceID,
      kind: .knowledge,
      title: "\(collection.name) / \(record.summary.name)",
      locator: section.locator,
      text: section.text
    )
  }

  private static func workspaceCandidates() throws -> [Candidate] {
    guard let document = try loadWorkspaceIndex() else { return [] }
    return document.chunks.map { chunk in
      Candidate(
        sourceID: "context://workspace/\(chunk.id.uuidString.lowercased())",
        kind: .workspace,
        title: chunk.relativePath,
        locator: "\(chunk.relativePath):\(chunk.startLine)-\(chunk.endLine)",
        text: chunk.text
      )
    }
  }

  private static func workspaceCandidate(sourceID: String) throws -> Candidate? {
    let parts = sourceParts(sourceID)
    guard parts.count == 4,
      parts[2] == "workspace",
      let chunkID = UUID(uuidString: parts[3])
    else {
      throw UnifiedContextToolError.invalidSourceID(sourceID)
    }
    guard let document = try loadWorkspaceIndex(),
      let chunk = document.chunks.first(where: { $0.id == chunkID })
    else {
      return nil
    }
    return Candidate(
      sourceID: sourceID,
      kind: .workspace,
      title: chunk.relativePath,
      locator: "\(chunk.relativePath):\(chunk.startLine)-\(chunk.endLine)",
      text: chunk.text
    )
  }

  private static func loadWorkspaceIndex() throws -> WorkspaceIndexDocument? {
    guard FileManager.default.fileExists(atPath: AppPaths.configurationFile.path) else {
      return nil
    }
    let configurationData = try Data(
      contentsOf: AppPaths.configurationFile,
      options: [.mappedIfSafe]
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let configuration = try decoder.decode(AppConfiguration.self, from: configurationData)
    let workspacePath = NSString(string: configuration.workspacePath).expandingTildeInPath
    let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let indexURL = AppPaths.workspaceIndexFile(for: workspaceURL.path)
    guard FileManager.default.fileExists(atPath: indexURL.path) else { return nil }
    let data = try Data(contentsOf: indexURL, options: [.mappedIfSafe])
    let document = try decoder.decode(WorkspaceIndexDocument.self, from: data)
    guard document.status.workspacePath == workspaceURL.path else { return nil }
    return document
  }

  private static func parseTextAttachments(
    content: String,
    messageID: UUID
  ) -> [AttachmentRecord] {
    guard let expression = try? NSRegularExpression(
      pattern: #"<agentm5n_attachment\s+name=\"([^\"]*)\"\s+media_type=\"([^\"]*)\"\s+bytes=\"([0-9]+)\"\s+truncated=\"(true|false)\">([\s\S]*?)</agentm5n_attachment>"#,
      options: []
    ) else {
      return []
    }

    let range = NSRange(content.startIndex..<content.endIndex, in: content)
    return expression.matches(in: content, range: range).enumerated().compactMap {
      index, match in
      guard match.numberOfRanges == 6,
        let nameRange = Range(match.range(at: 1), in: content),
        let bodyRange = Range(match.range(at: 5), in: content)
      else {
        return nil
      }
      return AttachmentRecord(
        id: "\(messageID.uuidString.lowercased()):text:\(index + 1)",
        name: unescape(String(content[nameRange])),
        content: String(content[bodyRange]).trimmingCharacters(
          in: .whitespacesAndNewlines
        )
      )
    }
  }

  private static func splitAttachmentSections(
    _ content: String
  ) -> [(locator: String, text: String)] {
    guard let expression = try? NSRegularExpression(
      pattern: #"(?m)^\[Datei:\s*([^\]]+)\]$"#,
      options: []
    ) else {
      return []
    }
    let fullRange = NSRange(content.startIndex..<content.endIndex, in: content)
    let matches = expression.matches(in: content, range: fullRange)
    guard !matches.isEmpty else { return [] }

    var result: [(locator: String, text: String)] = []
    for (index, match) in matches.enumerated() {
      guard match.numberOfRanges > 1,
        let locatorRange = Range(match.range(at: 1), in: content),
        let markerRange = Range(match.range(at: 0), in: content)
      else {
        continue
      }
      let end: String.Index
      if index + 1 < matches.count,
        let nextRange = Range(matches[index + 1].range(at: 0), in: content)
      {
        end = nextRange.lowerBound
      } else {
        end = content.endIndex
      }
      let text = String(content[markerRange.lowerBound..<end])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      result.append((String(content[locatorRange]), text))
    }
    return result
  }

  private static func searchTerms(_ query: String) -> [String] {
    let normalized = query
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
    let raw = normalized.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    return Array(Set(raw.filter { $0.count >= 2 })).sorted()
  }

  private static func lexicalScore(
    query: String,
    terms: [String],
    title: String,
    locator: String,
    text: String
  ) -> Int {
    let foldedQuery = fold(query)
    let foldedTitle = fold(title)
    let foldedLocator = fold(locator)
    let foldedText = fold(text)
    var score = 0

    if !foldedQuery.isEmpty {
      let phraseCount = occurrenceCount(foldedQuery, in: foldedText)
      score += min(phraseCount, 5) * 80
      if foldedTitle.contains(foldedQuery) { score += 70 }
      if foldedLocator.contains(foldedQuery) { score += 50 }
    }

    for term in terms {
      score += min(occurrenceCount(term, in: foldedText), 20) * 5
      if foldedTitle.contains(term) { score += 18 }
      if foldedLocator.contains(term) { score += 12 }
    }
    return score
  }

  private static func excerpt(
    text: String,
    query: String,
    terms: [String],
    maximumCharacters: Int
  ) -> String {
    guard text.count > maximumCharacters else {
      return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let foldedText = fold(text)
    let foldedQuery = fold(query)
    var offset: Int?
    if let range = foldedText.range(of: foldedQuery), !foldedQuery.isEmpty {
      offset = foldedText.distance(from: foldedText.startIndex, to: range.lowerBound)
    }
    if offset == nil {
      for term in terms {
        if let range = foldedText.range(of: term) {
          offset = foldedText.distance(from: foldedText.startIndex, to: range.lowerBound)
          break
        }
      }
    }

    let center = offset ?? 0
    let startOffset = max(0, center - maximumCharacters / 3)
    let start = text.index(text.startIndex, offsetBy: min(startOffset, text.count))
    let remaining = text.distance(from: start, to: text.endIndex)
    let end = text.index(start, offsetBy: min(maximumCharacters, remaining))
    return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func occurrenceCount(_ needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var searchRange = haystack.startIndex..<haystack.endIndex
    while let range = haystack.range(of: needle, range: searchRange) {
      count += 1
      searchRange = range.upperBound..<haystack.endIndex
    }
    return count
  }

  private static func fold(_ value: String) -> String {
    value
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
  }

  private static func sourceParts(_ sourceID: String) -> [String] {
    sourceID.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
  }

  private static func safeComponent(_ value: String) -> String {
    Data(value.utf8).base64EncodedString()
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "=", with: "")
  }

  private static func unescape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&amp;", with: "&")
  }

  private static func requiredString(
    _ name: String,
    in call: ProviderToolCall
  ) throws -> String {
    guard let value = optionalString(name, in: call), !value.isEmpty else {
      throw UnifiedContextToolError.missingArgument(
        tool: call.function.name,
        name: name
      )
    }
    return value
  }

  private static func optionalString(
    _ name: String,
    in call: ProviderToolCall
  ) -> String? {
    guard let value = call.function.arguments[name], case .string(let text) = value else {
      return nil
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func optionalInt(
    _ name: String,
    in call: ProviderToolCall
  ) -> Int? {
    guard let value = call.function.arguments[name], case .number(let number) = value else {
      return nil
    }
    return number.isFinite ? Int(number) : nil
  }

  private static func encoded<T: Encodable>(_ value: T) -> ToolExecutionResult {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(value)
      return ToolExecutionResult(
        success: true,
        output: String(decoding: data, as: UTF8.self)
      )
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private static func objectSchema(
    required: [String] = [],
    properties: [String: JSONValue]
  ) -> JSONValue {
    var schema: [String: JSONValue] = [
      "type": .string("object"),
      "properties": .object(properties),
      "additionalProperties": .bool(false)
    ]
    if !required.isEmpty {
      schema["required"] = .array(required.map(JSONValue.string))
    }
    return .object(schema)
  }

  private static func stringSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("string"),
      "description": .string(description)
    ])
  }

  private static func integerSchema(
    description: String,
    minimum: Int,
    maximum: Int
  ) -> JSONValue {
    .object([
      "type": .string("integer"),
      "description": .string(description),
      "minimum": .number(Double(minimum)),
      "maximum": .number(Double(maximum))
    ])
  }
}
