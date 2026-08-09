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
    @Guide(description: "Use all") var query: String
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
    @Guide(description: "Saved SSH profile name, hostname, or UUID") var host: String
    @Guide(description: "Absolute remote directory path") var path: String
    @Guide(description: "Depth from 1 to 4") var depth: Int
  }

  func call(arguments: Arguments) async throws -> String {
    await routeEdge(
      bridge: bridge,
      name: name,
      arguments: [
        "host": .string(arguments.host),
        "path": .string(arguments.path),
        "depth": .number(Double(arguments.depth)),
      ]
    )
  }
}

private struct AppleEdgeReadFileTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "edge_read_file"
  let description = "Read bounded UTF-8/text content from an absolute file path on an Edge node."

  @Generable
  struct Arguments {
    @Guide(description: "Saved SSH profile name, hostname, or UUID") var host: String
    @Guide(description: "Absolute remote file path") var path: String
    @Guide(description: "Maximum bytes from 1 to 524288") var maxBytes: Int
  }

  func call(arguments: Arguments) async throws -> String {
    await routeEdge(
      bridge: bridge,
      name: name,
      arguments: [
        "host": .string(arguments.host),
        "path": .string(arguments.path),
        "max_bytes": .number(Double(arguments.maxBytes)),
      ]
    )
  }
}

private struct AppleEdgeWriteFileTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "edge_write_file"
  let description = "Atomically write UTF-8 text to an absolute file path on an Edge node. Important existing files are backed up by default."

  @Generable
  struct Arguments {
    @Guide(description: "Saved SSH profile name, hostname, or UUID") var host: String
    @Guide(description: "Absolute remote destination path") var path: String
    @Guide(description: "Complete UTF-8 file content, maximum 524288 bytes") var content: String
    @Guide(description: "Create missing parent directories") var createParent: Bool
    @Guide(description: "Back up an existing target before replacement") var backup: Bool
  }

  func call(arguments: Arguments) async throws -> String {
    await routeEdge(
      bridge: bridge,
      name: name,
      arguments: [
        "host": .string(arguments.host),
        "path": .string(arguments.path),
        "content": .string(arguments.content),
        "create_parent": .bool(arguments.createParent),
        "backup": .bool(arguments.backup),
      ]
    )
  }
}

private struct AppleEdgeControlTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "edge_control"
  let description = "Inspect or control an Edge node. Operations: status, run, container, service, tail. Container actions: status/start/stop/restart/logs. Service actions: status/start/stop/restart."

  @Generable
  struct Arguments {
    @Guide(description: "Saved SSH profile name, hostname, or UUID") var host: String
    @Guide(description: "status, run, container, service, or tail") var operation: String
    @Guide(description: "Remote shell command for operation=run, otherwise empty") var command: String
    @Guide(description: "Container or systemd service name, otherwise empty") var target: String
    @Guide(description: "Action for container/service, otherwise empty") var action: String
    @Guide(description: "Absolute remote log path for operation=tail, otherwise empty") var path: String
    @Guide(description: "Log lines from 1 to 2000") var lines: Int
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "host": .string(arguments.host),
      "operation": .string(arguments.operation),
      "lines": .number(Double(arguments.lines)),
    ]
    if !arguments.command.isEmpty { values["command"] = .string(arguments.command) }
    if !arguments.target.isEmpty { values["target"] = .string(arguments.target) }
    if !arguments.action.isEmpty { values["action"] = .string(arguments.action) }
    if !arguments.path.isEmpty { values["path"] = .string(arguments.path) }
    return await routeEdge(bridge: bridge, name: name, arguments: values)
  }
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
