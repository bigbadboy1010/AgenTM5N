import Foundation
import FoundationModels

public enum AppleRoutedBrowserTools {
  public static func makeTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      BrowserTabsTool(bridge: bridge),
      BrowserOpenTool(bridge: bridge),
      BrowserReadTool(bridge: bridge),
      BrowserBatchTool(bridge: bridge),
    ]
  }

  public static func makeExistingPageTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      BrowserTabsTool(bridge: bridge),
      BrowserReadTool(bridge: bridge),
      BrowserBatchTool(bridge: bridge),
    ]
  }
}

private struct BrowserSessionTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "browser_session"
  let description = "Start, inspect, or stop the persistent AgenTM5N-managed Microsoft Edge automation session. Use start before explicit browser work when necessary."

  @Generable
  struct Arguments {
    @Guide(description: "start, status, or stop")
    var operation: String
  }

  func call(arguments: Arguments) async throws -> String {
    await routeBrowser(
      bridge: bridge,
      name: name,
      arguments: ["operation": .string(arguments.operation)]
    )
  }
}

private struct BrowserTabsTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "browser_tabs"
  let description = "List Microsoft Edge page tabs with tab IDs, titles, and URLs. Does not expose cookies or browser credentials."

  @Generable
  struct Arguments {
    @Guide(description: "Optional. Omit this value or use all.")
    var query: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    await routeBrowser(bridge: bridge, name: name, arguments: [:])
  }
}

private struct BrowserOpenTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "browser_open"
  let description = "Open a URL in Microsoft Edge. Leave tab_id empty to open a new tab; otherwise navigate that existing tab."

  @Generable
  struct Arguments {
    @Guide(description: "Absolute http, https, edge, or about URL")
    var url: String

    @Guide(description: "Existing tab ID, or empty string for a new tab")
    var tabID: String
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = ["url": .string(arguments.url)]
    if !arguments.tabID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      values["tab_id"] = .string(arguments.tabID)
    }
    return await routeBrowser(bridge: bridge, name: name, arguments: values)
  }
}

private struct BrowserReadTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "browser_read"
  let description = "Read a semantic snapshot of a Microsoft Edge page. It returns visible text plus interactive elements with temporary refs such as b12. Use these refs with browser_action."

  @Generable
  struct Arguments {
    @Guide(description: "Tab ID, or empty for the last selected tab")
    var tabID: String

    @Guide(description: "Maximum visible-text characters from 1000 to 60000")
    var maxChars: Int

    @Guide(description: "Maximum interactive elements from 10 to 250")
    var maxElements: Int
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "max_chars": .number(Double(arguments.maxChars)),
      "max_elements": .number(Double(arguments.maxElements)),
    ]
    if !arguments.tabID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      values["tab_id"] = .string(arguments.tabID)
    }
    return await routeBrowser(bridge: bridge, name: name, arguments: values)
  }
}


