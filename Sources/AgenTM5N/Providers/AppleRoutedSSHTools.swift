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
}

private struct RoutedSSHListHostsTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "ssh_list_hosts"
  let description = "List configured AgenTM5N SSH profiles. Returns only non-secret host metadata and whether credentials are configured."

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
  let description = "Run a non-interactive command on a configured SSH profile. AgenTM5N resolves linked Vault credentials internally. Never ask for or expose passwords, keys, passphrases, or secret IDs."

  @Generable
  struct Arguments {
    @Guide(description: "SSH profile name, hostname, or UUID")
    var host: String

    @Guide(description: "Remote shell command")
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
  let description = "Open a configured SSH profile in the visible AgenTM5N terminal. Linked Vault credentials are resolved internally."

  @Generable
  struct Arguments {
    @Guide(description: "SSH profile name, hostname, or UUID")
    var host: String

    @Guide(description: "Optional initial remote command; use an empty string for an interactive shell")
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
