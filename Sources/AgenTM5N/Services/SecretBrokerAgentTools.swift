import Foundation

public enum SecretBrokerAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "secret_list",
      description: "List metadata for secrets in the unlocked AgenTM5N Vault. Returns IDs, labels, kinds and optional username/host metadata only. Secret values are never returned.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "secret_run_command",
      description: "Run a local zsh command with one unlocked AgenTM5N Vault secret injected only into a named environment variable. The model never receives the secret value. AgenTM5N redacts the exact secret value from stdout/stderr before returning tool output. Do not use this for SSH private keys; use configured SSH profiles instead.",
      parameters: objectSchema(
        required: ["secret", "environment_variable", "command"],
        properties: [
          "secret": stringSchema("Exact secret label or UUID from secret_list."),
          "environment_variable": stringSchema("Environment variable name such as API_TOKEN. The command references it as $API_TOKEN."),
          "command": stringSchema("Local zsh command to execute in the configured workspace. Do not print or otherwise intentionally expose the secret."),
        ]
      )
    ),
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for call: ProviderToolCall) -> ToolRisk {
    call.function.name == "secret_list" ? .read : .execute
  }

  public static func summary(for call: ProviderToolCall) -> String {
    switch call.function.name {
    case "secret_list":
      return "secret_list — Metadaten ohne Secret-Werte"
    case "secret_run_command":
      let secret = call.function.arguments["secret"]?.compactDescription ?? "?"
      let variable = call.function.arguments["environment_variable"]?.compactDescription ?? "?"
      let command = call.function.arguments["command"]?.compactDescription ?? ""
      let boundedCommand = command.count > 180 ? "\(command.prefix(180))…" : command
      return "secret_run_command — secret: \(secret), env: \(variable), command: \(boundedCommand)"
    default:
      return call.function.name
    }
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
}