private struct BrowserBatchTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "browser_batch"
  let description = """
  Execute multiple Microsoft Edge interactions in exact order in one tool call.
  Use this whenever the user requests two or more browser actions such as
  fill, check, select, click, press, scroll, or wait.
  Prefer refs returned by the latest browser_read.
  """

  @Generable
  struct Step {
    @Guide(description: "click, fill, select, check, uncheck, press, scroll, or wait")
    var action: String

    @Guide(description: "Element ref from the latest browser_read, such as b1")
    var ref: String? = nil

    @Guide(description: "Optional CSS selector")
    var selector: String? = nil

    @Guide(description: "Optional visible element text or label")
    var targetText: String? = nil

    @Guide(description: "Text for fill/select or key fallback for press")
    var text: String? = nil

    @Guide(description: "Optional keyboard key")
    var key: String? = nil

    @Guide(description: "Optional vertical scroll amount")
    var amount: Int? = nil

    @Guide(description: "Optional timeout in milliseconds")
    var timeoutMilliseconds: Int? = nil
  }

  @Generable
  struct Arguments {
    @Guide(description: "Existing tab ID. Omit to use the currently selected browser tab.")
    var tabID: String? = nil

    @Guide(description: "Browser operations to perform, in exact order")
    var steps: [Step]

    @Guide(description: "Read the page again after all actions. Normally true.")
    var readAfter: Bool? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    guard !arguments.steps.isEmpty else {
      return "browser_batch failed: no steps supplied."
    }

    guard arguments.steps.count <= 12 else {
      return "browser_batch failed: maximum 12 steps."
    }

    var outputs: [String] = []

    for (index, step) in arguments.steps.enumerated() {
      var values: [String: JSONValue] = [
        "action": .string(step.action)
      ]

      if let tabID = arguments.tabID,
         !tabID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        values["tab_id"] = .string(tabID)
      }

      let optionalStrings: [(String, String?)] = [
        ("ref", step.ref),
        ("selector", step.selector),
        ("target_text", step.targetText),
        ("text", step.text),
        ("key", step.key),
      ]

      for (name, value) in optionalStrings {
        if let value,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          values[name] = .string(value)
        }
      }

      if let amount = step.amount {
        values["amount"] = .number(Double(amount))
      }

      if let timeout = step.timeoutMilliseconds {
        values["timeout_ms"] = .number(Double(timeout))
      }

      let result = await routeBrowser(
        bridge: bridge,
        name: "browser_action",
        arguments: values
      )

      outputs.append(
        "STEP \(index + 1) \(step.action):\n\(result)"
      )
    }

    if arguments.readAfter ?? true {
      var readArguments: [String: JSONValue] = [
        "max_chars": .number(10_000),
        "max_elements": .number(120)
      ]

      if let tabID = arguments.tabID,
         !tabID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        readArguments["tab_id"] = .string(tabID)
      }

      let snapshot = await routeBrowser(
        bridge: bridge,
        name: "browser_read",
        arguments: readArguments
      )

      outputs.append("FINAL PAGE:\n\(snapshot)")
    }

    return outputs.joined(separator: "\n\n")
  }
}

private struct BrowserActionTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "browser_action"
  let description = "Interact with Microsoft Edge. Actions: click, fill, select, check, uncheck, press, scroll, wait, activate_tab, close_tab, back, forward, reload. Prefer a ref from browser_read. Never request or expose cookies, localStorage, sessionStorage, or saved browser passwords."

  @Generable
  struct Arguments {
    @Guide(description: "click, fill, select, check, uncheck, press, scroll, wait, activate_tab, close_tab, back, forward, or reload")
    var action: String

    @Guide(description: "Tab ID, or empty for the last selected tab")
    var tabID: String

    @Guide(description: "Element ref from browser_read, or empty")
    var ref: String

    @Guide(description: "CSS selector, or empty")
    var selector: String

    @Guide(description: "Visible target text, or empty")
    var targetText: String

    @Guide(description: "Text to fill/select, key fallback for press, or empty")
    var text: String

    @Guide(description: "Keyboard key such as Enter, Tab, Escape, ArrowDown, or empty")
    var key: String

    @Guide(description: "Scroll pixels; use 700 when not scrolling")
    var amount: Int

    @Guide(description: "Timeout in milliseconds; use 5000 when not waiting")
    var timeoutMilliseconds: Int
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "action": .string(arguments.action),
      "text": .string(arguments.text),
      "amount": .number(Double(arguments.amount)),
      "timeout_ms": .number(Double(arguments.timeoutMilliseconds)),
    ]
    let optional: [(String, String)] = [
      ("tab_id", arguments.tabID),
      ("ref", arguments.ref),
      ("selector", arguments.selector),
      ("target_text", arguments.targetText),
      ("key", arguments.key),
    ]
    for (name, value) in optional
    where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      values[name] = .string(value)
    }
    return await routeBrowser(bridge: bridge, name: name, arguments: values)
  }
}

private func routeBrowser(
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
