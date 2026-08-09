import Foundation
import SwiftUI

public struct AgentWorkflowStep: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var toolName: String
  public var arguments: [String: JSONValue]

  public init(
    id: UUID = UUID(),
    toolName: String,
    arguments: [String: JSONValue]
  ) {
    self.id = id
    self.toolName = toolName
    self.arguments = arguments
  }
}

public struct AgentWorkflow: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var purpose: String
  public var steps: [AgentWorkflowStep]
  public var isEnabled: Bool
  public let createdAt: Date
  public var updatedAt: Date
  public var lastRunAt: Date?

  public init(
    id: UUID = UUID(),
    name: String,
    purpose: String,
    steps: [AgentWorkflowStep],
    isEnabled: Bool = true,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    lastRunAt: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.purpose = purpose
    self.steps = steps
    self.isEnabled = isEnabled
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastRunAt = lastRunAt
  }
}

public enum AgentWorkflowError: LocalizedError {
  case invalidName
  case invalidPurpose
  case invalidSteps
  case unknownTool(String)
  case nestedWorkflow(String)
  case unsafeSecretArgument(String)
  case notFound(String)
  case ambiguous(String)
  case disabled(String)

  public var errorDescription: String? {
    switch self {
    case .invalidName:
      return "Workflow-Name muss zwischen 1 und 100 Zeichen lang sein."
    case .invalidPurpose:
      return "Workflow-Zweck muss zwischen 1 und 600 Zeichen lang sein."
    case .invalidSteps:
      return "Ein Workflow benötigt 1 bis 20 gültige Schritte."
    case .unknownTool(let name):
      return "Unbekanntes Workflow-Werkzeug: \(name)"
    case .nestedWorkflow(let name):
      return "Workflow-Schritte dürfen keine Workflow-Verwaltungswerkzeuge aufrufen: \(name)"
    case .unsafeSecretArgument(let key):
      return "Workflow speichert keine Secret-Werte. Verwende secret_ref statt des Arguments \(key)."
    case .notFound(let query):
      return "Kein Workflow passt zu: \(query)"
    case .ambiguous(let query):
      return "Der Workflow ist nicht eindeutig: \(query)"
    case .disabled(let name):
      return "Der Workflow ist deaktiviert: \(name)"
    }
  }
}

@MainActor
public final class AgentWorkflowLibrary: ObservableObject {
  public static let shared = AgentWorkflowLibrary()

  @Published public private(set) var workflows: [AgentWorkflow] = []
  private let fileURL: URL

