import Foundation

public enum AgentToolCapability: String, Codable, CaseIterable, Hashable, Sendable {
  case workspace
  case terminal
  case ssh
  case edge
  case browser
  case git
  case macPersonal
  case secrets
  case http
  case system
  case reminders
  case coreML
  case memory
  case knowledge
  case attachments
  case documents
  case agents
  case workflows
  case updates
}

public struct AgentToolCatalogEntry: Codable, Equatable, Sendable {
  public let name: String
  public let capability: AgentToolCapability
  public let risk: ToolRisk
  public let cacheable: Bool
  public let secretAware: Bool

  public init(
    name: String,
    capability: AgentToolCapability,
    risk: ToolRisk,
    cacheable: Bool = false,
    secretAware: Bool = false
  ) {
    self.name = name
    self.capability = capability
    self.risk = risk
    self.cacheable = cacheable
    self.secretAware = secretAware
  }
}

/// Single provider-neutral catalog for AgenTM5N tools.
///
/// Foundation Models still needs thin Swift `Tool` adapters, but capability,
/// risk, caching, and the Ollama/OpenAI-style definitions live here so newly
/// added tools do not silently become provider-specific.
public enum AgentToolRegistry {
  public static var allDefinitions: [ProviderToolDefinition] {
    unique(
      AgentRuntime.toolDefinitions
        + MacNativeAgentTools.definitions
        + MacNativeMutationAgentTools.definitions
        + RemindersAgentTools.definitions
        + CoreMLAgentTools.definitions
        + WorkspaceMemoryAgentTools.definitions
        + ConversationAttachmentAgentTools.definitions
        + KnowledgeLibraryAgentTools.definitions
        + UnifiedContextAgentTools.definitions
        + GeneratedDocumentAgentTools.definitions
        + PersistentAgentTools.definitions
        + PlatformExpansionAgentTools.definitions
        + EdgeAgentTools.definitions
        + BrowserAgentTools.definitions
        + BrowserBatchAgentTools.definitions
        + AgentDelegationTools.definitions
        + WorkflowAgentTools.definitions
        + SelfBuiltToolAgentTools.definitions
    )
  }

  public static var ollamaDefinitions: [ProviderToolDefinition] {
    allDefinitions
  }

  public static func definitions(
    capabilities: Set<AgentToolCapability>
  ) -> [ProviderToolDefinition] {
    let names = Set(
      catalog
        .filter { capabilities.contains($0.capability) }
        .map(\.name)
    ).union(
      capabilities.contains(.terminal)
        ? Set(SelfBuiltToolLibrary.shared.records.filter(\.isEnabled).map(\.name))
        : Set<String>()
    )
    return allDefinitions.filter { names.contains($0.function.name) }
  }

