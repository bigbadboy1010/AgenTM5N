import Foundation

public enum PersistentAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "agent_list",
      description: "List persistent reusable AgenTM5N specialist agents. Use this before creating a duplicate agent or when the user asks what saved agents exist.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "agent_get",
      description: "Read one persistent reusable AgenTM5N specialist agent by exact name or UUID, including its purpose and specialist instructions.",
      parameters: objectSchema(
        required: ["agent"],
        properties: [
          "agent": stringSchema("Exact saved agent name or UUID.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "agent_create",
      description: "Create or replace a persistent reusable specialist agent for a recurring task. Use when the user explicitly asks to create, save, build, remember, or define an agent. The agent remains available in the Agenten section across app restarts.",
      parameters: objectSchema(
        required: ["name", "purpose", "instructions", "provider", "symbol"],
        properties: [
          "name": stringSchema("Short unique agent name, maximum 80 characters."),
          "purpose": stringSchema("Concise recurring purpose for this specialist agent, maximum 500 characters."),
          "instructions": stringSchema("Complete specialist system instructions. Be operational and specific; do not include secrets. Maximum 12000 characters."),
          "provider": stringSchema("Provider preference: current, apple_on_device, ollama_local, or ollama_cloud."),
          "symbol": stringSchema("SF Symbols name for the Agenten UI, or an empty string for the default symbol.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "agent_update",
      description: "Update an existing persistent specialist agent. Empty text fields mean unchanged. enabled_mode must be unchanged, true, or false.",
      parameters: objectSchema(
        required: ["agent", "name", "purpose", "instructions", "provider", "symbol", "enabled_mode"],
        properties: [
          "agent": stringSchema("Exact saved agent name or UUID."),
          "name": stringSchema("New name, or empty string to keep unchanged."),
          "purpose": stringSchema("New purpose, or empty string to keep unchanged."),
          "instructions": stringSchema("New specialist instructions, or empty string to keep unchanged."),
          "provider": stringSchema("New provider preference, or empty string to keep unchanged."),
          "symbol": stringSchema("New SF Symbols name, or empty string to keep unchanged."),
          "enabled_mode": stringSchema("Use unchanged, true, or false.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "agent_delete",
      description: "Delete one persistent reusable specialist agent by exact name or UUID. Use only when the user explicitly asks to remove or delete it.",
      parameters: objectSchema(
        required: ["agent"],
        properties: [
          "agent": stringSchema("Exact saved agent name or UUID.")
        ]
      )
    )
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for call: ProviderToolCall) -> ToolRisk {
    switch call.function.name {
    case "agent_list", "agent_get": .read
    default: .write
    }
  }

  public static func summary(for call: ProviderToolCall) -> String {
    let rendered = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      if key == "instructions" {
        return "instructions: <\(value.compactDescription.utf8.count) Bytes>"
      }
      let text = value.compactDescription
      return text.count > 160
        ? "\(key): \(text.prefix(160))…"
        : "\(key): \(text)"
    }
    return rendered.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(rendered.joined(separator: ", "))"
  }

  @MainActor
  public static func execute(
    call: ProviderToolCall,
    library: PersistentAgentLibrary = .shared
  ) -> ToolExecutionResult {
    do {
      switch call.function.name {
      case "agent_list":
        return encoded(library.profiles.map(ProfileDescriptor.init))

      case "agent_get":
        let query = try requiredString("agent", in: call)
        return encoded(ProfileDescriptor(library.resolve(query)))

      case "agent_create":
        let profile = try library.create(
          name: try requiredString("name", in: call),
          purpose: try requiredString("purpose", in: call),
          instructions: try requiredString("instructions", in: call),
          providerPreference: SavedAgentProviderPreference.parse(
            try requiredString("provider", in: call)
          ),
          symbolName: try requiredStringAllowingEmpty("symbol", in: call)
        )
        return encoded(MutationDescriptor(status: "saved", profile: profile))

      case "agent_update":
        let query = try requiredString("agent", in: call)
        let providerValue = try requiredStringAllowingEmpty("provider", in: call)
        let enabledMode = try requiredStringAllowingEmpty("enabled_mode", in: call)
          .lowercased()
        let enabled: Bool?
        switch enabledMode {
        case "true": enabled = true
        case "false": enabled = false
        default: enabled = nil
        }

        let profile = try library.update(
          query: query,
          name: optionalNonEmptyString("name", in: call),
          purpose: optionalNonEmptyString("purpose", in: call),
          instructions: optionalNonEmptyString("instructions", in: call),
          providerPreference: providerValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : SavedAgentProviderPreference.parse(providerValue),
          symbolName: optionalNonEmptyString("symbol", in: call),
          enabled: enabled
        )
        return encoded(MutationDescriptor(status: "updated", profile: profile))

      case "agent_delete":
        let query = try requiredString("agent", in: call)
        let profile = try library.delete(query: query)
        return encoded(MutationDescriptor(status: "deleted", profile: profile))

      default:
        return ToolExecutionResult(
          success: false,
          output: "Unsupported persistent agent tool: \(call.function.name)"
        )
      }
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private struct ProfileDescriptor: Encodable {
    let id: String
    let name: String
    let purpose: String
    let instructions: String
    let provider: String
    let symbol: String
    let enabled: Bool
    let createdAt: Date
    let updatedAt: Date
    let lastUsedAt: Date?

    init(_ profile: SavedAgentProfile) {
      id = profile.id.uuidString
      name = profile.name
      purpose = profile.purpose
      instructions = profile.instructions
      provider = profile.providerPreference.rawValue
      symbol = profile.symbolName
      enabled = profile.isEnabled
      createdAt = profile.createdAt
      updatedAt = profile.updatedAt
      lastUsedAt = profile.lastUsedAt
    }
  }

  private struct MutationDescriptor: Encodable {
    let status: String
    let profile: ProfileDescriptor

    init(status: String, profile: SavedAgentProfile) {
      self.status = status
      self.profile = ProfileDescriptor(profile)
    }
  }

  private static func requiredString(
    _ name: String,
    in call: ProviderToolCall
  ) throws -> String {
    guard let value = optionalNonEmptyString(name, in: call) else {
      throw AgentRuntimeError.missingArgument(tool: call.function.name, name: name)
    }
    return value
  }

  private static func requiredStringAllowingEmpty(
    _ name: String,
    in call: ProviderToolCall
  ) throws -> String {
    guard let value = call.function.arguments[name]?.stringValue else {
      throw AgentRuntimeError.missingArgument(tool: call.function.name, name: name)
    }
    return value
  }

  private static func optionalNonEmptyString(
    _ name: String,
    in call: ProviderToolCall
  ) -> String? {
    guard let value = call.function.arguments[name]?.stringValue else { return nil }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }

  private static func encoded<T: Encodable>(_ value: T) -> ToolExecutionResult {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(value)
      return ToolExecutionResult(
        success: true,
        output: String(decoding: data, as: UTF8.self)
      )
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private static func objectSchema(
    required: [String] = [],
    properties: [String: JSONValue]
  ) -> JSONValue {
    var schema: [String: JSONValue] = [
      "type": .string("object"),
      "properties": .object(properties),
      "additionalProperties": .bool(false)
    ]
    if !required.isEmpty {
      schema["required"] = .array(required.map(JSONValue.string))
    }
    return .object(schema)
  }

  private static func stringSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("string"),
      "description": .string(description)
    ])
  }
}
