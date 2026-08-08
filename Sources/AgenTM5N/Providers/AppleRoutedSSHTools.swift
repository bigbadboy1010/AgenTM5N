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
    await routeSSH(
      bridge: bridge,
      name: name,
      arguments: [:]
    )
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
    var values: [String: JSONValue] = [
      "host": .string(arguments.host)
    ]
    if !arguments.command.isEmpty {
      values["command"] = .string(arguments.command)
    }
    return await routeSSH(
      bridge: bridge,
      name: name,
      arguments: values
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
