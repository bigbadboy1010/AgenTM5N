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
    @Guide(description: "Use the literal value all")
    var query: String
  }

  func call(arguments: Arguments) async throws -> String {
    await route(name: name, arguments: [:])
  }
}

private struct AgentGetTool: Tool {
  let name = "agent_get"
  let description = "Read one persistent reusable AgenTM5N specialist agent by exact name or UUID."

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
  let description = "Create or replace a persistent reusable specialist agent when the user explicitly asks to create, save, build, remember, or define an agent. The saved agent appears in the Agenten section and remains available after relaunch."

  @Generable
  struct Arguments {
    @Guide(description: "Short unique agent name")
    var name: String

    @Guide(description: "Concise recurring purpose")
    var purpose: String

    @Guide(description: "Complete operational specialist instructions without secrets")
    var instructions: String

    @Guide(description: "current, apple_on_device, ollama_local, or ollama_cloud")
    var provider: String

    @Guide(description: "SF Symbols name, or empty string for the default")
    var symbol: String
  }

  func call(arguments: Arguments) async throws -> String {
    await route(
      name: name,
      arguments: [
        "name": .string(arguments.name),
        "purpose": .string(arguments.purpose),
        "instructions": .string(arguments.instructions),
        "provider": .string(arguments.provider),
        "symbol": .string(arguments.symbol),
      ]
    )
  }
}

private struct AgentUpdateTool: Tool {
  let name = "agent_update"
  let description = "Update an existing persistent specialist agent. Empty text fields keep their current values. enabled_mode must be unchanged, true, or false."

  @Generable
  struct Arguments {
    @Guide(description: "Exact saved agent name or UUID")
    var agent: String

    @Guide(description: "New name, or empty string")
    var name: String

    @Guide(description: "New purpose, or empty string")
    var purpose: String

    @Guide(description: "New specialist instructions, or empty string")
    var instructions: String

    @Guide(description: "New provider preference, or empty string")
    var provider: String

    @Guide(description: "New SF Symbols name, or empty string")
    var symbol: String

    @Guide(description: "unchanged, true, or false")
    var enabledMode: String
  }

  func call(arguments: Arguments) async throws -> String {
    await route(
      name: name,
      arguments: [
        "agent": .string(arguments.agent),
        "name": .string(arguments.name),
        "purpose": .string(arguments.purpose),
        "instructions": .string(arguments.instructions),
        "provider": .string(arguments.provider),
        "symbol": .string(arguments.symbol),
        "enabled_mode": .string(arguments.enabledMode),
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
