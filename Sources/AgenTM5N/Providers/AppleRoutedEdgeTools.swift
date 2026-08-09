import Foundation
import FoundationModels

/// Focused Apple on-device Edge control pack.
///
/// These adapters expose provider-neutral `edge_*` names while execution still
/// uses the same hardened SSH/Vault backend as AgenTM5N SSH 2.0.
public enum AppleRoutedEdgeTools {
  public static func makeTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      AppleEdgeListNodesTool(bridge: bridge),
      AppleEdgeListDirectoryTool(bridge: bridge),
      AppleEdgeReadFileTool(bridge: bridge),
      AppleEdgeWriteFileTool(bridge: bridge),
      AppleEdgeControlTool(bridge: bridge),
    ]
  }
}

private struct AppleEdgeListNodesTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "edge_list_nodes"
  let description = "List Edge-capable nodes from saved AgenTM5N SSH profiles without exposing credentials."

  @Generable
  struct Arguments {
    @Guide(description: "Optional. Omit this value or use all.")
    var query: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    await routeEdge(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleEdgeListDirectoryTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "edge_list_directory"
  let description = "List a bounded remote Edge directory tree, including /data/edge."

  @Generable
  struct Arguments {
    @Guide(description: "Saved SSH profile name, hostname, or UUID")
    var host: String

    @Guide(description: "Absolute remote directory path")
    var path: String

    @Guide(description: "Optional depth from 1 to 4. Defaults to 2.")
    var depth: Int? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "host": .string(arguments.host),
      "path": .string(arguments.path),
    ]
    if let depth = arguments.depth { values["depth"] = .number(Double(depth)) }
    return await routeEdge(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleEdgeReadFileTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "edge_read_file"
  let description = "Read bounded UTF-8/text content from an absolute file path on an Edge node."

  @Generable
  struct Arguments {
    @Guide(description: "Saved SSH profile name, hostname, or UUID")
    var host: String

    @Guide(description: "Absolute remote file path")
    var path: String

    @Guide(description: "Optional maximum bytes from 1 to 524288. Defaults to 65536.")
    var maxBytes: Int? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "host": .string(arguments.host),
      "path": .string(arguments.path),
    ]
    if let maxBytes = arguments.maxBytes {
      values["max_bytes"] = .number(Double(maxBytes))
    }
    return await routeEdge(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleEdgeWriteFileTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "edge_write_file"
  let description = "Atomically write UTF-8 text to an absolute file path on an Edge node. Important existing files are backed up by default."

  @Generable
  struct Arguments {
    @Guide(description: "Saved SSH profile name, hostname, or UUID")
    var host: String

    @Guide(description: "Absolute remote destination path")
    var path: String

    @Guide(description: "Complete UTF-8 file content, maximum 524288 bytes")
    var content: String

    @Guide(description: "Optional. Create missing parent directories. Defaults to false.")
    var createParent: Bool? = nil

    @Guide(description: "Optional. Back up an existing target before replacement. Defaults to true.")
    var backup: Bool? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "host": .string(arguments.host),
      "path": .string(arguments.path),
      "content": .string(arguments.content),
    ]
    if let createParent = arguments.createParent {
      values["create_parent"] = .bool(createParent)
    }
    if let backup = arguments.backup {
      values["backup"] = .bool(backup)
    }
    return await routeEdge(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleEdgeControlTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "edge_control"
  let description = "Inspect or control an Edge node. Operations: status, run, container, service, tail. Container actions: status/start/stop/restart/logs. Service actions: status/start/stop/restart."

  @Generable
  struct Arguments {
    @Guide(description: "Saved SSH profile name, hostname, or UUID")
    var host: String

    @Guide(description: "status, run, container, service, or tail")
    var operation: String

    @Guide(description: "Optional remote shell command for operation=run")
    var command: String? = nil

    @Guide(description: "Optional container or systemd service name")
    var target: String? = nil

    @Guide(description: "Optional action for container/service")
    var action: String? = nil

    @Guide(description: "Optional absolute remote log path for operation=tail")
    var path: String? = nil

    @Guide(description: "Optional log lines from 1 to 2000. Defaults to 200.")
    var lines: Int? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "host": .string(arguments.host),
      "operation": .string(arguments.operation),
    ]
    if let command = normalizedEdge(arguments.command, preserveWhitespace: true) {
      values["command"] = .string(command)
    }
    if let target = normalizedEdge(arguments.target) { values["target"] = .string(target) }
    if let action = normalizedEdge(arguments.action) { values["action"] = .string(action) }
    if let path = normalizedEdge(arguments.path) { values["path"] = .string(path) }
    if let lines = arguments.lines { values["lines"] = .number(Double(lines)) }
    return await routeEdge(bridge: bridge, name: name, arguments: values)
  }
}

private func normalizedEdge(
  _ value: String?,
  preserveWhitespace: Bool = false
) -> String? {
  guard let value else { return nil }
  if preserveWhitespace { return value.isEmpty ? nil : value }
  let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
  return normalized.isEmpty ? nil : normalized
}

private func routeEdge(
  bridge: AgentToolExecutionBridge,
  name: String,
  arguments: [String: JSONValue]
) async -> String {
  await bridge.execute(
    ProviderToolCall(function: .init(name: name, arguments: arguments))
  )
}
