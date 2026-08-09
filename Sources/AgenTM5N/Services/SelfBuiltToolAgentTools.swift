import Darwin
import Foundation

public enum SelfBuiltToolLanguage: String, Codable, CaseIterable, Sendable {
  case zsh
  case python3
}

public enum SelfBuiltToolParameterType: String, Codable, CaseIterable, Sendable {
  case string
  case integer
  case number
  case boolean
}

public struct SelfBuiltToolParameter: Codable, Equatable, Sendable {
  public var name: String
  public var type: SelfBuiltToolParameterType
  public var description: String
  public var required: Bool

  public init(
    name: String,
    type: SelfBuiltToolParameterType,
    description: String,
    required: Bool
  ) {
    self.name = name
    self.type = type
    self.description = description
    self.required = required
  }
}

public struct SelfBuiltToolRecord: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var description: String
  public var language: SelfBuiltToolLanguage
  public var parameters: [SelfBuiltToolParameter]
  public var source: String
  public var isEnabled: Bool
  public let createdAt: Date
  public var updatedAt: Date
  public var lastRunAt: Date?

  public init(
    id: UUID = UUID(),
    name: String,
    description: String,
    language: SelfBuiltToolLanguage,
    parameters: [SelfBuiltToolParameter],
    source: String,
    isEnabled: Bool = true,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    lastRunAt: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.language = language
    self.parameters = parameters
    self.source = source
    self.isEnabled = isEnabled
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastRunAt = lastRunAt
  }
}

public enum SelfBuiltToolError: LocalizedError {
  case invalidName
  case invalidDescription
  case invalidLanguage(String)
  case invalidParameters
  case invalidParameterName(String)
  case duplicateParameter(String)
  case sourceTooLarge
  case emptySource
  case unsafeSource(String)
  case notFound(String)
  case ambiguous(String)
  case disabled(String)
  case invalidArguments(String)
  case runtimeUnavailable(String)
  case timedOut
  case launchFailed(String)

  public var errorDescription: String? {
    switch self {
    case .invalidName:
      return "Tool-Name muss 3 bis 64 Zeichen lang sein und wird als custom_<name> gespeichert. Erlaubt sind a-z, 0-9 und _."
    case .invalidDescription:
      return "Tool-Beschreibung muss zwischen 1 und 1000 Zeichen lang sein."
    case .invalidLanguage(let language):
      return "Nicht unterstützte Tool-Sprache: \(language). Erlaubt: zsh, python3."
    case .invalidParameters:
      return "Ein selbst gebautes Tool darf maximal 16 gültige Parameter besitzen."
    case .invalidParameterName(let name):
      return "Ungültiger Tool-Parametername: \(name). Erlaubt sind a-z, 0-9 und _."
    case .duplicateParameter(let name):
      return "Tool-Parameter ist doppelt vorhanden: \(name)."
    case .sourceTooLarge:
      return "Tool-Quellcode überschreitet das Limit von 64 KiB."
    case .emptySource:
      return "Tool-Quellcode darf nicht leer sein."
    case .unsafeSource(let reason):
      return "Tool-Quellcode wurde aus Sicherheitsgründen abgelehnt: \(reason)"
    case .notFound(let query):
      return "Kein selbst gebautes Tool passt zu: \(query)"
    case .ambiguous(let query):
      return "Das selbst gebaute Tool ist nicht eindeutig: \(query)"
    case .disabled(let name):
      return "Das selbst gebaute Tool ist deaktiviert: \(name)"
    case .invalidArguments(let reason):
      return "Ungültige Argumente für das selbst gebaute Tool: \(reason)"
    case .runtimeUnavailable(let runtime):
      return "Benötigte Tool-Laufzeit ist nicht verfügbar: \(runtime)"
    case .timedOut:
      return "Das selbst gebaute Tool hat das Laufzeitlimit von 60 Sekunden überschritten."
    case .launchFailed(let reason):
      return "Das selbst gebaute Tool konnte nicht gestartet werden: \(reason)"
    }
  }
}

/// Persistent runtime library for model-authored tools.
///
/// Definitions are stored with protected POSIX permissions. Runtime source is
/// always execute-risk and gets a minimal environment without inherited Vault,
/// provider, SSH-agent, shell-profile, or user HOME credentials.
public final class SelfBuiltToolLibrary: @unchecked Sendable {
  public static let shared = SelfBuiltToolLibrary()

