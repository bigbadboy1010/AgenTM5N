import Foundation
import FoundationModels

public enum AppleRoutedPlatformExpansionTools {
  public static func makeHTTPTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      AppleSecretListTool(bridge: bridge),
      AppleHTTPRequestTool(bridge: bridge),
    ]
  }

  public static func makeSystemTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      AppleSystemInfoTool(bridge: bridge),
      AppleProcessListTool(bridge: bridge),
      AppleDiskInfoTool(bridge: bridge),
      AppleNetworkInfoTool(bridge: bridge),
    ]
  }

  public static func makeMacUtilityTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      AppleClipboardReadTool(bridge: bridge),
      AppleClipboardWriteTool(bridge: bridge),
      AppleNotificationTool(bridge: bridge),
      AppleShortcutsListTool(bridge: bridge),
      AppleShortcutsRunTool(bridge: bridge),
    ]
  }

  public static func makeReminderTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      AppleRemindersListTool(bridge: bridge),
      AppleRemindersCreateTool(bridge: bridge),
      AppleRemindersCompleteTool(bridge: bridge),
    ]
  }

  public static func makeDelegationTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [AppleAgentDelegateTool(bridge: bridge)]
  }

  public static func makeWorkflowTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      AppleWorkflowListTool(bridge: bridge),
      AppleWorkflowCreateTool(bridge: bridge),
      AppleWorkflowDeleteTool(bridge: bridge),
      AppleWorkflowRunTool(bridge: bridge),
    ]
  }

  public static func makeUpdateTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      AppleAppVersionTool(bridge: bridge),
      AppleUpdateCheckTool(bridge: bridge),
    ]
  }
}

