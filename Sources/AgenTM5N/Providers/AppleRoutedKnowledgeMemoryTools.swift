import Foundation
import FoundationModels

public enum AppleRoutedKnowledgeMemoryTools {
  public static func makeMemoryTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      AppleWorkspaceIndexStatusTool(bridge: bridge),
      AppleWorkspaceIndexBuildTool(bridge: bridge),
      AppleWorkspaceSemanticSearchTool(bridge: bridge),
      AppleWorkspaceIndexClearTool(bridge: bridge),
    ]
  }

  public static func makeContextTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      AppleContextSearchTool(bridge: bridge),
      AppleContextReadSourceTool(bridge: bridge),
    ]
  }

  public static func makeKnowledgeTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      AppleKnowledgeListCollectionsTool(bridge: bridge),
      AppleKnowledgeSearchTool(bridge: bridge),
      AppleKnowledgeReadSourceTool(bridge: bridge),
      AppleKnowledgeImportTool(bridge: bridge),
    ]
  }

  public static func makeAttachmentTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      AppleAttachmentListTool(bridge: bridge),
      AppleAttachmentSearchTool(bridge: bridge),
      AppleAttachmentReadSectionTool(bridge: bridge),
    ]
  }

  public static func makeDocumentTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      AppleDocumentGenerateTool(bridge: bridge),
      AppleDocumentListTool(bridge: bridge),
      AppleDocumentDeleteTool(bridge: bridge),
    ]
  }

  public static func makeCoreMLTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      AppleCoreMLListTool(bridge: bridge),
      AppleCoreMLDescribeTool(bridge: bridge),
      AppleCoreMLPredictTool(bridge: bridge),
    ]
  }
}

private struct AppleWorkspaceIndexStatusTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "workspace_index_status"
  let description = "Read the status of the local Workspace Memory index, including whether semantic Core ML embeddings are active."
  @Generable struct Arguments { @Guide(description: "Use current") var query: String }
  func call(arguments: Arguments) async throws -> String {
    await routeKnowledge(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleWorkspaceIndexBuildTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "workspace_index_build"
  let description = "Build or rebuild local Workspace Memory. Optionally name a registered Core ML embedding model; empty uses lexical mode."
  @Generable struct Arguments { @Guide(description: "Optional Core ML embedding model name or UUID; empty for lexical mode") var model: String }
  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [:]
    if !arguments.model.isEmpty { values["model"] = .string(arguments.model) }
    return await routeKnowledge(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleWorkspaceSemanticSearchTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "workspace_semantic_search"
  let description = "Search Workspace Memory by meaning. When an embedding model is configured, AgenTM5N runs the query embedding locally through Core ML with CPU + Apple Neural Engine policy."
  @Generable
  struct Arguments {
    @Guide(description: "Natural-language search query") var query: String
    @Guide(description: "Maximum matches from 1 to 20") var limit: Int
  }
  func call(arguments: Arguments) async throws -> String {
    await routeKnowledge(
      bridge: bridge,
      name: name,
      arguments: [
        "query": .string(arguments.query),
        "limit": .number(Double(arguments.limit)),
      ]
    )
  }
}

private struct AppleWorkspaceIndexClearTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "workspace_index_clear"
  let description = "Delete the local Workspace Memory index for the current workspace."
  @Generable struct Arguments { @Guide(description: "Use current") var query: String }
  func call(arguments: Arguments) async throws -> String {
    await routeKnowledge(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleContextSearchTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "context_search"
  let description = "Search current attachments, persistent Knowledge Library, and Workspace Memory and return ranked bounded source excerpts."
  @Generable
  struct Arguments {
    @Guide(description: "Natural-language or literal query") var query: String
    @Guide(description: "all, attachments, knowledge, or workspace") var scope: String
    @Guide(description: "Maximum matches from 1 to 20") var limit: Int
  }
  func call(arguments: Arguments) async throws -> String {
    await routeKnowledge(
      bridge: bridge,
      name: name,
      arguments: [
        "query": .string(arguments.query),
        "scope": .string(arguments.scope),
        "limit": .number(Double(arguments.limit)),
      ]
    )
  }
}

private struct AppleContextReadSourceTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "context_read_source"
  let description = "Read one bounded context source returned by context_search using its exact source_id."
  @Generable
  struct Arguments {
    @Guide(description: "Exact source_id") var sourceID: String
    @Guide(description: "Maximum characters from 500 to 12000") var maximumCharacters: Int
  }
  func call(arguments: Arguments) async throws -> String {
    await routeKnowledge(
      bridge: bridge,
      name: name,
      arguments: [
        "source_id": .string(arguments.sourceID),
        "maximum_characters": .number(Double(arguments.maximumCharacters)),
      ]
    )
  }
}

private struct AppleKnowledgeListCollectionsTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "knowledge_list_collections"
  let description = "List persistent local AgenTM5N knowledge collections without internal paths."
  @Generable struct Arguments { @Guide(description: "Use all") var query: String }
  func call(arguments: Arguments) async throws -> String {
    await routeKnowledge(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleKnowledgeSearchTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "knowledge_search"
  let description = "Search persistent local knowledge documents and return source locators and bounded excerpts."
  @Generable
  struct Arguments {
    @Guide(description: "Search query") var query: String
    @Guide(description: "Optional exact collection name or UUID; empty searches enabled collections") var collection: String
    @Guide(description: "Maximum results from 1 to 20") var limit: Int
  }
  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "query": .string(arguments.query),
      "limit": .number(Double(arguments.limit)),
    ]
    if !arguments.collection.isEmpty { values["collection"] = .string(arguments.collection) }
    return await routeKnowledge(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleKnowledgeReadSourceTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "knowledge_read_source"
  let description = "Read one bounded section of a persistent local knowledge document."
  @Generable
  struct Arguments {
    @Guide(description: "Exact document name or UUID") var document: String
    @Guide(description: "Optional collection name or UUID; empty if unnecessary") var collection: String
    @Guide(description: "Optional source locator; empty reads a bounded default section") var locator: String
    @Guide(description: "Maximum characters from 500 to 12000") var maximumCharacters: Int
  }
  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "document": .string(arguments.document),
      "maximum_characters": .number(Double(arguments.maximumCharacters)),
    ]
    if !arguments.collection.isEmpty { values["collection"] = .string(arguments.collection) }
    if !arguments.locator.isEmpty { values["locator"] = .string(arguments.locator) }
    return await routeKnowledge(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleKnowledgeImportTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "knowledge_import_document"
  let description = "Import one supported file from inside the configured workspace into an existing persistent knowledge collection."
  @Generable
  struct Arguments {
    @Guide(description: "Exact collection name or UUID") var collection: String
    @Guide(description: "Workspace-relative or in-workspace file path") var path: String
  }
  func call(arguments: Arguments) async throws -> String {
    await routeKnowledge(
      bridge: bridge,
      name: name,
      arguments: [
        "collection": .string(arguments.collection),
        "path": .string(arguments.path),
      ]
    )
  }
}

private struct AppleAttachmentListTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "attachment_list"
  let description = "List files and images attached in the current conversation without binary data or internal paths."
  @Generable struct Arguments { @Guide(description: "Use all") var query: String }
  func call(arguments: Arguments) async throws -> String {
    await routeKnowledge(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleAttachmentSearchTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "attachment_search"
  let description = "Search extracted text or OCR text in current conversation attachments."
  @Generable
  struct Arguments {
    @Guide(description: "Search query") var query: String
    @Guide(description: "Optional exact attachment name or ID; empty searches all") var attachment: String
    @Guide(description: "Maximum results from 1 to 20") var limit: Int
  }
  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "query": .string(arguments.query),
      "limit": .number(Double(arguments.limit)),
    ]
    if !arguments.attachment.isEmpty { values["attachment"] = .string(arguments.attachment) }
    return await routeKnowledge(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleAttachmentReadSectionTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "attachment_read_section"
  let description = "Read one bounded source section from an attachment in the current conversation."
  @Generable
  struct Arguments {
    @Guide(description: "Exact attachment name or ID") var attachment: String
    @Guide(description: "Optional locator such as Seite 3 or Folie 7; empty reads the first section") var section: String
    @Guide(description: "Maximum characters from 500 to 12000") var maximumCharacters: Int
  }
  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "attachment": .string(arguments.attachment),
      "maximum_characters": .number(Double(arguments.maximumCharacters)),
    ]
    if !arguments.section.isEmpty { values["section"] = .string(arguments.section) }
    return await routeKnowledge(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleDocumentGenerateTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "document_generate"
  let description = "Generate a local managed DOCX, PDF, XLSX, or PPTX document through AgenTM5N Document Studio."
  @Generable
  struct Arguments {
    @Guide(description: "docx, pdf, xlsx, or pptx") var format: String
    @Guide(description: "Document title") var title: String
    @Guide(description: "Optional filename; empty lets AgenTM5N choose") var filename: String
    @Guide(description: "Document content") var content: String
  }
  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "format": .string(arguments.format),
      "title": .string(arguments.title),
      "content": .string(arguments.content),
    ]
    if !arguments.filename.isEmpty { values["filename"] = .string(arguments.filename) }
    return await routeKnowledge(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleDocumentListTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "document_list_generated"
  let description = "List locally generated AgenTM5N documents without managed storage paths."
  @Generable struct Arguments { @Guide(description: "Use all") var query: String }
  func call(arguments: Arguments) async throws -> String {
    await routeKnowledge(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleDocumentDeleteTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "document_delete_generated"
  let description = "Delete one managed generated document by exact ID, filename, or title."
  @Generable struct Arguments { @Guide(description: "Exact document ID, filename, or title") var document: String }
  func call(arguments: Arguments) async throws -> String {
    await routeKnowledge(bridge: bridge, name: name, arguments: ["document": .string(arguments.document)])
  }
}

private struct AppleCoreMLListTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "coreml_list_models"
  let description = "List registered local Core ML models and their inputs, outputs, active state, and compute policy."
  @Generable struct Arguments { @Guide(description: "Use all") var query: String }
  func call(arguments: Arguments) async throws -> String {
    await routeKnowledge(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleCoreMLDescribeTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "coreml_describe_model"
  let description = "Describe one registered Core ML model by name or UUID. Empty selects the active model."
  @Generable struct Arguments { @Guide(description: "Optional model name or UUID; empty for active") var model: String }
  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [:]
    if !arguments.model.isEmpty { values["model"] = .string(arguments.model) }
    return await routeKnowledge(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleCoreMLPredictTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "coreml_predict"
  let description = "Run one local Core ML prediction. Input is a JSON object string. Supports scalar features, nested numeric arrays for MLMultiArray, and local image-path strings for image features."
  @Generable
  struct Arguments {
    @Guide(description: "Optional registered model name or UUID; empty for active") var model: String
    @Guide(description: "JSON object matching the model input names") var inputJson: String
  }
  func call(arguments: Arguments) async throws -> String {
    guard let input = parseJSONObject(arguments.inputJson) else {
      return "TOOL_ERROR: coreml_predict inputJson must be a valid JSON object."
    }
    var values: [String: JSONValue] = ["input": .object(input)]
    if !arguments.model.isEmpty { values["model"] = .string(arguments.model) }
    return await routeKnowledge(bridge: bridge, name: name, arguments: values)
  }
}

private func routeKnowledge(
  bridge: AgentToolExecutionBridge,
  name: String,
  arguments: [String: JSONValue]
) async -> String {
  await bridge.execute(
    ProviderToolCall(function: .init(name: name, arguments: arguments))
  )
}

private func parseJSONObject(_ text: String) -> [String: JSONValue]? {
  guard let data = text.data(using: .utf8),
    let raw = try? JSONSerialization.jsonObject(with: data),
    let object = raw as? [String: Any]
  else { return nil }
  var result: [String: JSONValue] = [:]
  for (key, value) in object {
    guard let converted = knowledgeJSONValue(value) else { return nil }
    result[key] = converted
  }
  return result
}

private func knowledgeJSONValue(_ value: Any) -> JSONValue? {
  switch value {
  case let string as String: return .string(string)
  case let bool as Bool: return .bool(bool)
  case let number as NSNumber: return .number(number.doubleValue)
  case let object as [String: Any]:
    var result: [String: JSONValue] = [:]
    for (key, raw) in object {
      guard let converted = knowledgeJSONValue(raw) else { return nil }
      result[key] = converted
    }
    return .object(result)
  case let array as [Any]:
    var result: [JSONValue] = []
    result.reserveCapacity(array.count)
    for raw in array {
      guard let converted = knowledgeJSONValue(raw) else { return nil }
      result.append(converted)
    }
    return .array(result)
  case _ as NSNull: return .null
  default: return nil
  }
}