  private let lock = NSLock()
  private let fileURL: URL
  private var storage: [SelfBuiltToolRecord] = []

  public init(fileURL: URL? = nil) {
    self.fileURL = fileURL
      ?? AppPaths.applicationSupportDirectory.appendingPathComponent("self-built-tools.json")
    load()
  }

  public var records: [SelfBuiltToolRecord] {
    lock.lock()
    defer { lock.unlock() }
    return storage.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  public var providerDefinitions: [ProviderToolDefinition] {
    records
      .filter(\.isEnabled)
      .map(SelfBuiltToolAgentTools.providerDefinition)
  }

  public func resolve(_ query: String) throws -> SelfBuiltToolRecord {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    lock.lock()
    defer { lock.unlock() }
    let matches = storage.filter {
      $0.id.uuidString.caseInsensitiveCompare(normalized) == .orderedSame
        || $0.name.caseInsensitiveCompare(normalized) == .orderedSame
    }
    guard !matches.isEmpty else { throw SelfBuiltToolError.notFound(query) }
    guard matches.count == 1, let result = matches.first else {
      throw SelfBuiltToolError.ambiguous(query)
    }
    return result
  }

  @discardableResult
  public func createOrReplace(
    name: String,
    description: String,
    language: SelfBuiltToolLanguage,
    parameters: [SelfBuiltToolParameter],
    source: String
  ) throws -> SelfBuiltToolRecord {
    let normalizedName = try SelfBuiltToolAgentTools.normalizedToolName(name)
    let normalizedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...1_000).contains(normalizedDescription.count) else {
      throw SelfBuiltToolError.invalidDescription
    }
    try SelfBuiltToolAgentTools.validate(parameters: parameters)
    try SelfBuiltToolAgentTools.validate(source: source)

    lock.lock()
    defer { lock.unlock() }

    if let index = storage.firstIndex(where: {
      $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame
    }) {
      storage[index].description = normalizedDescription
      storage[index].language = language
      storage[index].parameters = parameters
      storage[index].source = source
      storage[index].isEnabled = true
      storage[index].updatedAt = Date()
      try saveLocked()
      return storage[index]
    }

    let record = SelfBuiltToolRecord(
      name: normalizedName,
      description: normalizedDescription,
      language: language,
      parameters: parameters,
      source: source
    )
    storage.append(record)
    try saveLocked()
    return record
  }

  @discardableResult
  public func setEnabled(_ enabled: Bool, query: String) throws -> SelfBuiltToolRecord {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    lock.lock()
    defer { lock.unlock() }
    let matches = storage.indices.filter { index in
      storage[index].id.uuidString.caseInsensitiveCompare(normalized) == .orderedSame
        || storage[index].name.caseInsensitiveCompare(normalized) == .orderedSame
    }
    guard !matches.isEmpty else { throw SelfBuiltToolError.notFound(query) }
    guard matches.count == 1, let index = matches.first else {
      throw SelfBuiltToolError.ambiguous(query)
    }
    storage[index].isEnabled = enabled
    storage[index].updatedAt = Date()
    try saveLocked()
    return storage[index]
  }

  public func delete(_ query: String) throws -> SelfBuiltToolRecord {
    let record = try resolve(query)
    lock.lock()
    defer { lock.unlock() }
    storage.removeAll { $0.id == record.id }
    try saveLocked()
    return record
  }

  public func markRun(id: UUID) throws {
    lock.lock()
    defer { lock.unlock() }
    guard let index = storage.firstIndex(where: { $0.id == id }) else { return }
    storage[index].lastRunAt = Date()
    storage[index].updatedAt = Date()
    try saveLocked()
  }

  private func load() {
    do {
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        storage = []
        return
      }
      let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      storage = try decoder.decode([SelfBuiltToolRecord].self, from: data)
    } catch {
      storage = []
      AppLogger.app.error(
        "Self-built tool library load failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func saveLocked() throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directory.path
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(storage).write(to: fileURL, options: [.atomic])
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fileURL.path
    )
  }
}

