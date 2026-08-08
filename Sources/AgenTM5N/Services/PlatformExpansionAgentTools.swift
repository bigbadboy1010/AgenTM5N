import Foundation

public enum PlatformExpansionAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "secret_list",
      description: "List non-secret metadata for unlocked AgenTM5N Vault entries. Returns labels and kinds, never secret values or secret identifiers. Use the label as secret_ref in tools that explicitly support secrets.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "http_request",
      description: "Perform an HTTP(S) request. An optional Vault secret is resolved internally by label and injected only by the native executor. Secret values are never returned to the model. External network requests require AgenTM5N approval.",
      parameters: objectSchema(
        required: ["method", "url"],
        properties: [
          "method": stringSchema("HTTP method: GET, HEAD, POST, PUT, PATCH, DELETE, or OPTIONS."),
          "url": stringSchema("Absolute http or https URL. Do not put credentials in the URL."),
          "headers": stringMapSchema("Optional non-secret HTTP headers."),
          "body": stringSchema("Optional request body. JSON is the default content type when none is supplied."),
          "secret_ref": stringSchema("Optional exact Vault secret label. The value stays inside AgenTM5N."),
          "secret_usage": stringSchema("Optional secret usage: bearer, basic, or header. Defaults to bearer."),
          "secret_header": stringSchema("Header name when secret_usage is header. Defaults to X-API-Key.")
        ]
      )
    ),

    ProviderToolDefinition(
      name: "system_info",
      description: "Return local Mac hardware, operating-system, uptime, processor architecture, and memory information without exposing secrets.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "process_list",
      description: "Return a bounded local process list sorted by CPU usage.",
      parameters: objectSchema(
        properties: [
          "limit": integerSchema("Maximum number of processes, 1 to 100.", minimum: 1, maximum: 100)
        ]
      )
    ),
    ProviderToolDefinition(
      name: "disk_info",
      description: "Return local filesystem capacity and free-space information using a read-only system query.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "network_info",
      description: "Return bounded local network-interface and routing information. Does not reveal Vault secrets.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "clipboard_read",
      description: "Read plain text from the macOS clipboard. Use only when the user asks to inspect or use clipboard content.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "clipboard_write",
      description: "Replace the macOS clipboard with supplied plain text.",
      parameters: objectSchema(
        required: ["text"],
        properties: ["text": stringSchema("Plain text to copy to the clipboard.")]
      )
    ),
    ProviderToolDefinition(
      name: "notification_send",
      description: "Display a local macOS notification using an AppleScript notification command.",
      parameters: objectSchema(
        required: ["title", "message"],
        properties: [
          "title": stringSchema("Notification title."),
          "message": stringSchema("Notification body."),
          "subtitle": stringSchema("Optional subtitle.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "shortcuts_list",
      description: "List shortcuts available through the macOS Shortcuts command-line interface.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "shortcuts_run",
      description: "Run a named macOS Shortcut. The shortcut itself may perform additional actions and therefore requires execution approval.",
      parameters: objectSchema(
        required: ["name"],
        properties: ["name": stringSchema("Exact shortcut name.")]
      )
    ),
    ProviderToolDefinition(
      name: "finder_reveal",
      description: "Reveal a local path in Finder. Workspace boundaries apply unless Full Access is enabled.",
      parameters: objectSchema(
        required: ["path"],
        properties: ["path": stringSchema("Workspace-relative or absolute path to reveal.")]
      )
    ),

    ProviderToolDefinition(
      name: "ssh_upload",
      description: "Upload one local workspace file to a saved SSH profile using SCP. AgenTM5N resolves linked Vault credentials internally.",
      parameters: objectSchema(
        required: ["host", "local_path", "remote_path"],
        properties: [
          "host": stringSchema("Saved SSH profile name, hostname, or UUID."),
          "local_path": stringSchema("Local file path. Must be inside the workspace unless Full Access is enabled."),
          "remote_path": stringSchema("Remote destination file or directory path.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "ssh_download",
      description: "Download one remote file from a saved SSH profile into the local workspace using SCP. AgenTM5N resolves linked Vault credentials internally.",
      parameters: objectSchema(
        required: ["host", "remote_path", "local_path"],
        properties: [
          "host": stringSchema("Saved SSH profile name, hostname, or UUID."),
          "remote_path": stringSchema("Remote source file path."),
          "local_path": stringSchema("Local destination path inside the workspace unless Full Access is enabled.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "ssh_tail_log",
      description: "Read the last bounded lines of a remote log file through a saved SSH profile using one non-interactive SSH connection.",
      parameters: objectSchema(
        required: ["host", "path"],
        properties: [
          "host": stringSchema("Saved SSH profile name, hostname, or UUID."),
          "path": stringSchema("Remote log-file path."),
          "lines": integerSchema("Number of lines, 1 to 2000. Defaults to 200.", minimum: 1, maximum: 2000)
        ]
      )
    ),
    ProviderToolDefinition(
      name: "ssh_run_batch",
      description: "Run several requested remote shell commands in order through one SSH connection. This reduces repeated SSH handshakes for diagnostic batches.",
      parameters: objectSchema(
        required: ["host", "commands"],
        properties: [
          "host": stringSchema("Saved SSH profile name, hostname, or UUID."),
          "commands": arraySchema(
            item: stringSchema("One remote command."),
            description: "Ordered commands. AgenTM5N joins them safely as a sequential remote script."
          )
        ]
      )
    ),

    ProviderToolDefinition(
      name: "app_version_info",
      description: "Return AgenTM5N's current app version, build number, bundle identifier, and update channel metadata.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "app_check_update",
      description: "Check a user-provided HTTPS JSON update manifest for a newer AgenTM5N version. The manifest may contain version, build, download_url, and notes fields. This tool never installs automatically.",
      parameters: objectSchema(
        required: ["manifest_url"],
        properties: [
          "manifest_url": stringSchema("HTTPS URL of the AgenTM5N update manifest.")
        ]
      )
    )
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for call: ProviderToolCall) -> ToolRisk {
    AgentToolRegistry.entry(named: call.function.name)?.risk ?? .execute
  }

  public static func summary(for call: ProviderToolCall) -> String {
    let values = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      if key == "body" || key == "text" {
        return "\(key): <\(value.compactDescription.utf8.count) Bytes>"
      }
      if key == "headers" {
        return "headers: <metadata>"
      }
      // secret_ref is a label, never the secret value. It remains useful in the
      // audit while the Vault content itself stays hidden.
      let rendered = value.compactDescription
      return "\(key): \(rendered.count > 180 ? String(rendered.prefix(180)) + "…" : rendered)"
    }
    return values.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(values.joined(separator: ", "))"
  }

  private static func objectSchema(
    required: [String] = [],
    properties: [String: JSONValue]
  ) -> JSONValue {
    var value: [String: JSONValue] = [
      "type": .string("object"),
      "properties": .object(properties),
      "additionalProperties": .bool(false),
    ]
    if !required.isEmpty {
      value["required"] = .array(required.map(JSONValue.string))
    }
    return .object(value)
  }

  private static func stringSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("string"),
      "description": .string(description),
    ])
  }

  private static func integerSchema(
    _ description: String,
    minimum: Int,
    maximum: Int
  ) -> JSONValue {
    .object([
      "type": .string("integer"),
      "description": .string(description),
      "minimum": .number(Double(minimum)),
      "maximum": .number(Double(maximum)),
    ])
  }

  private static func arraySchema(
    item: JSONValue,
    description: String
  ) -> JSONValue {
    .object([
      "type": .string("array"),
      "items": item,
      "description": .string(description),
    ])
  }

  private static func stringMapSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("object"),
      "description": .string(description),
      "additionalProperties": .object(["type": .string("string")]),
    ])
  }
}
