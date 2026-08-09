import FoundationModels

public extension AppleRoutedOperationalTools {
  static func makeWorkspaceReadTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    filtered(
      names: ["list_directory", "glob_files", "search_text", "read_file"],
      bridge: bridge
    )
  }

  static func makeWorkspaceEditTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    filtered(
      names: ["read_file", "apply_patch", "write_file"],
      bridge: bridge
    )
  }

  static func makeLocalCommandTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    filtered(names: ["run_command", "terminal_open"], bridge: bridge)
  }

  static func makeGitTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    filtered(
      names: ["git_status", "git_diff", "git_branches", "git_checkout", "git_commit"],
      bridge: bridge
    )
  }

  private static func filtered(
    names: Set<String>,
    bridge: AgentToolExecutionBridge
  ) -> [any Tool] {
    makeTools(bridge: bridge).filter { names.contains($0.name) }
  }
}
