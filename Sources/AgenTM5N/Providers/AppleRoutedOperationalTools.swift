import Foundation
import FoundationModels

public enum AppleRoutedOperationalTools {
  public static func makeTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      RoutedListDirectoryTool(bridge: bridge),
      RoutedGlobFilesTool(bridge: bridge),
      RoutedSearchTextTool(bridge: bridge),
      RoutedReadFileTool(bridge: bridge),
      RoutedApplyPatchTool(bridge: bridge),
      RoutedWriteFileTool(bridge: bridge),
      RoutedRunCommandTool(bridge: bridge),
      RoutedTerminalOpenTool(bridge: bridge),
      RoutedSSHListHostsTool(bridge: bridge),
      RoutedSSHRunTool(bridge: bridge),
      RoutedSSHOpenTerminalTool(bridge: bridge),
      RoutedGitStatusTool(bridge: bridge),
      RoutedGitDiffTool(bridge: bridge),
      RoutedGitBranchesTool(bridge: bridge),
      RoutedGitCheckoutTool(bridge: bridge),
      RoutedGitCommitTool(bridge: bridge),
    ]
  }
}

private struct RoutedListDirectoryTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "list_directory"
  let description = "List files and directories in the configured AgenTM5N workspace. Use an empty path for the workspace root."

  @Generable
  struct Arguments {
    @Guide(description: "Relative or absolute directory path; empty string means workspace root")
    var path: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routeOperational(
      bridge: bridge,
      name: name,
      arguments: arguments.path.isEmpty ? [:] : ["path": .string(arguments.path)]
    )
  }
}

private struct RoutedGlobFilesTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "glob_files"
  let description = "Find workspace files using a glob pattern such as **/*.swift, *.yml or Sources/**."

  @Generable
  struct Arguments {
    @Guide(description: "Glob pattern")
    var pattern: String

    @Guide(description: "Optional path below the workspace; empty string means workspace root")
    var path: String

    @Guide(description: "Whether hidden files and directories should be included")
    var includeHidden: Bool
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "pattern": .string(arguments.pattern),
      "include_hidden": .bool(arguments.includeHidden),
    ]
    if !arguments.path.isEmpty { values["path"] = .string(arguments.path) }
    return await routeOperational(bridge: bridge, name: name, arguments: values)
  }
}

private struct RoutedSearchTextTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "search_text"
  let description = "Search UTF-8 workspace files and return matching relative paths, lines, columns and bounded previews."

  @Generable
  struct Arguments {
    @Guide(description: "Single-line text fragment to search for")
    var query: String

    @Guide(description: "Optional path below the workspace; empty string means workspace root")
    var path: String

    @Guide(description: "Optional glob filter such as *.swift; empty string means no filter")
    var glob: String

    @Guide(description: "Use case-sensitive matching")
    var caseSensitive: Bool

    @Guide(description: "Include hidden files and directories")
    var includeHidden: Bool
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "query": .string(arguments.query),
      "case_sensitive": .bool(arguments.caseSensitive),
      "include_hidden": .bool(arguments.includeHidden),
    ]
    if !arguments.path.isEmpty { values["path"] = .string(arguments.path) }
    if !arguments.glob.isEmpty { values["glob"] = .string(arguments.glob) }
    return await routeOperational(bridge: bridge, name: name, arguments: values)
  }
}

private struct RoutedReadFileTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "read_file"
  let description = "Read one UTF-8 text file from the AgenTM5N workspace."

  @Generable
  struct Arguments {
    @Guide(description: "Relative or absolute file path")
    var path: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routeOperational(
      bridge: bridge,
      name: name,
      arguments: ["path": .string(arguments.path)]
    )
  }
}

private struct RoutedApplyPatchTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "apply_patch"
  let description = "Replace exactly one known text block in an existing workspace file. Read the file first."

  @Generable
  struct Arguments {
    @Guide(description: "Target file path")
    var path: String

    @Guide(description: "Exact existing text that must occur exactly once")
    var oldText: String

    @Guide(description: "Replacement text; may be empty to remove the old text")
    var newText: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routeOperational(
      bridge: bridge,
      name: name,
      arguments: [
        "path": .string(arguments.path),
        "old_text": .string(arguments.oldText),
        "new_text": .string(arguments.newText),
      ]
    )
  }
}

private struct RoutedWriteFileTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "write_file"
  let description = "Create or replace a UTF-8 text file in the configured workspace. Prefer apply_patch for existing files."

  @Generable
  struct Arguments {
    @Guide(description: "Destination file path")
    var path: String

    @Guide(description: "Complete UTF-8 file content")
    var content: String

    @Guide(description: "Create missing parent directories")
    var createDirectories: Bool
  }

  func call(arguments: Arguments) async throws -> String {
    await routeOperational(
      bridge: bridge,
      name: name,
      arguments: [
        "path": .string(arguments.path),
        "content": .string(arguments.content),
        "create_directories": .bool(arguments.createDirectories),
      ]
    )
  }
}

