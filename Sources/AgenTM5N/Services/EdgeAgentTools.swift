import Foundation

public enum EdgeAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "edge_list_nodes",
      description: "List Edge-capable nodes from saved AgenTM5N SSH profiles without exposing credentials or Vault values.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "edge_list_directory",
      description: "List a bounded directory tree on an Edge node through its saved SSH profile. Intended for /data/edge and other explicitly requested remote paths.",
      parameters: objectSchema(
        required: ["host", "path"],
        properties: [
          "host": stringSchema("Saved SSH profile name, hostname, or UUID."),
          "path": stringSchema("Remote directory path."),
          "depth": integerSchema("Directory depth from 1 to 4. Defaults to 2.", minimum: 1, maximum: 4)
        ]
      )
    ),
    ProviderToolDefinition(
      name: "edge_read_file",
      description: "Read bounded text content from a file on an Edge node through its saved SSH profile.",
      parameters: objectSchema(
        required: ["host", "path"],
        properties: [
          "host": stringSchema("Saved SSH profile name, hostname, or UUID."),
          "path": stringSchema("Remote file path."),
          "max_bytes": integerSchema("Maximum bytes to read from 1 to 524288. Defaults to 65536.", minimum: 1, maximum: 524288)
        ]
      )
    ),
    ProviderToolDefinition(
      name: "edge_write_file",
      description: "Write UTF-8 text to a file on an Edge node using an atomic temporary file. By default AgenTM5N backs up an existing target before replacement and preserves its mode/ownership when possible.",
      parameters: objectSchema(
        required: ["host", "path", "content"],
        properties: [
          "host": stringSchema("Saved SSH profile name, hostname, or UUID."),
          "path": stringSchema("Remote destination file path."),
          "content": stringSchema("UTF-8 file content. Maximum 524288 bytes."),
          "create_parent": boolSchema("Create missing parent directories. Defaults to false."),
          "backup": boolSchema("Back up an existing target before replacing it. Defaults to true.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "edge_control",
      description: "Inspect or control an Edge node through the hardened SSH/Vault path. Operations: status, run, container, service, or tail. Container actions: status, start, stop, restart, logs. Service actions: status, start, stop, restart.",
      parameters: objectSchema(
        required: ["host", "operation"],
        properties: [
          "host": stringSchema("Saved SSH profile name, hostname, or UUID."),
          "operation": stringSchema("status, run, container, service, or tail."),
          "command": stringSchema("Remote shell command for operation=run."),
          "target": stringSchema("Container or systemd service name for container/service operations."),
          "action": stringSchema("Container: status/start/stop/restart/logs. Service: status/start/stop/restart."),
          "path": stringSchema("Remote log path for operation=tail."),
          "lines": integerSchema("Log lines from 1 to 2000. Defaults to 200.", minimum: 1, maximum: 2000)
        ]
      )
    )
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for call: ProviderToolCall) -> ToolRisk {
    switch call.function.name {
    case "edge_list_nodes", "edge_list_directory", "edge_read_file":
      return .read
    case "edge_write_file":
      return .write
    case "edge_control":
      let operation = call.function.arguments["operation"]?.stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ""
      let action = call.function.arguments["action"]?.stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ""
      if operation == "status" || operation == "tail" {
        return .read
      }
      if operation == "container", action == "status" || action == "logs" {
        return .read
      }
      if operation == "service", action == "status" {
        return .read
      }
      return .execute
    default:
      return .execute
    }
  }

  public static func summary(for call: ProviderToolCall) -> String {
    let values = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      if key == "content" || key == "command" {
        return "\(key): <\(value.compactDescription.utf8.count) Bytes>"
      }
      let rendered = value.compactDescription
      return "\(key): \(rendered.count > 180 ? String(rendered.prefix(180)) + "…" : rendered)"
    }
    return values.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(values.joined(separator: ", "))"
  }

  private static func objectSchema(
    required: [String] = [],
    properties: [String: JSONValue]
  ) -> JSONValue {
    var value: [String: JSONValue] = [
      "type": .string("object"),
      "properties": .object(properties),
      "additionalProperties": .bool(false)
    ]
    if !required.isEmpty {
      value["required"] = .array(required.map(JSONValue.string))
    }
    return .object(value)
  }

  private static func stringSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("string"),
      "description": .string(description)
    ])
  }

  private static func boolSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("boolean"),
      "description": .string(description)
    ])
  }

  private static func integerSchema(
    _ description: String,
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
