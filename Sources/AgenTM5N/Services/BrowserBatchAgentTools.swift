import Foundation

/// Provider-neutral multi-step Microsoft Edge automation.
///
/// The batch itself is one centrally authorized execute-risk tool call. Individual
/// steps are forwarded directly to the native browser service only after that
/// authorization has succeeded, so Apple and Ollama providers share identical
/// execution semantics without generating multiple approval prompts.
public enum BrowserBatchAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "browser_batch",
      description: "Execute 1 to 12 Microsoft Edge interactions in exact order, then optionally read the final page. Use for multi-step form filling and browser automation. The entire batch is one execute-risk action and never exposes cookies, browser passwords, localStorage, or sessionStorage.",
      parameters: objectSchema(
        required: ["steps"],
        properties: [
          "tab_id": stringSchema("Optional existing tab ID. Defaults to the currently selected AgenTM5N browser tab."),
          "steps": .object([
            "type": .string("array"),
            "description": .string("Ordered browser actions, from 1 to 12 steps."),
            "minItems": .number(1),
            "maxItems": .number(12),
            "items": .object([
              "type": .string("object"),
              "required": .array([.string("action")]),
              "properties": .object([
                "action": stringSchema("click, fill, select, check, uncheck, press, scroll, or wait."),
                "ref": stringSchema("Temporary element ref returned by browser_read, such as b1."),
                "selector": stringSchema("Optional CSS selector when no ref is available."),
                "target_text": stringSchema("Optional visible element text or label."),
                "text": stringSchema("Text for fill/select or key fallback for press."),
                "key": stringSchema("Optional keyboard key."),
                "amount": integerSchema("Optional vertical scroll amount in pixels.", minimum: -20_000, maximum: 20_000),
                "timeout_ms": integerSchema("Optional wait timeout in milliseconds.", minimum: 100, maximum: 30_000),
              ]),
              "additionalProperties": .bool(false),
            ]),
          ]),
          "read_after": boolSchema("Read the final page after all steps. Defaults to true."),
        ]
      )
    )
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    call.function.name == "browser_batch"
  }

  public static func risk(for call: ProviderToolCall) -> ToolRisk {
    .execute
  }

  public static func summary(for call: ProviderToolCall) -> String {
    guard case .array(let steps) = call.function.arguments["steps"] else {
      return "browser_batch"
    }
    let actions = steps.prefix(12).compactMap { value -> String? in
      guard case .object(let object) = value,
        let action = object["action"]?.stringValue
      else { return nil }
      if action.caseInsensitiveCompare("fill") == .orderedSame,
        let text = object["text"]
      {
        return "fill(<\(text.compactDescription.utf8.count) Bytes>)"
      }
      if action.caseInsensitiveCompare("select") == .orderedSame,
        let text = object["text"]
      {
        return "select(<\(text.compactDescription.utf8.count) Bytes>)"
      }
      return action
    }
    let tab = call.function.arguments["tab_id"]?.stringValue
      .map { " tab=\(String($0.prefix(80)))" } ?? ""
    return "browser_batch — \(steps.count) Schritte\(tab): \(actions.joined(separator: " → "))"
  }

  public static func execute(
    call: ProviderToolCall,
    service: MicrosoftEdgeBrowserService = .shared
  ) async -> ToolExecutionResult {
    guard case .array(let rawSteps) = call.function.arguments["steps"],
      !rawSteps.isEmpty,
      rawSteps.count <= 12
    else {
      return .init(success: false, output: "browser_batch benötigt 1 bis 12 gültige Schritte.")
    }

    let tabID = normalizedString(call.function.arguments["tab_id"]?.stringValue)
    var outputs: [String] = []

    for (index, value) in rawSteps.enumerated() {
      guard case .object(let object) = value,
        let rawAction = object["action"]?.stringValue
      else {
        return .init(success: false, output: "browser_batch Schritt \(index + 1) ist ungültig.")
      }

      let action = rawAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let allowedActions: Set<String> = [
        "click", "fill", "select", "check", "uncheck", "press", "scroll", "wait",
      ]
      guard allowedActions.contains(action) else {
        return .init(
          success: false,
          output: "browser_batch Schritt \(index + 1) verwendet eine nicht erlaubte Aktion: \(rawAction)"
        )
      }

      var arguments: [String: JSONValue] = ["action": .string(action)]
      if let tabID { arguments["tab_id"] = .string(tabID) }

      for key in ["ref", "selector", "target_text", "text", "key"] {
        if let text = normalizedString(object[key]?.stringValue) {
          arguments[key] = .string(text)
        }
      }
      if case .number(let amount) = object["amount"], amount.isFinite {
        arguments["amount"] = .number(amount)
      }
      if case .number(let timeout) = object["timeout_ms"], timeout.isFinite {
        arguments["timeout_ms"] = .number(timeout)
      }

      let stepCall = ProviderToolCall(
        function: .init(name: "browser_action", arguments: arguments)
      )
      let result = await service.execute(call: stepCall)
      outputs.append("STEP \(index + 1) \(action):\n\(result.output)")
      if !result.success {
        return .init(success: false, output: outputs.joined(separator: "\n\n"))
      }
    }

    if call.function.arguments["read_after"]?.boolValue ?? true {
      var readArguments: [String: JSONValue] = [
        "max_chars": .number(10_000),
        "max_elements": .number(120),
      ]
      if let tabID { readArguments["tab_id"] = .string(tabID) }
      let readCall = ProviderToolCall(
        function: .init(name: "browser_read", arguments: readArguments)
      )
      let snapshot = await service.execute(call: readCall)
      outputs.append("FINAL PAGE:\n\(snapshot.output)")
      if !snapshot.success {
        return .init(success: false, output: outputs.joined(separator: "\n\n"))
      }
    }

    return .init(success: true, output: outputs.joined(separator: "\n\n"))
  }

  private static func normalizedString(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func objectSchema(
    required: [String] = [],
    properties: [String: JSONValue]
  ) -> JSONValue {
    var schema: [String: JSONValue] = [
      "type": .string("object"),
      "properties": .object(properties),
      "additionalProperties": .bool(false),
    ]
    if !required.isEmpty {
      schema["required"] = .array(required.map(JSONValue.string))
    }
    return .object(schema)
  }

  private static func stringSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("string"),
      "description": .string(description),
    ])
  }

  private static func boolSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("boolean"),
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
}