public enum SelfBuiltToolAgentTools {
  public static var definitions: [ProviderToolDefinition] {
    managementDefinitions + SelfBuiltToolLibrary.shared.providerDefinitions
  }

  public static let managementNames: Set<String> = [
    "toolsmith_list",
    "toolsmith_get",
    "toolsmith_create",
    "toolsmith_set_enabled",
    "toolsmith_delete",
    "toolsmith_run",
  ]

  public static let managementDefinitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "toolsmith_list",
      description: "List persistent runtime tools previously built by AgenTM5N. Returns metadata and parameter schemas, not source code.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "toolsmith_get",
      description: "Inspect one AgenTM5N self-built runtime tool by exact name or UUID, including its source code. Never place credentials or Vault secret values in tool source.",
      parameters: objectSchema(
        required: ["tool"],
        properties: ["tool": stringSchema("Exact custom tool name or UUID.")]
      )
    ),
    ProviderToolDefinition(
      name: "toolsmith_create",
      description: "Create or replace a persistent AgenTM5N runtime tool. Tool names are normalized to custom_<name>. Source may be zsh or python3 and must read inputs from AGENTM5N_ARGS_FILE or AGENTM5N_ARG_<NAME>. Never embed passwords, tokens, API keys, private keys or other secrets in source. Runtime execution is always execute-risk.",
      parameters: objectSchema(
        required: ["name", "description", "language", "source"],
        properties: [
          "name": stringSchema("Tool name. custom_ is added automatically when missing."),
          "description": stringSchema("Precise description telling future models when to call the tool."),
          "language": stringSchema("zsh or python3."),
          "parameters": parameterArraySchema(),
          "parameters_json": stringSchema("Optional JSON array alternative for Foundation Models adapters."),
          "source": stringSchema("Complete zsh or python3 source. Print the final tool result to stdout."),
        ]
      )
    ),
    ProviderToolDefinition(
      name: "toolsmith_set_enabled",
      description: "Enable or disable one persistent self-built AgenTM5N runtime tool without deleting it.",
      parameters: objectSchema(
        required: ["tool", "enabled"],
        properties: [
          "tool": stringSchema("Exact custom tool name or UUID."),
          "enabled": boolSchema("true enables the tool; false disables it."),
        ]
      )
    ),
    ProviderToolDefinition(
      name: "toolsmith_delete",
      description: "Delete one persistent self-built AgenTM5N runtime tool by exact name or UUID.",
      parameters: objectSchema(
        required: ["tool"],
        properties: ["tool": stringSchema("Exact custom tool name or UUID.")]
      )
    ),
    ProviderToolDefinition(
      name: "toolsmith_run",
      description: "Run one persistent self-built AgenTM5N tool. Prefer calling the custom tool directly when the provider exposes its generated function definition. Self-built execution always uses execute-risk and requires the active AgenTM5N permission policy.",
      parameters: objectSchema(
        required: ["tool"],
        properties: [
          "tool": stringSchema("Exact custom tool name or UUID."),
          "arguments": .object([
            "type": .string("object"),
            "description": .string("Arguments matching the custom tool parameter schema."),
            "additionalProperties": .bool(true),
          ]),
          "arguments_json": stringSchema("Optional JSON object alternative for Foundation Models adapters."),
        ]
      )
    ),
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    managementNames.contains(call.function.name)
      || SelfBuiltToolLibrary.shared.records.contains {
        $0.name.caseInsensitiveCompare(call.function.name) == .orderedSame
      }
  }

  public static func isDynamicToolName(_ name: String) -> Bool {
    SelfBuiltToolLibrary.shared.records.contains {
      $0.name.caseInsensitiveCompare(name) == .orderedSame
    }
  }

  public static func risk(for call: ProviderToolCall) -> ToolRisk {
    switch call.function.name {
    case "toolsmith_list", "toolsmith_get":
      return .read
    case "toolsmith_create", "toolsmith_set_enabled", "toolsmith_delete":
      return .write
    case "toolsmith_run":
      return .execute
    default:
      return .execute
    }
  }

  public static func summary(for call: ProviderToolCall) -> String {
    let values = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      let lower = key.lowercased()
      if lower == "source" || lower == "arguments" || lower == "arguments_json"
        || lower == "parameters" || lower == "parameters_json"
      {
        return "\(key): <\(value.compactDescription.utf8.count) Bytes>"
      }
      let rendered = value.compactDescription
      return "\(key): \(rendered.count > 160 ? String(rendered.prefix(160)) + "…" : rendered)"
    }
    let suffix = risk(for: call) == .execute
      ? " — selbst erzeugter Runtime-Code / explizite Ausführungsfreigabe"
      : ""
    return (values.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(values.joined(separator: ", "))") + suffix
  }

  public static func execute(
    call: ProviderToolCall,
    library: SelfBuiltToolLibrary = .shared
  ) -> ToolExecutionResult {
    do {
      switch call.function.name {
      case "toolsmith_list":
        return encoded(library.records.map(ListDescriptor.init))

      case "toolsmith_get":
        return encoded(GetDescriptor(try library.resolve(try requiredString("tool", in: call))))

      case "toolsmith_create":
        let languageText = try requiredString("language", in: call).lowercased()
        guard let language = SelfBuiltToolLanguage(rawValue: languageText) else {
          throw SelfBuiltToolError.invalidLanguage(languageText)
        }
        let parameters = try parseParameters(call)
        let record = try library.createOrReplace(
          name: try requiredString("name", in: call),
          description: try requiredString("description", in: call),
          language: language,
          parameters: parameters,
          source: try requiredStringAllowingNewlines("source", in: call)
        )
        return encoded(MutationDescriptor(status: "saved", tool: record))

      case "toolsmith_set_enabled":
        guard let enabled = call.function.arguments["enabled"]?.boolValue else {
          throw AgentRuntimeError.missingArgument(tool: call.function.name, name: "enabled")
        }
        return encoded(
          MutationDescriptor(
            status: enabled ? "enabled" : "disabled",
            tool: try library.setEnabled(
              enabled,
              query: try requiredString("tool", in: call)
            )
          )
        )

      case "toolsmith_delete":
        return encoded(
          MutationDescriptor(
            status: "deleted",
            tool: try library.delete(try requiredString("tool", in: call))
          )
        )

      case "toolsmith_run":
        let record = try library.resolve(try requiredString("tool", in: call))
        let arguments = try parseArguments(call)
        return try execute(record: record, arguments: arguments, library: library)

      default:
        let record = try library.resolve(call.function.name)
        return try execute(record: record, arguments: call.function.arguments, library: library)
      }
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  public static func providerDefinition(
    _ record: SelfBuiltToolRecord
  ) -> ProviderToolDefinition {
    var properties: [String: JSONValue] = [:]
    var required: [String] = []
    for parameter in record.parameters {
      properties[parameter.name] = parameterSchema(parameter)
      if parameter.required { required.append(parameter.name) }
    }
    return ProviderToolDefinition(
      name: record.name,
      description: "[AgenTM5N self-built tool] \(record.description)",
      parameters: objectSchema(required: required, properties: properties)
    )
  }

  public static func normalizedToolName(_ value: String) throws -> String {
    var name = value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "-", with: "_")
      .replacingOccurrences(of: " ", with: "_")
    if !name.hasPrefix("custom_") {
      name = "custom_" + name
    }
    guard (3...64).contains(name.count),
      name.first?.isLetter == true,
      name.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "_" })
    else {
      throw SelfBuiltToolError.invalidName
    }
    return name
  }

  public static func validate(parameters: [SelfBuiltToolParameter]) throws {
    guard parameters.count <= 16 else { throw SelfBuiltToolError.invalidParameters }
    var seen: Set<String> = []
    for parameter in parameters {
      let name = parameter.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty,
        name.count <= 32,
        name.first?.isLetter == true,
        name.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "_" })
      else {
        throw SelfBuiltToolError.invalidParameterName(parameter.name)
      }
      guard seen.insert(name).inserted else {
        throw SelfBuiltToolError.duplicateParameter(name)
      }
      guard parameter.description.count <= 500 else {
        throw SelfBuiltToolError.invalidParameters
      }
    }
  }

  public static func validate(source: String) throws {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw SelfBuiltToolError.emptySource }
    guard source.utf8.count <= 64 * 1024 else { throw SelfBuiltToolError.sourceTooLarge }
    guard !source.contains("\0") else {
      throw SelfBuiltToolError.unsafeSource("NUL-Bytes sind nicht erlaubt.")
    }
    let lower = source.lowercased()
    let blockedFragments = [
      "-----begin private key-----",
      "-----begin rsa private key-----",
      "-----begin openssh private key-----",
      "security find-generic-password",
      "security find-internet-password",
      "security dump-keychain",
    ]
    if let blocked = blockedFragments.first(where: { lower.contains($0) }) {
      throw SelfBuiltToolError.unsafeSource("gesperrtes Credential-Muster: \(blocked)")
    }
  }

  private static func execute(
    record: SelfBuiltToolRecord,
    arguments: [String: JSONValue],
    library: SelfBuiltToolLibrary
  ) throws -> ToolExecutionResult {
    guard record.isEnabled else { throw SelfBuiltToolError.disabled(record.name) }
    try validate(arguments: arguments, parameters: record.parameters)

    let workspace = try currentWorkspaceURL()
    let runtime = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentm5n-tool-\(UUID().uuidString)", isDirectory: true)
    let runtimeHome = runtime.appendingPathComponent("home", isDirectory: true)
    let runtimeTmp = runtime.appendingPathComponent("tmp", isDirectory: true)
    try FileManager.default.createDirectory(
      at: runtimeHome,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.createDirectory(
      at: runtimeTmp,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: runtime) }

    let argsURL = runtime.appendingPathComponent("arguments.json")
    let stdoutURL = runtime.appendingPathComponent("stdout.txt")
    let stderrURL = runtime.appendingPathComponent("stderr.txt")
    let scriptURL = runtime.appendingPathComponent(
      record.language == .zsh ? "tool.zsh" : "tool.py"
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(JSONValue.object(arguments)).write(to: argsURL, options: [.atomic])
    let scriptData: Data
    if record.language == .zsh {
      scriptData = Data(("#!/bin/zsh\nset -euo pipefail\n" + record.source + "\n").utf8)
    } else {
      scriptData = Data(record.source.utf8)
    }
    try scriptData.write(to: scriptURL, options: [.atomic])
    FileManager.default.createFile(atPath: stdoutURL.path, contents: Data())
    FileManager.default.createFile(atPath: stderrURL.path, contents: Data())
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: argsURL.path)
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stdoutURL.path)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stderrURL.path)

    let process = Process()
    switch record.language {
    case .zsh:
      process.executableURL = URL(fileURLWithPath: "/bin/zsh")
      process.arguments = [scriptURL.path]
    case .python3:
      let python = "/usr/bin/python3"
      guard FileManager.default.isExecutableFile(atPath: python) else {
        throw SelfBuiltToolError.runtimeUnavailable(python)
      }
      process.executableURL = URL(fileURLWithPath: python)
      process.arguments = [scriptURL.path]
    }
    process.currentDirectoryURL = workspace

    var environment: [String: String] = [
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      "HOME": runtimeHome.path,
      "TMPDIR": runtimeTmp.path + "/",
      "XDG_CONFIG_HOME": runtimeHome.appendingPathComponent(".config").path,
      "XDG_CACHE_HOME": runtimeHome.appendingPathComponent(".cache").path,
      "PYTHONNOUSERSITE": "1",
      "LANG": "en_US.UTF-8",
      "LC_ALL": "en_US.UTF-8",
      "AGENTM5N_TOOL_NAME": record.name,
      "AGENTM5N_WORKSPACE": workspace.path,
      "AGENTM5N_ARGS_FILE": argsURL.path,
    ]
    for (name, value) in arguments {
      environment["AGENTM5N_ARG_\(environmentName(name))"] = environmentValue(value)
    }
    process.environment = environment

    guard let stdoutHandle = FileHandle(forWritingAtPath: stdoutURL.path),
      let stderrHandle = FileHandle(forWritingAtPath: stderrURL.path)
    else {
      throw SelfBuiltToolError.launchFailed("Temporäre Ausgabedateien konnten nicht geöffnet werden.")
    }
    defer {
      stdoutHandle.closeFile()
      stderrHandle.closeFile()
    }
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle

    do {
      try process.run()
    } catch {
      throw SelfBuiltToolError.launchFailed(error.localizedDescription)
    }

    let deadline = Date().addingTimeInterval(60)
    while process.isRunning {
      if Date() >= deadline {
        process.terminate()
        usleep(250_000)
        if process.isRunning {
          Darwin.kill(process.processIdentifier, SIGKILL)
        }
        throw SelfBuiltToolError.timedOut
      }
      usleep(50_000)
    }

    stdoutHandle.synchronizeFile()
    stderrHandle.synchronizeFile()
    let stdout = readBoundedText(stdoutURL, limit: 192 * 1024)
    let stderr = readBoundedText(stderrURL, limit: 64 * 1024)
    try? library.markRun(id: record.id)

    let combined: String
    if stderr.isEmpty {
      combined = stdout
    } else if stdout.isEmpty {
      combined = "STDERR:\n\(stderr)"
    } else {
      combined = "\(stdout)\n\nSTDERR:\n\(stderr)"
    }
    return ToolExecutionResult(
      success: process.terminationStatus == 0,
      output: combined.isEmpty
        ? "Tool beendet mit Exit-Code \(process.terminationStatus)."
        : String(combined.prefix(256 * 1024))
    )
  }

  private static func validate(
    arguments: [String: JSONValue],
    parameters: [SelfBuiltToolParameter]
  ) throws {
    let known = Set(parameters.map(\.name))
    let unknown = arguments.keys.filter { !known.contains($0) }
    guard unknown.isEmpty else {
      throw SelfBuiltToolError.invalidArguments(
        "Unbekannte Parameter: \(unknown.sorted().joined(separator: ", "))"
      )
    }
    for parameter in parameters {
      guard let value = arguments[parameter.name] else {
        if parameter.required {
          throw SelfBuiltToolError.invalidArguments(
            "Pflichtparameter fehlt: \(parameter.name)"
          )
        }
        continue
      }
      let valid: Bool
      switch (parameter.type, value) {
      case (.string, .string), (.integer, .number), (.number, .number), (.boolean, .bool):
        valid = true
      default:
        valid = false
      }
      guard valid else {
        throw SelfBuiltToolError.invalidArguments(
          "Parameter \(parameter.name) erwartet \(parameter.type.rawValue)."
        )
      }
      if parameter.type == .integer, case .number(let number) = value,
        number.rounded() != number
      {
        throw SelfBuiltToolError.invalidArguments(
          "Parameter \(parameter.name) erwartet eine ganze Zahl."
        )
      }
    }
  }

  private static func parseParameters(_ call: ProviderToolCall) throws -> [SelfBuiltToolParameter] {
    let value: JSONValue?
    if let direct = call.function.arguments["parameters"] {
      value = direct
    } else if let text = call.function.arguments["parameters_json"]?.stringValue,
      let data = text.data(using: .utf8)
    {
      value = try JSONDecoder().decode(JSONValue.self, from: data)
    } else {
      value = .array([])
    }

    guard case .array(let items) = value else {
      throw SelfBuiltToolError.invalidParameters
    }
    let parameters = try items.map { item -> SelfBuiltToolParameter in
      guard case .object(let object) = item,
        let name = object["name"]?.stringValue,
        let typeText = object["type"]?.stringValue,
        let type = SelfBuiltToolParameterType(rawValue: typeText.lowercased())
      else {
        throw SelfBuiltToolError.invalidParameters
      }
      return SelfBuiltToolParameter(
        name: name,
        type: type,
        description: object["description"]?.stringValue ?? "",
        required: object["required"]?.boolValue ?? false
      )
    }
    try validate(parameters: parameters)
    return parameters
  }

  private static func parseArguments(_ call: ProviderToolCall) throws -> [String: JSONValue] {
    if case .object(let arguments) = call.function.arguments["arguments"] {
      return arguments
    }
    if let text = call.function.arguments["arguments_json"]?.stringValue,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      guard let data = text.data(using: .utf8),
        case .object(let arguments) = try JSONDecoder().decode(JSONValue.self, from: data)
      else {
        throw SelfBuiltToolError.invalidArguments("arguments_json muss ein JSON-Objekt sein.")
      }
      return arguments
    }
    return [:]
  }

  private static func currentWorkspaceURL() throws -> URL {
    let data = try Data(contentsOf: AppPaths.configurationFile)
    let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
    let expanded = NSString(string: configuration.workspacePath).expandingTildeInPath
    let resolved = URL(fileURLWithPath: expanded, isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw AgentRuntimeError.invalidWorkspace(configuration.workspacePath)
    }
    return resolved
  }

  private static func environmentName(_ value: String) -> String {
    value.uppercased().map { character in
      character.isLetter || character.isNumber ? String(character) : "_"
    }.joined()
  }

  private static func environmentValue(_ value: JSONValue) -> String {
    switch value {
    case .string(let text): return text
    case .number(let number): return String(number)
    case .bool(let flag): return flag ? "true" : "false"
    default: return value.compactDescription
    }
  }

  private static func readBoundedText(_ url: URL, limit: Int) -> String {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
    defer { handle.closeFile() }
    let data = handle.readData(ofLength: limit)
    return String(decoding: data, as: UTF8.self)
  }

  private struct ListDescriptor: Encodable {
    let id: String
    let name: String
    let description: String
    let language: String
    let parameters: [SelfBuiltToolParameter]
    let enabled: Bool
    let sourceBytes: Int
    let createdAt: Date
    let updatedAt: Date
    let lastRunAt: Date?

    init(_ record: SelfBuiltToolRecord) {
      id = record.id.uuidString
      name = record.name
      description = record.description
      language = record.language.rawValue
      parameters = record.parameters
      enabled = record.isEnabled
      sourceBytes = record.source.utf8.count
      createdAt = record.createdAt
      updatedAt = record.updatedAt
      lastRunAt = record.lastRunAt
    }
  }

  private struct GetDescriptor: Encodable {
    let id: String
    let name: String
    let description: String
    let language: String
    let parameters: [SelfBuiltToolParameter]
    let source: String
    let enabled: Bool
    let createdAt: Date
    let updatedAt: Date
    let lastRunAt: Date?

    init(_ record: SelfBuiltToolRecord) {
      id = record.id.uuidString
      name = record.name
      description = record.description
      language = record.language.rawValue
      parameters = record.parameters
      source = record.source
      enabled = record.isEnabled
      createdAt = record.createdAt
      updatedAt = record.updatedAt
      lastRunAt = record.lastRunAt
    }
  }

  private struct MutationDescriptor: Encodable {
    let status: String
    let tool: ListDescriptor

    init(status: String, tool: SelfBuiltToolRecord) {
      self.status = status
      self.tool = ListDescriptor(tool)
    }
  }

  private static func requiredString(_ name: String, in call: ProviderToolCall) throws -> String {
    guard let value = call.function.arguments[name]?.stringValue?
      .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else {
      throw AgentRuntimeError.missingArgument(tool: call.function.name, name: name)
    }
    return value
  }

  private static func requiredStringAllowingNewlines(
    _ name: String,
    in call: ProviderToolCall
  ) throws -> String {
    guard let value = call.function.arguments[name]?.stringValue,
      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw AgentRuntimeError.missingArgument(tool: call.function.name, name: name)
    }
    return value
  }

  private static func encoded<T: Encodable>(_ value: T) -> ToolExecutionResult {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(value)
      return ToolExecutionResult(success: true, output: String(decoding: data, as: UTF8.self))
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private static func parameterArraySchema() -> JSONValue {
    .object([
      "type": .string("array"),
      "description": .string("Optional tool parameters, maximum 16."),
      "items": .object([
        "type": .string("object"),
        "required": .array([.string("name"), .string("type"), .string("description"), .string("required")]),
        "properties": .object([
          "name": stringSchema("Lowercase parameter name."),
          "type": stringSchema("string, integer, number, or boolean."),
          "description": stringSchema("What the parameter means."),
          "required": .object(["type": .string("boolean")]),
        ]),
        "additionalProperties": .bool(false),
      ]),
    ])
  }

  private static func parameterSchema(_ parameter: SelfBuiltToolParameter) -> JSONValue {
    let type: String
    switch parameter.type {
    case .string: type = "string"
    case .integer: type = "integer"
    case .number: type = "number"
    case .boolean: type = "boolean"
    }
    return .object([
      "type": .string(type),
      "description": .string(parameter.description),
    ])
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
