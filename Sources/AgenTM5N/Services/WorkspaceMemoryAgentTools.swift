import Foundation

public enum WorkspaceMemoryAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "workspace_index_status",
      description: "Return the local workspace index status, including lexical or Core ML semantic mode, counts and warnings. Never exposes embedding vectors or internal index paths.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "workspace_index_build",
      description: "Build or replace the local workspace index. Without model, build a lexical index that always works. With a compatible registered Core ML model, add semantic embeddings. An incompatible model falls back to lexical mode with a warning.",
      parameters: objectSchema(
        properties: [
          "model": stringSchema("Optional registered Core ML model name or UUID. Omit this argument to build a lexical index without Core ML.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "workspace_semantic_search",
      description: "Search the active workspace index. Uses Core ML similarity when semantic vectors exist and lexical ranking otherwise. Returns relative paths, line ranges, scores and bounded excerpts.",
      parameters: objectSchema(
        required: ["query"],
        properties: [
          "query": stringSchema("Natural-language or code-oriented search query."),
          "limit": integerSchema(
            description: "Optional result count from 1 to 20.",
            minimum: 1,
            maximum: 20
          ),
        ]
      )
    ),
    ProviderToolDefinition(
      name: "workspace_index_clear",
      description: "Delete the local workspace index. Source files and Core ML models are not modified.",
      parameters: objectSchema(properties: [:])
    ),
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for call: ProviderToolCall) -> ToolRisk {
    switch call.function.name {
    case "workspace_index_status", "workspace_semantic_search":
      return .read
    case "workspace_index_clear":
      return .write
    default:
      return .execute
    }
  }

  public static func summary(for call: ProviderToolCall) -> String {
    let values = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      let description = value.compactDescription
      if key == "query", description.count > 180 {
        return "query: \(description.prefix(180))…"
      }
      return "\(key): \(description)"
    }
    return values.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(values.joined(separator: ", "))"
  }

  private static func objectSchema(
    required: [String] = [],
    properties: [String: JSONValue]
  ) -> JSONValue {
    var schema: [String: JSONValue] = [
      "type": .string("object"),
      "properties": .object(properties),
      "additionalProperties": .bool(false),
    ]
    if !required.isEmpty {
      schema["required"] = .array(required.map(JSONValue.string))
    }
    return .object(schema)
  }

  private static func stringSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("string"),
      "description": .string(description),
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
      "maximum": .number(Double(maximum)),
    ])
  }
}