  public static let catalog: [AgentToolCatalogEntry] = [
    .init(name: "list_directory", capability: .workspace, risk: .read, cacheable: true),
    .init(name: "glob_files", capability: .workspace, risk: .read, cacheable: true),
    .init(name: "search_text", capability: .workspace, risk: .read, cacheable: true),
    .init(name: "read_file", capability: .workspace, risk: .read),
    .init(name: "apply_patch", capability: .workspace, risk: .write),
    .init(name: "write_file", capability: .workspace, risk: .write),
    .init(name: "run_command", capability: .terminal, risk: .execute),
    .init(name: "terminal_open", capability: .terminal, risk: .execute),

    .init(name: "ssh_list_hosts", capability: .ssh, risk: .read, cacheable: true, secretAware: true),
    .init(name: "ssh_run", capability: .ssh, risk: .execute, secretAware: true),
    .init(name: "ssh_open_terminal", capability: .ssh, risk: .execute, secretAware: true),
    .init(name: "ssh_upload", capability: .ssh, risk: .execute, secretAware: true),
    .init(name: "ssh_download", capability: .ssh, risk: .execute, secretAware: true),
    .init(name: "ssh_tail_log", capability: .ssh, risk: .execute, secretAware: true),
    .init(name: "ssh_run_batch", capability: .ssh, risk: .execute, secretAware: true),

    .init(name: "edge_list_nodes", capability: .edge, risk: .read, cacheable: true, secretAware: true),
    .init(name: "edge_list_directory", capability: .edge, risk: .read, secretAware: true),
    .init(name: "edge_read_file", capability: .edge, risk: .read, secretAware: true),
    .init(name: "edge_write_file", capability: .edge, risk: .write, secretAware: true),
    .init(name: "edge_control", capability: .edge, risk: .execute, secretAware: true),

    .init(name: "browser_session", capability: .browser, risk: .execute),
    .init(name: "browser_tabs", capability: .browser, risk: .read),
    .init(name: "browser_open", capability: .browser, risk: .execute),
    .init(name: "browser_read", capability: .browser, risk: .read),
    .init(name: "browser_action", capability: .browser, risk: .execute),
    .init(name: "browser_batch", capability: .browser, risk: .execute),

    .init(name: "git_status", capability: .git, risk: .read, cacheable: true),
    .init(name: "git_diff", capability: .git, risk: .read),
    .init(name: "git_branches", capability: .git, risk: .read, cacheable: true),
    .init(name: "git_checkout", capability: .git, risk: .write),
    .init(name: "git_commit", capability: .git, risk: .write),

    .init(name: "calendar_list_events", capability: .macPersonal, risk: .read),
    .init(name: "contacts_search", capability: .macPersonal, risk: .read),
    .init(name: "mail_list_recent", capability: .macPersonal, risk: .read),
    .init(name: "mail_read_message", capability: .macPersonal, risk: .read),
    .init(name: "calendar_create_event", capability: .macPersonal, risk: .write),
    .init(name: "calendar_update_event", capability: .macPersonal, risk: .write),
    .init(name: "calendar_delete_event", capability: .macPersonal, risk: .write),
    .init(name: "contacts_create", capability: .macPersonal, risk: .write),
    .init(name: "contacts_update", capability: .macPersonal, risk: .write),
    .init(name: "mail_create_draft", capability: .macPersonal, risk: .write),
    .init(name: "mail_send", capability: .macPersonal, risk: .write),
    .init(name: "mail_reply", capability: .macPersonal, risk: .write),

    .init(name: "secret_list", capability: .secrets, risk: .read, cacheable: true, secretAware: true),
    .init(name: "http_request", capability: .http, risk: .execute, secretAware: true),

    .init(name: "system_info", capability: .system, risk: .read, cacheable: true),
    .init(name: "process_list", capability: .system, risk: .read, cacheable: true),
    .init(name: "disk_info", capability: .system, risk: .read, cacheable: true),
    .init(name: "network_info", capability: .system, risk: .read, cacheable: true),
    .init(name: "clipboard_read", capability: .system, risk: .read),
    .init(name: "clipboard_write", capability: .system, risk: .write),
    .init(name: "notification_send", capability: .system, risk: .write),
    .init(name: "shortcuts_list", capability: .system, risk: .read, cacheable: true),
    .init(name: "shortcuts_run", capability: .system, risk: .execute),
    .init(name: "finder_reveal", capability: .system, risk: .execute),

    .init(name: "reminders_list", capability: .reminders, risk: .read),
    .init(name: "reminders_create", capability: .reminders, risk: .write),
    .init(name: "reminders_complete", capability: .reminders, risk: .write),

    .init(name: "coreml_list_models", capability: .coreML, risk: .read, cacheable: true),
    .init(name: "coreml_describe_model", capability: .coreML, risk: .read, cacheable: true),
    .init(name: "coreml_predict", capability: .coreML, risk: .execute),

    .init(name: "workspace_index_status", capability: .memory, risk: .read, cacheable: true),
    .init(name: "workspace_index_build", capability: .memory, risk: .write),
    .init(name: "workspace_semantic_search", capability: .memory, risk: .read),
    .init(name: "workspace_index_clear", capability: .memory, risk: .write),
    .init(name: "context_search", capability: .memory, risk: .read),
    .init(name: "context_read_source", capability: .memory, risk: .read),

    .init(name: "attachment_list", capability: .attachments, risk: .read, cacheable: true),
    .init(name: "attachment_describe", capability: .attachments, risk: .read),
    .init(name: "attachment_search", capability: .attachments, risk: .read),
    .init(name: "attachment_read_section", capability: .attachments, risk: .read),

    .init(name: "knowledge_list_collections", capability: .knowledge, risk: .read, cacheable: true),
    .init(name: "knowledge_list_documents", capability: .knowledge, risk: .read, cacheable: true),
    .init(name: "knowledge_search", capability: .knowledge, risk: .read),
    .init(name: "knowledge_read_source", capability: .knowledge, risk: .read),
    .init(name: "knowledge_import_document", capability: .knowledge, risk: .write),

    .init(name: "agent_list", capability: .agents, risk: .read, cacheable: true),
    .init(name: "agent_get", capability: .agents, risk: .read, cacheable: true),
    .init(name: "agent_create", capability: .agents, risk: .write),
    .init(name: "agent_update", capability: .agents, risk: .write),
    .init(name: "agent_delete", capability: .agents, risk: .write),
    .init(name: "agent_delegate", capability: .agents, risk: .execute),

    .init(name: "workflow_list", capability: .workflows, risk: .read, cacheable: true),
    .init(name: "workflow_create", capability: .workflows, risk: .write),
    .init(name: "workflow_delete", capability: .workflows, risk: .write),
    .init(name: "workflow_run", capability: .workflows, risk: .execute),

    .init(name: "toolsmith_list", capability: .terminal, risk: .read),
    .init(name: "toolsmith_get", capability: .terminal, risk: .read),
    .init(name: "toolsmith_create", capability: .terminal, risk: .write),
    .init(name: "toolsmith_set_enabled", capability: .terminal, risk: .write),
    .init(name: "toolsmith_delete", capability: .terminal, risk: .write),
    .init(name: "toolsmith_run", capability: .terminal, risk: .execute),

    .init(name: "document_generate", capability: .documents, risk: .write),
    .init(name: "document_list_generated", capability: .documents, risk: .read, cacheable: true),
    .init(name: "document_delete_generated", capability: .documents, risk: .write),

    .init(name: "app_version_info", capability: .updates, risk: .read, cacheable: true),
    .init(name: "app_check_update", capability: .updates, risk: .execute),
  ]