private struct AppleSecretListTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "secret_list"
  let description = "List unlocked AgenTM5N Vault secret labels and kinds. Never returns secret values or secret IDs."

  @Generable
  struct Arguments {
    @Guide(description: "Optional. Omit this value or use all.")
    var query: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    await routePlatform(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleHTTPRequestTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "http_request"
  let description = "Perform one HTTP(S) request. Use secret_ref only as an exact Vault label. AgenTM5N injects the secret natively; never ask for or expose its value."

  @Generable
  struct Arguments {
    @Guide(description: "GET, HEAD, POST, PUT, PATCH, DELETE, or OPTIONS")
    var method: String

    @Guide(description: "Absolute http or https URL without embedded credentials")
    var url: String

    @Guide(description: "Optional JSON object of non-secret string headers")
    var headersJson: String? = nil

    @Guide(description: "Optional request body")
    var body: String? = nil

    @Guide(description: "Optional exact Vault secret label")
    var secretRef: String? = nil

    @Guide(description: "Optional secret usage: bearer, basic, or header")
    var secretUsage: String? = nil

    @Guide(description: "Optional header name when secret_usage is header")
    var secretHeader: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "method": .string(arguments.method),
      "url": .string(arguments.url),
    ]

    if let body = normalizedOptional(arguments.body, preserveWhitespace: true) {
      values["body"] = .string(body)
    }
    if let secretRef = normalizedOptional(arguments.secretRef) {
      values["secret_ref"] = .string(secretRef)
    }
    if let secretUsage = normalizedOptional(arguments.secretUsage) {
      values["secret_usage"] = .string(secretUsage)
    }
    if let secretHeader = normalizedOptional(arguments.secretHeader) {
      values["secret_header"] = .string(secretHeader)
    }
    if let headersJSON = normalizedOptional(arguments.headersJson) {
      guard let headers = parseStringMap(headersJSON) else {
        return "TOOL_ERROR: headersJson must be a JSON object containing string values only."
      }
      if !headers.isEmpty {
        values["headers"] = .object(headers.mapValues(JSONValue.string))
      }
    }
    return await routePlatform(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleSystemInfoTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "system_info"
  let description = "Read local Mac hardware, OS, architecture, uptime, and memory metadata."

  @Generable
  struct Arguments {
    @Guide(description: "Optional. Omit this value or use current.")
    var query: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    await routePlatform(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleProcessListTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "process_list"
  let description = "Read a bounded local process list sorted by CPU usage."

  @Generable
  struct Arguments {
    @Guide(description: "Optional maximum process count from 1 to 100. Defaults to 25.")
    var limit: Int? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [:]
    if let limit = arguments.limit {
      values["limit"] = .number(Double(limit))
    }
    return await routePlatform(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleDiskInfoTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "disk_info"
  let description = "Read local filesystem size and free-space information."

  @Generable
  struct Arguments {
    @Guide(description: "Optional. Omit this value or use current.")
    var query: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    await routePlatform(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleNetworkInfoTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "network_info"
  let description = "Read local network-interface and default-route information."

  @Generable
  struct Arguments {
    @Guide(description: "Optional. Omit this value or use current.")
    var query: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    await routePlatform(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleClipboardReadTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "clipboard_read"
  let description = "Read plain text from the macOS clipboard when explicitly relevant to the user's request."

  @Generable
  struct Arguments {
    @Guide(description: "Optional. Omit this value or use current.")
    var query: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    await routePlatform(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleClipboardWriteTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "clipboard_write"
  let description = "Replace the macOS clipboard with plain text."

  @Generable
  struct Arguments {
    @Guide(description: "Text to copy")
    var text: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routePlatform(
      bridge: bridge,
      name: name,
      arguments: ["text": .string(arguments.text)]
    )
  }
}

private struct AppleNotificationTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "notification_send"
  let description = "Display one local macOS notification."

  @Generable
  struct Arguments {
    @Guide(description: "Notification title")
    var title: String

    @Guide(description: "Notification message")
    var message: String

    @Guide(description: "Optional subtitle")
    var subtitle: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "title": .string(arguments.title),
      "message": .string(arguments.message),
    ]
    if let subtitle = normalizedOptional(arguments.subtitle) {
      values["subtitle"] = .string(subtitle)
    }
    return await routePlatform(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleShortcutsListTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "shortcuts_list"
  let description = "List macOS Shortcuts available to the current user."

  @Generable
  struct Arguments {
    @Guide(description: "Optional. Omit this value or use all.")
    var query: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    await routePlatform(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleShortcutsRunTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "shortcuts_run"
  let description = "Run one named macOS Shortcut through AgenTM5N approval."

  @Generable
  struct Arguments {
    @Guide(description: "Exact Shortcut name")
    var shortcutName: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routePlatform(
      bridge: bridge,
      name: name,
      arguments: ["name": .string(arguments.shortcutName)]
    )
  }
}

private struct AppleRemindersListTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "reminders_list"
  let description = "List incomplete macOS Reminders."

  @Generable
  struct Arguments {
    @Guide(description: "Optional maximum reminders from 1 to 100. Defaults to 25.")
    var limit: Int? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [:]
    if let limit = arguments.limit {
      values["limit"] = .number(Double(limit))
    }
    return await routePlatform(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleRemindersCreateTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "reminders_create"
  let description = "Create one macOS Reminder. AgenTM5N applies personal-data confirmation policy."

  @Generable
  struct Arguments {
    @Guide(description: "Reminder title")
    var title: String

    @Guide(description: "Optional notes")
    var notes: String? = nil

    @Guide(description: "Optional ISO-8601 due date/time")
    var dueDate: String? = nil

    @Guide(description: "Optional exact Reminders list name")
    var listName: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = ["title": .string(arguments.title)]
    if let notes = normalizedOptional(arguments.notes, preserveWhitespace: true) {
      values["notes"] = .string(notes)
    }
    if let dueDate = normalizedOptional(arguments.dueDate) {
      values["due_date"] = .string(dueDate)
    }
    if let listName = normalizedOptional(arguments.listName) {
      values["list"] = .string(listName)
    }
    return await routePlatform(bridge: bridge, name: name, arguments: values)
  }
}

private struct AppleRemindersCompleteTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "reminders_complete"
  let description = "Mark one incomplete macOS Reminder complete by exact title or identifier."

  @Generable
  struct Arguments {
    @Guide(description: "Exact reminder title or identifier")
    var reminder: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routePlatform(
      bridge: bridge,
      name: name,
      arguments: ["reminder": .string(arguments.reminder)]
    )
  }
}

private struct AppleAgentDelegateTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "agent_delegate"
  let description = "Delegate a bounded subtask to one saved AgenTM5N specialist agent. The delegated agent never receives Vault secret values directly."

  @Generable
  struct Arguments {
    @Guide(description: "Exact saved agent name or UUID")
    var agent: String

    @Guide(description: "Concrete bounded specialist task")
    var task: String

    @Guide(description: "Optional. Allow AgenTM5N tools for the delegate. Defaults to true.")
    var allowTools: Bool? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "agent": .string(arguments.agent),
      "task": .string(arguments.task),
    ]
    if let allowTools = arguments.allowTools {
      values["allow_tools"] = .bool(allowTools)
    }
    return await routePlatform(
      bridge: bridge,
      name: name,
      arguments: values
    )
  }
}

private struct AppleWorkflowListTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "workflow_list"
  let description = "List persistent AgenTM5N workflows without secret values."

  @Generable
  struct Arguments {
    @Guide(description: "Optional. Omit this value or use all.")
    var query: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    await routePlatform(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleWorkflowCreateTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "workflow_create"
  let description = "Create a reusable AgenTM5N workflow. Steps are JSON objects with tool and arguments. Store secret_ref labels only, never secret values."

  @Generable
  struct Arguments {
    @Guide(description: "Workflow name")
    var workflowName: String

    @Guide(description: "Workflow purpose")
    var purpose: String

    @Guide(description: "JSON array of {tool,arguments} objects")
    var stepsJson: String
  }

  func call(arguments: Arguments) async throws -> String {
    guard let steps = parseJSONArray(arguments.stepsJson) else {
      return "TOOL_ERROR: Invalid workflow steps JSON."
    }
    return await routePlatform(
      bridge: bridge,
      name: name,
      arguments: [
        "name": .string(arguments.workflowName),
        "purpose": .string(arguments.purpose),
        "steps": .array(steps),
      ]
    )
  }
}

private struct AppleWorkflowDeleteTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "workflow_delete"
  let description = "Delete one saved AgenTM5N workflow by exact name or UUID."

  @Generable
  struct Arguments {
    @Guide(description: "Exact workflow name or UUID")
    var workflow: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routePlatform(
      bridge: bridge,
      name: name,
      arguments: ["workflow": .string(arguments.workflow)]
    )
  }
}

private struct AppleWorkflowRunTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "workflow_run"
  let description = "Run one saved AgenTM5N workflow after central execution approval."

  @Generable
  struct Arguments {
    @Guide(description: "Exact workflow name or UUID")
    var workflow: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routePlatform(
      bridge: bridge,
      name: name,
      arguments: ["workflow": .string(arguments.workflow)]
    )
  }
}

private struct AppleAppVersionTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "app_version_info"
  let description = "Read current AgenTM5N version and build metadata."

  @Generable
  struct Arguments {
    @Guide(description: "Optional. Omit this value or use current.")
    var query: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    await routePlatform(bridge: bridge, name: name, arguments: [:])
  }
}

private struct AppleUpdateCheckTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "app_check_update"
  let description = "Check an HTTPS AgenTM5N update manifest. Never installs automatically."

  @Generable
  struct Arguments {
    @Guide(description: "HTTPS JSON manifest URL")
    var manifestURL: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routePlatform(
      bridge: bridge,
      name: name,
      arguments: ["manifest_url": .string(arguments.manifestURL)]
    )
  }
}

private func routePlatform(
  bridge: AgentToolExecutionBridge,
  name: String,
  arguments: [String: JSONValue]
) async -> String {
  await bridge.execute(
    ProviderToolCall(
      function: .init(name: name, arguments: arguments)
    )
  )
}

private func normalizedOptional(
  _ value: String?,
  preserveWhitespace: Bool = false
) -> String? {
  guard let value else { return nil }
  if preserveWhitespace {
    return value.isEmpty ? nil : value
  }
  let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
  return normalized.isEmpty ? nil : normalized
}

private func parseStringMap(_ text: String) -> [String: String]? {
  let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !normalized.isEmpty else { return [:] }
  guard let data = normalized.data(using: .utf8),
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else { return nil }
  var result: [String: String] = [:]
  for (key, value) in object {
    guard let string = value as? String else { return nil }
    result[key] = string
  }
  return result
}

private func parseJSONArray(_ text: String) -> [JSONValue]? {
  guard let data = text.data(using: .utf8),
    let raw = try? JSONSerialization.jsonObject(with: data),
    let array = raw as? [Any]
  else { return nil }
  let converted = array.compactMap(jsonValue)
  return converted.count == array.count ? converted : nil
}

private func jsonValue(_ value: Any) -> JSONValue? {
  switch value {
  case let string as String: return .string(string)
  case let bool as Bool: return .bool(bool)
  case let number as NSNumber: return .number(number.doubleValue)
  case let object as [String: Any]:
    var result: [String: JSONValue] = [:]
    for (key, raw) in object {
      guard let converted = jsonValue(raw) else { return nil }
      result[key] = converted
    }
    return .object(result)
  case let array as [Any]:
    let converted = array.compactMap(jsonValue)
    return converted.count == array.count ? .array(converted) : nil
  case _ as NSNull: return .null
  default: return nil
  }
}
