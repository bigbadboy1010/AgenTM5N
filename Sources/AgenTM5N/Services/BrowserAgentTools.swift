import Foundation

public enum BrowserAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "browser_session",
      description: "Control the persistent AgenTM5N-managed Microsoft Edge automation session. Operations: start, status, or stop. The managed Edge profile is separate from the user's normal browser profile and persists between AgenTM5N launches.",
      parameters: objectSchema(
        required: ["operation"],
        properties: [
          "operation": stringSchema("start, status, or stop.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "browser_tabs",
      description: "List open page tabs in the AgenTM5N-managed Microsoft Edge session. Returns tab IDs, titles, and URLs, never cookies or browser credentials.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "browser_open",
      description: "Open an http, https, edge, or about URL in Microsoft Edge. By default opens a new tab; when tab_id is supplied, navigates that existing tab.",
      parameters: objectSchema(
        required: ["url"],
        properties: [
          "url": stringSchema("Absolute browser URL."),
          "tab_id": stringSchema("Optional existing tab ID to navigate instead of opening a new tab.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "browser_read",
      description: "Read a bounded semantic snapshot of a Microsoft Edge tab. Returns page title, URL, visible text, and interactive elements annotated with temporary AgenTM5N refs for later clicking or filling. Password values, cookies, localStorage, and sessionStorage are never returned.",
      parameters: objectSchema(
        properties: [
          "tab_id": stringSchema("Optional tab ID. Defaults to the last AgenTM5N-selected page tab."),
          "max_chars": integerSchema("Maximum visible-text characters from 1000 to 60000. Defaults to 30000.", minimum: 1_000, maximum: 60_000),
          "max_elements": integerSchema("Maximum interactive elements from 10 to 250. Defaults to 120.", minimum: 10, maximum: 250)
        ]
      )
    ),
    ProviderToolDefinition(
      name: "browser_action",
      description: "Interact with the current Microsoft Edge page. Actions: click, fill, select, check, uncheck, press, scroll, wait, activate_tab, close_tab, back, forward, or reload. Prefer a ref returned by browser_read; CSS selector or visible text may be used when a ref is unavailable. This tool never exposes cookies or saved browser passwords.",
      parameters: objectSchema(
        required: ["action"],
        properties: [
          "action": stringSchema("click, fill, select, check, uncheck, press, scroll, wait, activate_tab, close_tab, back, forward, or reload."),
          "tab_id": stringSchema("Optional target tab ID. Defaults to the last AgenTM5N-selected page tab."),
          "ref": stringSchema("Temporary element ref returned by browser_read, such as b12."),
          "selector": stringSchema("Optional CSS selector when no ref is available."),
          "target_text": stringSchema("Optional visible element text when no ref or selector is available."),
          "text": stringSchema("Text to enter for fill, option text/value for select, or key name for press when key is omitted. The audit records only its byte length."),
          "key": stringSchema("Keyboard key for press, for example Enter, Tab, Escape, ArrowDown, ArrowUp, Space, or Backspace."),
          "amount": integerSchema("Vertical scroll amount in pixels. Positive scrolls down; negative scrolls up. Defaults to 700.", minimum: -20_000, maximum: 20_000),
          "timeout_ms": integerSchema("Wait timeout from 100 to 30000 milliseconds. Defaults to 5000.", minimum: 100, maximum: 30_000)
        ]
      )
    )
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for call: ProviderToolCall) -> ToolRisk {
    switch call.function.name {
    case "browser_tabs", "browser_read":
      return .read
    case "browser_session":
      let operation = call.function.arguments["operation"]?.stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ""
      return operation == "status" ? .read : .execute
    default:
      return .execute
    }
  }

  public static func summary(for call: ProviderToolCall) -> String {
    let values = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      if key == "text" {
        return "text: <\(value.compactDescription.utf8.count) Bytes>"
      }
      if key == "url", let rawURL = value.stringValue {
        return "url: \(safeURLSummary(rawURL))"
      }
      let rendered = value.compactDescription
      return "\(key): \(rendered.count > 180 ? String(rendered.prefix(180)) + "…" : rendered)"
    }
    return values.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(values.joined(separator: ", "))"
  }

  private static func safeURLSummary(_ value: String) -> String {
    guard var components = URLComponents(string: value) else {
      return "<browser-url>"
    }
    components.user = nil
    components.password = nil
    components.query = nil
    components.fragment = nil
    let rendered = components.string ?? "<browser-url>"
    return rendered.count > 220 ? String(rendered.prefix(220)) + "…" : rendered
  }

  private static func objectSchema(
    required: [String] = [],
    properties: [String: JSONValue]
  ) -> JSONValue {
    var value: [String: JSONValue] = [
      "type": .string("object"),
      "properties": .object(properties),
      "additionalProperties": .bool(false)
    ]
    if !required.isEmpty {
      value["required"] = .array(required.map(JSONValue.string))
    }
    return .object(value)
  }

  private static func stringSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("string"),
      "description": .string(description)
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
      "maximum": .number(Double(maximum))
    ])
  }
}
