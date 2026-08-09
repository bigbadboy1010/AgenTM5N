import Foundation
import FoundationModels

public enum AppleRoutedToolsmithTools {
  public static func makeTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [ToolsmithTool(bridge: bridge)]
  }
}

private struct ToolsmithTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "toolsmith"
  let description = "Build, inspect, list, delete, or run persistent AgenTM5N runtime tools. Self-built tools use zsh or python3, receive structured parameters, run in the configured workspace, and never receive Vault secrets automatically."

  @Generable
  struct Arguments {
    @Guide(description: "Operation: list, get, create, delete, or run")
    var operation: String

    @Guide(description: "Optional exact custom tool name or UUID for get/delete/run")
    var tool: String? = nil

    @Guide(description: "Optional new tool name for create; custom_ is added automatically")
    var name: String? = nil

    @Guide(description: "Optional precise description of when future models should call the tool")
    var description: String? = nil

    @Guide(description: "Optional language: zsh or python3")
    var language: String? = nil

    @Guide(description: "Optional JSON array of parameter objects with name,type,description,required; use [] for no parameters")
    var parametersJSON: String? = nil

    @Guide(description: "Optional complete zsh or python3 source. Read inputs from AGENTM5N_ARGS_FILE or AGENTM5N_ARG_<NAME>. Never embed secrets.")
    var source: String? = nil

    @Guide(description: "Optional JSON object containing arguments when running a custom tool; use {} for no arguments")
    var argumentsJSON: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    let operation = arguments.operation
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    switch operation {
    case "list":
      return await route(name: "toolsmith_list", arguments: [:])

    case "get":
      return await route(
        name: "toolsmith_get",
        arguments: ["tool": .string(arguments.tool ?? "")]
      )

    case "create":
      return await route(
        name: "toolsmith_create",
        arguments: [
          "name": .string(arguments.name ?? ""),
          "description": .string(arguments.description ?? ""),
          "language": .string(arguments.language ?? "zsh"),
          "parameters_json": .string(arguments.parametersJSON ?? "[]"),
          "source": .string(arguments.source ?? ""),
        ]
      )

    case "delete":
      return await route(
        name: "toolsmith_delete",
        arguments: ["tool": .string(arguments.tool ?? "")]
      )

    case "run":
      return await route(
        name: "toolsmith_run",
        arguments: [
          "tool": .string(arguments.tool ?? ""),
          "arguments_json": .string(arguments.argumentsJSON ?? "{}"),
        ]
      )

    default:
      return "TOOL_ERROR: toolsmith operation must be list, get, create, delete, or run."
    }
  }

  private func route(
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
}
