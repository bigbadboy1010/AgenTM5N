import Foundation
import FoundationModels

public enum AppleRoutedPersistentAgentTools {
  public static func makeTools() -> [any Tool] {
    [
      AgentListTool(),
      AgentGetTool(),
      AgentCreateTool(),
      AgentUpdateTool(),
      AgentDeleteTool(),
    ]
  }
}

private struct AgentListTool: Tool {
  let name = "agent_list"
  let description = "List persistent reusable AgenTM5N specialist agents. Use this before creating a duplicate or when the user asks which agents are saved."

  @Generable
  struct Arguments {
    @Guide(description: "Optional. Omit this value or use all.")
    var query: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    await route(name: name, arguments: [:])
  }
}

private struct AgentGetTool: Tool {
  let name = "agent_get"
  let description = "Read one persistent reusable AgenTM5N specialist agent by exact name or UUID, including any explicit sandbox capability scope."

  @Generable
  struct Arguments {
    @Guide(description: "Exact saved agent name or UUID")
    var agent: String
  }

  func call(arguments: Arguments) async throws -> String {
    await route(
      name: name,
      arguments: ["agent": .string(arguments.agent)]
    )
  }
}

private struct AgentCreateTool: Tool {
  let name = "agent_create"
  let description = "Create or replace a persistent reusable specialist agent when the user explicitly asks to create or save an agent. Use capabilities=all by default so the specialist has the same centrally authorized AgenTM5N tool capabilities as the main agent. Restrict capabilities only when the user explicitly requests a sandbox. Never put secrets in the agent profile."

  @Generable
  struct Arguments {
    @Guide(description: "Short unique agent name")
    var name: String

    @Guide(description: "Concise recurring purpose")
    var purpose: String

    @Guide(description: "Complete operational specialist instructions without secrets")
    var instructions: String

    @Guide(description: "Optional provider: current, apple_on_device, ollama_local, or ollama_cloud. Defaults to current.")
    var provider: String? = nil

    @Guide(description: "Optional SF Symbols name. Omit for the default.")
    var symbol: String? = nil

    @Guide(description: "Optional capability scope. Omit or use all by default; only restrict when the user explicitly requests a sandbox.")
    var capabilities: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    let capabilityText = arguments.capabilities?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let values: [String: JSONValue] = [
      "name": .string(arguments.name),
      "purpose": .string(arguments.purpose),
      "instructions": .string(arguments.instructions),
      "provider": .string(arguments.provider ?? "current"),
      "symbol": .string(arguments.symbol ?? ""),
      "capabilities": .string(capabilityText.isEmpty ? "all" : capabilityText),
    ]
    return await route(name: name, arguments: values)
  }
}

private struct AgentUpdateTool: Tool {
  let name = "agent_update"
  let description = "Update an existing persistent specialist agent. Omitted fields keep their current values. capabilities may be unchanged, all, or a comma-separated sandbox capability set."

  @Generable
  struct Arguments {
    @Guide(description: "Exact saved agent name or UUID")
    var agent: String

    @Guide(description: "Optional new name")
    var name: String? = nil

    @Guide(description: "Optional new purpose")
    var purpose: String? = nil

    @Guide(description: "Optional new specialist instructions")
    var instructions: String? = nil

    @Guide(description: "Optional new provider preference")
    var provider: String? = nil

    @Guide(description: "Optional new SF Symbols name")
    var symbol: String? = nil

    @Guide(description: "Optional enabled mode: unchanged, true, or false")
    var enabledMode: String? = nil

    @Guide(description: "Optional capability mode: unchanged, all, or comma-separated sandbox capability names")
    var capabilities: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    await route(
      name: name,
      arguments: [
        "agent": .string(arguments.agent),
        "name": .string(arguments.name ?? ""),
        "purpose": .string(arguments.purpose ?? ""),
        "instructions": .string(arguments.instructions ?? ""),
        "provider": .string(arguments.provider ?? ""),
        "symbol": .string(arguments.symbol ?? ""),
        "enabled_mode": .string(arguments.enabledMode ?? "unchanged"),
        "capabilities": .string(arguments.capabilities ?? "unchanged"),
      ]
    )
  }
}

private struct AgentDeleteTool: Tool {
  let name = "agent_delete"
  let description = "Delete one persistent reusable specialist agent. Use only when the user explicitly asks to remove or delete it."

  @Generable
  struct Arguments {
    @Guide(description: "Exact saved agent name or UUID")
    var agent: String
  }

  func call(arguments: Arguments) async throws -> String {
    await route(
      name: name,
      arguments: ["agent": .string(arguments.agent)]
    )
  }
}

private func route(
  name: String,
  arguments: [String: JSONValue]
) async -> String {
  await AgentToolExecutionBridge.shared.execute(
    ProviderToolCall(
      function: ProviderToolCall.Function(
        name: name,
        arguments: arguments
      )
    )
  )
}
