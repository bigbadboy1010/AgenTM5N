import Foundation

public enum KnowledgeLibraryAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "knowledge_list_collections",
      description: "List persistent local AgenTM5N knowledge collections with stable collection IDs, enabled state and document counts. Never returns internal paths or content hashes.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "knowledge_list_documents",
      description: "List managed documents in one persistent knowledge collection. Returns stable document IDs and bounded metadata without internal paths or hashes.",
      parameters: objectSchema(
        required: ["collection"],
        properties: [
          "collection": stringSchema("Exact collection name or collection UUID returned by knowledge_list_collections.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "knowledge_search",
      description: "Search enabled persistent knowledge documents using local lexical ranking. Returns collection, document, source locator, score and bounded excerpt.",
      parameters: objectSchema(
        required: ["query"],
        properties: [
          "query": stringSchema("Natural-language or literal search query."),
          "collection": stringSchema("Optional collection name or UUID to restrict the search."),
          "limit": integerSchema(
            description: "Optional result count from 1 to 20.",
            minimum: 1,
            maximum: 20
          )
        ]
      )
    ),
    ProviderToolDefinition(
      name: "knowledge_read_source",
      description: "Read one bounded source section from a managed persistent knowledge document. Use knowledge_search or knowledge_list_documents to identify the document first.",
      parameters: objectSchema(
        required: ["document"],
        properties: [
          "document": stringSchema("Exact document name or document UUID."),
          "collection": stringSchema("Optional collection name or UUID for disambiguation."),
          "locator": stringSchema("Optional source locator such as a PDF page, slide, sheet range or document section."),
          "maximum_characters": integerSchema(
            description: "Optional content limit from 500 to 12000 characters.",
            minimum: 500,
            maximum: 12_000
          )
        ]
      )
    ),
    ProviderToolDefinition(
      name: "knowledge_import_document",
      description: "Import or update one supported file from inside the configured workspace into a persistent AgenTM5N knowledge collection. The file is copied into protected managed storage and extracted locally. Paths outside the workspace are always rejected.",
      parameters: objectSchema(
        required: ["collection", "path"],
        properties: [
          "collection": stringSchema("Exact collection name or UUID."),
          "path": stringSchema("File path inside the configured workspace. Relative paths are resolved below the workspace root.")
        ]
      )
    )
  ] + UnifiedContextAgentTools.definitions
    + GeneratedDocumentAgentTools.definitions
    + MacNativeAgentTools.definitions

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for call: ProviderToolCall) -> ToolRisk {
    if GeneratedDocumentAgentTools.handles(call) {
      return GeneratedDocumentAgentTools.risk(for: call)
    }
    if MacNativeAgentTools.handles(call) {
      return MacNativeAgentTools.risk(for: call)
    }
    if UnifiedContextAgentTools.handles(call) {
      return UnifiedContextAgentTools.risk(for: call)
    }
    switch call.function.name {
    case "knowledge_import_document":
      return .write
    default:
      return .read
    }
  }

  public static func summary(for call: ProviderToolCall) -> String {
    if GeneratedDocumentAgentTools.handles(call) {
      return GeneratedDocumentAgentTools.summary(for: call)
    }
    if MacNativeAgentTools.handles(call) {
      return MacNativeAgentTools.summary(for: call)
    }
    if UnifiedContextAgentTools.handles(call) {
      return UnifiedContextAgentTools.summary(for: call)
    }
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
    service: KnowledgeLibraryService = .shared,
    workspacePath: String
  ) async -> ToolExecutionResult {
    if GeneratedDocumentAgentTools.handles(call) {
      return await GeneratedDocumentAgentTools.execute(call: call)
    }

    if MacNativeAgentTools.handles(call) {
      return await MacNativeAgentTools.execute(call: call)
    }

    if UnifiedContextAgentTools.handles(call) {
      return UnifiedContextAgentTools.execute(
        call: call,
        messages: persistedConversationMessages()
      )
    }

    do {
      switch call.function.name {
      case "knowledge_list_collections":
        return try await listCollections(service: service)
      case "knowledge_list_documents":
        return try await listDocuments(call: call, service: service)
      case "knowledge_search":
        return try await search(call: call, service: service)
      case "knowledge_read_source":
        return try await readSource(call: call, service: service)
      case "knowledge_import_document":
        return try await importDocument(
          call: call,
          service: service,
          workspacePath: workspacePath
        )
      default:
        return ToolExecutionResult(
          success: false,
          output: "Unsupported knowledge tool: \(call.function.name)"
        )
      }
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private struct CollectionDescriptor: Encodable {
    let id: String
    let name: String
    let enabled: Bool
    let documentCount: Int
    let enabledDocumentCount: Int
  }

  private struct DocumentDescriptor: Encodable {
    let id: String
    let name: String
    let collectionID: String
    let collectionName: String
    let documentKind: String
    let mediaType: String
    let byteCount: Int
    let sourceSectionCount: Int
    let enabled: Bool
    let importedAt: Date
    let updatedAt: Date
  }

  private struct SearchDescriptor: Encodable {
    let documentID: String
    let documentName: String
    let collectionID: String
    let collectionName: String
    let locator: String
    let score: Int
    let excerpt: String
  }

  private struct ReadDescriptor: Encodable {
    let documentID: String
    let documentName: String
    let collectionID: String
    let collectionName: String
    let locator: String
    let content: String
    let truncated: Bool
  }

  private struct ImportDescriptor: Encodable {
    let status: String
    let documentID: String
    let documentName: String
    let collectionID: String
    let documentKind: String
    let sourceSectionCount: Int
  }

  private static func persistedConversationMessages() -> [ChatMessage] {
    guard FileManager.default.fileExists(atPath: AppPaths.conversationFile.path),
      let data = try? Data(contentsOf: AppPaths.conversationFile, options: [.mappedIfSafe])
    else {
      return []
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([ChatMessage].self, from: data)) ?? []
  }

  private static func listCollections(
    service: KnowledgeLibraryService
  ) async throws -> ToolExecutionResult {
    let snapshot = try await service.snapshot()
    let descriptors = snapshot.collections.map { collection in
      let documents = snapshot.documents.filter {
        $0.collectionID == collection.id
      }
      return CollectionDescriptor(
        id: collection.id.uuidString,
        name: collection.name,
        enabled: collection.isEnabled,
        documentCount: documents.count,
        enabledDocumentCount: documents.filter(\.isEnabled).count
      )
    }
    return encoded(descriptors)
  }

  private static func listDocuments(
    call: ProviderToolCall,
    service: KnowledgeLibraryService
  ) async throws -> ToolExecutionResult {
    let collectionQuery = try requiredString("collection", in: call)
    let collection = try await service.resolveCollectionSummary(collectionQuery)
    let snapshot = try await service.snapshot()
    let descriptors = snapshot.documents
      .filter { $0.collectionID == collection.id }
      .map { summary in
        DocumentDescriptor(
          id: summary.id.uuidString,
          name: summary.name,
          collectionID: collection.id.uuidString,
          collectionName: collection.name,
          documentKind: summary.documentKind.rawValue,
          mediaType: summary.mediaType,
          byteCount: summary.byteCount,
          sourceSectionCount: summary.sectionCount,
          enabled: summary.isEnabled,
          importedAt: summary.importedAt,
          updatedAt: summary.updatedAt
        )
      }
    return encoded(descriptors)
  }

  private static func search(
    call: ProviderToolCall,
    service: KnowledgeLibraryService
  ) async throws -> ToolExecutionResult {
    let query = try requiredString("query", in: call)
    let collection = optionalString("collection", in: call)
    let limit = optionalInt("limit", in: call) ?? 8
    let matches = try await service.search(
      query: query,
      collectionQuery: collection,
      limit: limit
    )
    return encoded(
      matches.map { match in
        SearchDescriptor(
          documentID: match.documentID.uuidString,
          documentName: match.documentName,
          collectionID: match.collectionID.uuidString,
          collectionName: match.collectionName,
          locator: match.locator,
          score: match.score,
          excerpt: match.excerpt
        )
      }
    )
  }

  private static func readSource(
    call: ProviderToolCall,
    service: KnowledgeLibraryService
  ) async throws -> ToolExecutionResult {
    let document = try requiredString("document", in: call)
    let collection = optionalString("collection", in: call)
    let locator = optionalString("locator", in: call)
    let maximum = optionalInt("maximum_characters", in: call) ?? 6_000
    let result = try await service.readSource(
      documentQuery: document,
      collectionQuery: collection,
      locatorQuery: locator,
      maximumCharacters: maximum
    )
    return encoded(
      ReadDescriptor(
        documentID: result.documentID.uuidString,
        documentName: result.documentName,
        collectionID: result.collectionID.uuidString,
        collectionName: result.collectionName,
        locator: result.locator,
        content: result.content,
        truncated: result.truncated
      )
    )
  }

  private static func importDocument(
    call: ProviderToolCall,
    service: KnowledgeLibraryService,
    workspacePath: String
  ) async throws -> ToolExecutionResult {
    let collection = try requiredString("collection", in: call)
    let path = try requiredString("path", in: call)
    let url = try workspaceFileURL(path: path, workspacePath: workspacePath)
    let results = try await service.importDocuments(
      urls: [url],
      collectionQuery: collection
    )
    guard let result = results.first else {
      return ToolExecutionResult(success: false, output: "Knowledge import returned no result.")
    }
    return encoded(
      ImportDescriptor(
        status: result.status.rawValue,
        documentID: result.document.id.uuidString,
        documentName: result.document.name,
        collectionID: result.document.collectionID.uuidString,
        documentKind: result.document.documentKind.rawValue,
        sourceSectionCount: result.document.sectionCount
      )
    )
  }

  private static func workspaceFileURL(
    path: String,
    workspacePath: String
  ) throws -> URL {
    let root = URL(
      fileURLWithPath: NSString(string: workspacePath).expandingTildeInPath,
      isDirectory: true
    ).standardizedFileURL.resolvingSymlinksInPath()
    let requested: URL
    if path.hasPrefix("/") {
      requested = URL(fileURLWithPath: path)
    } else {
      requested = root.appendingPathComponent(path)
    }
    let resolved = requested.standardizedFileURL.resolvingSymlinksInPath()
    guard resolved.path.hasPrefix(root.path + "/") else {
      throw AgentRuntimeError.pathOutsideWorkspace(path)
    }
    let values = try resolved.resourceValues(forKeys: [.isRegularFileKey])
    guard values.isRegularFile == true else {
      throw KnowledgeLibraryError.unreadableFile(resolved.lastPathComponent)
    }
    return resolved
  }

  private static func requiredString(
    _ name: String,
    in call: ProviderToolCall
  ) throws -> String {
    guard let value = optionalString(name, in: call) else {
      throw AgentRuntimeError.missingArgument(tool: call.function.name, name: name)
    }
    return value
  }

  private static func optionalString(
    _ name: String,
    in call: ProviderToolCall
  ) -> String? {
    guard let value = call.function.arguments[name]?.stringValue else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func optionalInt(
    _ name: String,
    in call: ProviderToolCall
  ) -> Int? {
    guard let value = call.function.arguments[name] else { return nil }
    guard case .number(let number) = value, number.isFinite else { return nil }
    return Int(number)
  }

  private static func encoded<T: Encodable>(_ value: T) -> ToolExecutionResult {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
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
