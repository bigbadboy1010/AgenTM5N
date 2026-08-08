import Foundation
import FoundationModels

public enum AppleRoutedSSHTools {
  public static func makeTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      RoutedSSHListHostsTool(bridge: bridge),
      RoutedSSHRunTool(bridge: bridge),
      RoutedSSHOpenTerminalTool(bridge: bridge),
    ]
  }

  public static func makeListHostsTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [RoutedSSHListHostsTool(bridge: bridge)]
  }

  public static func makeRunTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [RoutedSSHRunTool(bridge: bridge)]
  }

  public static func makeOpenTerminalTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [RoutedSSHOpenTerminalTool(bridge: bridge)]
  }

  public static func makeUploadTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [RoutedSSHUploadTool(bridge: bridge)]
  }

  public static func makeDownloadTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [RoutedSSHDownloadTool(bridge: bridge)]
  }

  public static func makeTailTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [RoutedSSHTailLogTool(bridge: bridge)]
  }

  public static func makeBatchTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [RoutedSSHBatchTool(bridge: bridge)]
  }
}

private struct RoutedSSHListHostsTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "ssh_list_hosts"
  let description = "List saved AgenTM5N SSH profiles without secret values."

  @Generable
  struct Arguments {
    @Guide(description: "Use all")
    var query: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routeSSH(bridge: bridge, name: name, arguments: [:])
  }
}

private struct RoutedSSHRunTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "ssh_run"
  let description = "Run one remote shell command string through a saved SSH profile. The command string may contain multiple requested commands separated by semicolons or newlines; preserve all commands the user asked to run and keep their order. AgenTM5N resolves Vault credentials internally."

  @Generable
  struct Arguments {
    @Guide(description: "Saved SSH profile name, hostname, or UUID")
    var host: String

    @Guide(description: "Complete remote shell command string. When the user requested multiple commands, include every command in this single string, separated by semicolons or newlines, for example: whoami; hostname; uname -a")
    var command: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routeSSH(
      bridge: bridge,
      name: name,
      arguments: [
        "host": .string(arguments.host),
        "command": .string(arguments.command),
      ]
    )
  }
}

private struct RoutedSSHOpenTerminalTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "ssh_open_terminal"
  let description = "Open one saved SSH profile in the visible AgenTM5N terminal. Vault credentials stay internal."

  @Generable
  struct Arguments {
    @Guide(description: "Saved SSH profile name, hostname, or UUID")
    var host: String

    @Guide(description: "Initial remote command, or empty for an interactive shell")
    var command: String
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = ["host": .string(arguments.host)]
    if !arguments.command.isEmpty { values["command"] = .string(arguments.command) }
    return await routeSSH(bridge: bridge, name: name, arguments: values)
  }
}

private struct RoutedSSHUploadTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "ssh_upload"
  let description = "Upload one local workspace file to a saved SSH profile with SCP. Vault credentials stay internal."

  @Generable
  struct Arguments {
    @Guide(description: "Saved SSH profile name, hostname, or UUID") var host: String
    @Guide(description: "Local workspace file path") var localPath: String
    @Guide(description: "Remote destination path using safe path characters") var remotePath: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routeSSH(
      bridge: bridge,
      name: name,
      arguments: [
        "host": .string(arguments.host),
        "local_path": .string(arguments.localPath),
        "remote_path": .string(arguments.remotePath),
      ]
    )
  }
}

private struct RoutedSSHDownloadTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "ssh_download"
  let description = "Download one remote file from a saved SSH profile into the local workspace with SCP. Vault credentials stay internal."

  @Generable
  struct Arguments {
    @Guide(description: "Saved SSH profile name, hostname, or UUID") var host: String
    @Guide(description: "Remote source path using safe path characters") var remotePath: String
    @Guide(description: "Local workspace destination path") var localPath: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routeSSH(
      bridge: bridge,
      name: name,
      arguments: [
        "host": .string(arguments.host),
        "remote_path": .string(arguments.remotePath),
        "local_path": .string(arguments.localPath),
      ]
    )
  }
}

private struct RoutedSSHTailLogTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "ssh_tail_log"
  let description = "Read the last bounded lines of one remote log file through a saved SSH profile."

  @Generable
  struct Arguments {
    @Guide(description: "Saved SSH profile name, hostname, or UUID") var host: String
    @Guide(description: "Remote log path") var path: String
    @Guide(description: "Number of lines from 1 to 2000") var lines: Int
  }

  func call(arguments: Arguments) async throws -> String {
    await routeSSH(
      bridge: bridge,
      name: name,
      arguments: [
        "host": .string(arguments.host),
        "path": .string(arguments.path),
        "lines": .number(Double(arguments.lines)),
      ]
    )
  }
}

private struct RoutedSSHBatchTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "ssh_run_batch"
  let description = "Run an ordered batch of remote commands through one saved SSH profile and one SSH connection. Use this for server health checks instead of several separate ssh_run calls."

  @Generable
  struct Arguments {
    @Guide(description: "Saved SSH profile name, hostname, or UUID") var host: String
    @Guide(description: "Ordered remote commands, one command per line") var commands: String
  }

  func call(arguments: Arguments) async throws -> String {
    let commands = arguments.commands
      .split(whereSeparator: { $0.isNewline })
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return await routeSSH(
      bridge: bridge,
      name: name,
      arguments: [
        "host": .string(arguments.host),
        "commands": .array(commands.map(JSONValue.string)),
      ]
    )
  }
}

private func routeSSH(
  bridge: AgentToolExecutionBridge,
  name: String,
  arguments: [String: JSONValue]
) async -> String {
  await bridge.execute(
    ProviderToolCall(
      function: ProviderToolCall.Function(
        name: name,
        arguments: arguments
      )
    )
  )
}