  public static func entry(named name: String) -> AgentToolCatalogEntry? {
    if let existing = catalog.first(where: { $0.name == name }) {
      return existing
    }
    if SelfBuiltToolAgentTools.isDynamicToolName(name) {
      return AgentToolCatalogEntry(
        name: name,
        capability: .terminal,
        risk: .execute,
        cacheable: false,
        secretAware: false
      )
    }
    return nil
  }

  public static func isAllowed(
    _ name: String,
    within capabilities: Set<AgentToolCapability>?
  ) -> Bool {
    guard let capabilities else { return true }
    guard let entry = entry(named: name) else { return false }
    return capabilities.contains(entry.capability)
  }

  public static func isRemoteOrExternal(_ name: String) -> Bool {
    if SelfBuiltToolAgentTools.managementNames.contains(name)
      || SelfBuiltToolAgentTools.isDynamicToolName(name)
    {
      return true
    }
    if name == "run_command"
      || name == "terminal_open"
      || name == "shortcuts_run"
    {
      return true
    }
    guard let capability = entry(named: name)?.capability else {
      return name == "app_check_update"
    }
    return capability == .ssh
      || capability == .edge
      || capability == .browser
      || capability == .http
      || name == "app_check_update"
  }

  private static func unique(
    _ definitions: [ProviderToolDefinition]
  ) -> [ProviderToolDefinition] {
    var seen: Set<String> = []
    return definitions.filter { definition in
      seen.insert(definition.function.name).inserted
    }
  }
}
