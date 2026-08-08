import Foundation

public enum AgentDelegationTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "agent_delegate",
      description: "Delegate a bounded subtask to one enabled persistent specialist agent. AgenTM5N resolves the saved profile locally and runs the subtask with that profile's preferred provider when possible. The delegated agent never receives Vault secret values directly.",
      parameters: objectSchema(
        required: ["agent", "task"],
        properties: [
          "agent": stringSchema("Exact persistent-agent name or UUID."),
          "task": stringSchema("Concrete bounded subtask for the specialist."),
          "allow_tools": boolSchema("Allow the delegated specialist to use provider-neutral AgenTM5N tools. Defaults to true for Ollama delegates and false for Apple delegates to avoid nested on-device tool recursion.")
        ]
      )
    )
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    call.function.name == "agent_delegate"
  }

  public static func risk(for _: ProviderToolCall) -> ToolRisk { .execute }

  public static func summary(for call: ProviderToolCall) -> String {
    let agent = call.function.arguments["agent"]?.compactDescription ?? "?"
    let task = call.function.arguments["task"]?.compactDescription ?? "?"
    let bounded = task.count > 220 ? String(task.prefix(220)) + "…" : task
    return "agent_delegate — agent: \(agent), task: \(bounded)"
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
}