private struct RoutedRunCommandTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "run_command"
  let description = "Run a non-interactive local zsh command in the configured AgenTM5N workspace and return stdout, stderr and exit status."

  @Generable
  struct Arguments {
    @Guide(description: "Local shell command")
    var command: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routeOperational(
      bridge: bridge,
      name: name,
      arguments: ["command": .string(arguments.command)]
    )
  }
}

private struct RoutedTerminalOpenTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "terminal_open"
  let description = "Open the visible AgenTM5N local terminal, optionally with an initial command."

  @Generable
  struct Arguments {
    @Guide(description: "Optional initial command; empty string means none")
    var command: String

    @Guide(description: "Optional terminal title; empty string uses the default")
    var title: String
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [:]
    if !arguments.command.isEmpty { values["command"] = .string(arguments.command) }
    if !arguments.title.isEmpty { values["title"] = .string(arguments.title) }
    return await routeOperational(bridge: bridge, name: name, arguments: values)
  }
}

private struct RoutedSSHListHostsTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "ssh_list_hosts"
  let description = "List configured AgenTM5N SSH profiles. Returns host metadata and whether credentials are configured, but never passwords, private keys, passphrases or secret identifiers."

  @Generable
  struct Arguments {
    @Guide(description: "Use the literal value all")
    var query: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routeOperational(bridge: bridge, name: name, arguments: [:])
  }
}

private struct RoutedSSHRunTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "ssh_run"
  let description = "Execute a non-interactive command on a configured AgenTM5N SSH host. AgenTM5N resolves the profile's password/private-key/passphrase secrets internally; never ask the user to reveal those secret values."

  @Generable
  struct Arguments {
    @Guide(description: "Configured SSH profile name, hostname or UUID")
    var host: String

    @Guide(description: "Remote shell command to execute")
    var command: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routeOperational(
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
  let description = "Open a configured SSH host in the visible AgenTM5N terminal. AgenTM5N resolves linked Vault credentials internally."

  @Generable
  struct Arguments {
    @Guide(description: "Configured SSH profile name, hostname or UUID")
    var host: String

    @Guide(description: "Optional remote command to start; empty string means interactive shell")
    var command: String
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = ["host": .string(arguments.host)]
    if !arguments.command.isEmpty { values["command"] = .string(arguments.command) }
    return await routeOperational(bridge: bridge, name: name, arguments: values)
  }
}

private struct RoutedGitStatusTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "git_status"
  let description = "Return concise Git status for the configured workspace."

  @Generable
  struct Arguments {
    @Guide(description: "Use the literal value current")
    var query: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routeOperational(bridge: bridge, name: name, arguments: [:])
  }
}

private struct RoutedGitDiffTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "git_diff"
  let description = "Return the Git diff for the configured workspace."

  @Generable
  struct Arguments {
    @Guide(description: "Return staged diff when true; working-tree diff when false")
    var staged: Bool
  }

  func call(arguments: Arguments) async throws -> String {
    await routeOperational(
      bridge: bridge,
      name: name,
      arguments: ["staged": .bool(arguments.staged)]
    )
  }
}

private struct RoutedGitBranchesTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "git_branches"
  let description = "Show the current Git branch and local branch inventory for the configured workspace."

  @Generable
  struct Arguments {
    @Guide(description: "Use the literal value local")
    var query: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routeOperational(bridge: bridge, name: name, arguments: [:])
  }
}

private struct RoutedGitCheckoutTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "git_checkout"
  let description = "Switch to or create a local Git branch. The existing AgenTM5N runtime blocks the operation when the working tree is dirty."

  @Generable
  struct Arguments {
    @Guide(description: "Valid local Git branch name")
    var branch: String

    @Guide(description: "Create the branch from current HEAD before switching")
    var create: Bool
  }

  func call(arguments: Arguments) async throws -> String {
    await routeOperational(
      bridge: bridge,
      name: name,
      arguments: [
        "branch": .string(arguments.branch),
        "create": .bool(arguments.create),
      ]
    )
  }
}

private struct RoutedGitCommitTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "git_commit"
  let description = "Stage only explicitly listed workspace paths and create a local Git commit. This never pushes."

  @Generable
  struct Arguments {
    @Guide(description: "Commit message")
    var message: String

    @Guide(description: "Concrete relative workspace paths to stage; do not use dot")
    var paths: [String]
  }

  func call(arguments: Arguments) async throws -> String {
    await routeOperational(
      bridge: bridge,
      name: name,
      arguments: [
        "message": .string(arguments.message),
        "paths": .array(arguments.paths.map(JSONValue.string)),
      ]
    )
  }
}

private func routeOperational(
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