  public init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? Self.defaultFileURL()
    load()
  }

  public func resolve(_ query: String) throws -> AgentWorkflow {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = workflows.filter {
      $0.id.uuidString.caseInsensitiveCompare(normalized) == .orderedSame
        || $0.name.caseInsensitiveCompare(normalized) == .orderedSame
    }
    guard !matches.isEmpty else { throw AgentWorkflowError.notFound(query) }
    guard matches.count == 1, let match = matches.first else {
      throw AgentWorkflowError.ambiguous(query)
    }
    return match
  }

  @discardableResult
  public func create(
    name: String,
    purpose: String,
    steps: [AgentWorkflowStep]
  ) throws -> AgentWorkflow {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...100).contains(normalizedName.count) else {
      throw AgentWorkflowError.invalidName
    }
    guard (1...600).contains(normalizedPurpose.count) else {
      throw AgentWorkflowError.invalidPurpose
    }
    try validateSteps(steps)

    if let existing = workflows.first(where: {
      $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame
    }), let index = workflows.firstIndex(where: { $0.id == existing.id }) {
      workflows[index].purpose = normalizedPurpose
      workflows[index].steps = steps
      // Replacing workflow content must not silently re-enable a workflow that
      // the user deliberately disabled earlier.
      workflows[index].updatedAt = Date()
      let result = workflows[index]
      sort()
      try save()
      return result
    }

    let workflow = AgentWorkflow(
      name: normalizedName,
      purpose: normalizedPurpose,
      steps: steps
    )
    workflows.append(workflow)
    sort()
    try save()
    return workflow
  }

  public func delete(_ query: String) throws -> AgentWorkflow {
    let workflow = try resolve(query)
    workflows.removeAll { $0.id == workflow.id }
    try save()
    return workflow
  }

  public func markRun(id: UUID) throws {
    guard let index = workflows.firstIndex(where: { $0.id == id }) else { return }
    workflows[index].lastRunAt = Date()
    workflows[index].updatedAt = Date()
    try save()
  }

  private func validateSteps(_ steps: [AgentWorkflowStep]) throws {
    guard (1...20).contains(steps.count) else {
      throw AgentWorkflowError.invalidSteps
    }
    for step in steps {
      guard AgentToolRegistry.allDefinitions.contains(where: {
        $0.function.name == step.toolName
      }) else {
        throw AgentWorkflowError.unknownTool(step.toolName)
      }
      if step.toolName.hasPrefix("workflow_") {
        throw AgentWorkflowError.nestedWorkflow(step.toolName)
      }
      for key in step.arguments.keys {
        let normalized = key.lowercased()
        if normalized == "secret_ref" { continue }
        if normalized.contains("password")
          || normalized.contains("private_key")
          || normalized.contains("passphrase")
          || normalized.contains("api_key")
          || normalized == "token"
          || normalized == "secret"
        {
          throw AgentWorkflowError.unsafeSecretArgument(key)
        }
      }
    }
  }

  private func load() {
    do {
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        workflows = []
        return
      }
      let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      workflows = try decoder.decode([AgentWorkflow].self, from: data)
      sort()
    } catch {
      workflows = []
      AppLogger.app.error(
        "Workflow library load failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func save() throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(workflows).write(to: fileURL, options: [.atomic])
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fileURL.path
    )
  }

  private func sort() {
    workflows.sort {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  private static func defaultFileURL() -> URL {
    AppPaths.applicationSupportDirectory.appendingPathComponent("workflows.json")
  }
}

public enum WorkflowAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "workflow_list",
      description: "List reusable persistent AgenTM5N workflows. Returns step tool names and metadata but never resolves secret values.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "workflow_create",
      description: "Create or replace a reusable AgenTM5N workflow composed of provider-neutral tool steps. Store only secret_ref labels, never secret values. Replacing an existing workflow preserves its enabled/disabled state.",
      parameters: objectSchema(
        required: ["name", "purpose", "steps"],
        properties: [
          "name": stringSchema("Workflow name."),
          "purpose": stringSchema("Short description of what the workflow accomplishes."),
          "steps": .object([
            "type": .string("array"),
            "description": .string("Ordered workflow steps, maximum 20."),
            "items": .object([
              "type": .string("object"),
              "required": .array([.string("tool"), .string("arguments")]),
              "properties": .object([
                "tool": stringSchema("Registered AgenTM5N tool name."),
                "arguments": .object([
                  "type": .string("object"),
                  "description": .string("Tool arguments. Use secret_ref labels instead of secret values."),
                  "additionalProperties": .bool(true),
                ]),
              ]),
              "additionalProperties": .bool(false),
            ]),
          ])
        ]
      )
    ),
    ProviderToolDefinition(
      name: "workflow_delete",
      description: "Delete a persistent workflow by exact name or UUID.",
      parameters: objectSchema(
        required: ["workflow"],
        properties: ["workflow": stringSchema("Exact workflow name or UUID.")]
      )
    ),
    ProviderToolDefinition(
      name: "workflow_run",
      description: "Run one enabled persistent workflow in order. The workflow run receives one central execution approval and records bounded per-step results in its audit output.",
      parameters: objectSchema(
        required: ["workflow"],
        properties: ["workflow": stringSchema("Exact workflow name or UUID.")]
      )
    )
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for call: ProviderToolCall) -> ToolRisk {
    switch call.function.name {
    case "workflow_list": .read
    case "workflow_create", "workflow_delete": .write
    case "workflow_run": .execute
    default: .execute
    }
  }

  public static func summary(for call: ProviderToolCall) -> String {
    let values = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      if key == "steps" { return "steps: <\(value.compactDescription.utf8.count) Bytes>" }
      let rendered = value.compactDescription
      return "\(key): \(rendered.count > 180 ? String(rendered.prefix(180)) + "…" : rendered)"
    }
    return values.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(values.joined(separator: ", "))"
  }

  public static func parseSteps(_ value: JSONValue?) throws -> [AgentWorkflowStep] {
    guard case .array(let items) = value else {
      throw AgentWorkflowError.invalidSteps
    }
    return try items.map { item in
      guard case .object(let object) = item,
        let tool = object["tool"]?.stringValue,
        case .object(let arguments) = object["arguments"]
      else {
        throw AgentWorkflowError.invalidSteps
      }
      return AgentWorkflowStep(toolName: tool, arguments: arguments)
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