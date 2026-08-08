import Foundation

public actor ToolResultCache {
  public static let shared = ToolResultCache()

  private struct Entry: Sendable {
    let result: ToolExecutionResult
    let expiresAt: Date
  }

  private var entries: [String: Entry] = [:]
  private let maximumEntries = 128

  public init() {}

  public func result(for call: ProviderToolCall) -> ToolExecutionResult? {
    purgeExpired()
    let key = cacheKey(call)
    guard let entry = entries[key], entry.expiresAt > Date() else {
      entries.removeValue(forKey: key)
      return nil
    }
    return entry.result
  }

  public func store(
    _ result: ToolExecutionResult,
    for call: ProviderToolCall,
    ttl: TimeInterval
  ) {
    guard result.success, ttl > 0 else { return }
    purgeExpired()
    if entries.count >= maximumEntries,
      let oldest = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key
    {
      entries.removeValue(forKey: oldest)
    }
    entries[cacheKey(call)] = Entry(
      result: result,
      expiresAt: Date().addingTimeInterval(ttl)
    )
  }

  public func invalidateAll() {
    entries.removeAll(keepingCapacity: true)
  }

  public nonisolated func ttl(for toolName: String) -> TimeInterval {
    switch toolName {
    case "system_info": 60,
      "ssh_list_hosts", "git_branches", "coreml_list_models", "workflow_list", "agent_list": 20,
      "git_status", "disk_info", "network_info", "process_list", "workspace_index_status": 8,
      "shortcuts_list", "secret_list", "app_version_info": 30,
      "list_directory", "glob_files", "search_text": 5
    default:
      0
    }
  }

  private func cacheKey(_ call: ProviderToolCall) -> String {
    let args = call.function.arguments.keys.sorted().map { key in
      "\(key)=\(call.function.arguments[key]?.compactDescription ?? "null")"
    }.joined(separator: "&")
    return "\(call.function.name)?\(args)"
  }

  private func purgeExpired() {
    let now = Date()
    entries = entries.filter { $0.value.expiresAt > now }
  }
}
