import Foundation

public enum AgentRuntimeError: LocalizedError {
  case missingArgument(tool: String, name: String)
  case invalidWorkspace(String)
  case pathOutsideWorkspace(String)
  case unreadableTextFile(String)
  case inputTooLarge(limit: Int)
  case commandBlocked(String)
  case commandLaunchFailed(String)
  case unsupportedTool(String)

  public var errorDescription: String? {
    switch self {
    case .missingArgument(let tool, let name):
      "Werkzeug \(tool) benötigt das Argument \(name)."
    case .invalidWorkspace(let path):
      "Der konfigurierte Workspace ist ungültig oder kein Verzeichnis: \(path)"
    case .pathOutsideWorkspace(let path):
      "Der Pfad liegt außerhalb des freigegebenen Workspace: \(path)"
    case .unreadableTextFile(let path):
      "Die Datei ist nicht als UTF-8-Text lesbar: \(path)"
    case .inputTooLarge(let limit):
      "Die Eingabe überschreitet das erlaubte Limit von \(limit) Bytes."
    case .commandBlocked(let command):
      "Das Kommando wurde durch die Workspace-Sicherheitsregel blockiert: \(command)"
    case .commandLaunchFailed(let reason):
      "Das Kommando konnte nicht gestartet werden: \(reason)"
    case .unsupportedTool(let name):
      "Unbekanntes Werkzeug: \(name)"
    }
  }
}

public actor AgentRuntime {
  public static let toolDefinitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "list_directory",
      description: "List files and directories in a path. Paths are relative to the configured workspace unless Full Access is enabled.",
      parameters: objectSchema(
        properties: [
          "path": stringSchema("Relative or absolute directory path. Defaults to the workspace root.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "read_file",
      description: "Read a UTF-8 text file. Use this before editing an existing file.",
      parameters: objectSchema(
        required: ["path"],
        properties: [
          "path": stringSchema("Relative or absolute file path.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "write_file",
      description: "Create or replace a UTF-8 text file. Parent directories may be created.",
      parameters: objectSchema(
        required: ["path", "content"],
        properties: [
          "path": stringSchema("Relative or absolute destination file path."),
          "content": stringSchema("Complete UTF-8 file content."),
          "create_directories": boolSchema("Create missing parent directories. Defaults to true.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "run_command",
      description: "Run a zsh command in the configured workspace and return stdout, stderr and exit status.",
      parameters: objectSchema(
        required: ["command"],
        properties: [
          "command": stringSchema("Shell command to execute.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "git_status",
      description: "Return the concise Git status for the configured workspace.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "git_diff",
      description: "Return the Git diff for the configured workspace.",
      parameters: objectSchema(
        properties: [
          "staged": boolSchema("Return the staged diff instead of the working-tree diff.")
        ]
      )
    ),
  ]

  private static let maxReadBytes = 512 * 1024
  private static let maxWriteBytes = 1 * 1024 * 1024
  private static let maxOutputBytes = 256 * 1024
  private static let commandTimeout: TimeInterval = 120

  public init() {}

  public func risk(for call: ProviderToolCall) -> ToolRisk {
    switch call.function.name {
    case "list_directory", "read_file", "git_status", "git_diff":
      .read
    case "write_file":
      .write
    case "run_command":
      .execute
    default:
      .execute
    }
  }

  public func summary(for call: ProviderToolCall) -> String {
    let arguments = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      let rendered: String
      if key == "content" {
        rendered = "<\(value.compactDescription.utf8.count) Bytes>"
      } else {
        rendered = value.compactDescription
      }
      return "\(key): \(rendered)"
    }
    return arguments.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(arguments.joined(separator: ", "))"
  }

  public func execute(
    call: ProviderToolCall,
    workspacePath: String,
    permissionMode: AgentPermissionMode
  ) async -> ToolExecutionResult {
    do {
      let workspace = try makeWorkspaceURL(workspacePath)
      switch call.function.name {
      case "list_directory":
        return try listDirectory(
          call: call,
          workspace: workspace,
          allowOutsideWorkspace: permissionMode == .fullAccess
        )
      case "read_file":
        return try readFile(
          call: call,
          workspace: workspace,
          allowOutsideWorkspace: permissionMode == .fullAccess
        )
      case "write_file":
        return try writeFile(
          call: call,
          workspace: workspace,
          allowOutsideWorkspace: permissionMode == .fullAccess
        )
      case "run_command":
        let command = try requiredString("command", in: call)
        if permissionMode != .fullAccess, isBlockedWorkspaceCommand(command) {
          throw AgentRuntimeError.commandBlocked(command)
        }
        return try await runCommand(command, workspace: workspace)
      case "git_status":
        return try await runCommand(
          "git status --short --branch",
          workspace: workspace
        )
      case "git_diff":
        let staged = call.function.arguments["staged"]?.boolValue ?? false
        return try await runCommand(
          staged ? "git diff --cached --no-ext-diff" : "git diff --no-ext-diff",
          workspace: workspace
        )
      default:
        throw AgentRuntimeError.unsupportedTool(call.function.name)
      }
    } catch {
      return ToolExecutionResult(
        success: false,
        output: error.localizedDescription
      )
    }
  }

  private func listDirectory(
    call: ProviderToolCall,
    workspace: URL,
    allowOutsideWorkspace: Bool
  ) throws -> ToolExecutionResult {
    let path = call.function.arguments["path"]?.stringValue ?? "."
    let directory = try resolveExistingPath(
      path,
      workspace: workspace,
      allowOutsideWorkspace: allowOutsideWorkspace
    )
    let keys: Set<URLResourceKey> = [
      .isDirectoryKey,
      .fileSizeKey,
      .contentModificationDateKey,
    ]
    let entries = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: Array(keys),
      options: [.skipsHiddenFiles]
    )
    let lines = try entries
      .sorted {
        $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
          == .orderedAscending
      }
      .prefix(500)
      .map { url -> String in
        let values = try url.resourceValues(forKeys: keys)
        let type = values.isDirectory == true ? "d" : "f"
        let size = values.fileSize.map(String.init) ?? "-"
        return "\(type)\t\(size)\t\(url.lastPathComponent)"
      }

    return ToolExecutionResult(
      success: true,
      output: lines.isEmpty ? "(leer)" : lines.joined(separator: "\n")
    )
  }

  private func readFile(
    call: ProviderToolCall,
    workspace: URL,
    allowOutsideWorkspace: Bool
  ) throws -> ToolExecutionResult {
    let path = try requiredString("path", in: call)
    let file = try resolveExistingPath(
      path,
      workspace: workspace,
      allowOutsideWorkspace: allowOutsideWorkspace
    )
    let data = try Data(contentsOf: file, options: [.mappedIfSafe])
    guard data.count <= Self.maxReadBytes else {
      throw AgentRuntimeError.inputTooLarge(limit: Self.maxReadBytes)
    }
    guard let text = String(data: data, encoding: .utf8) else {
      throw AgentRuntimeError.unreadableTextFile(file.path)
    }
    return ToolExecutionResult(success: true, output: text)
  }

  private func writeFile(
    call: ProviderToolCall,
    workspace: URL,
    allowOutsideWorkspace: Bool
  ) throws -> ToolExecutionResult {
    let path = try requiredString("path", in: call)
    let content = try requiredString("content", in: call)
    guard content.utf8.count <= Self.maxWriteBytes else {
      throw AgentRuntimeError.inputTooLarge(limit: Self.maxWriteBytes)
    }

    let file = try resolveDestinationPath(
      path,
      workspace: workspace,
      allowOutsideWorkspace: allowOutsideWorkspace
    )
    let createDirectories = call.function.arguments["create_directories"]?.boolValue ?? true
    if createDirectories {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
    }
    guard let data = content.data(using: .utf8) else {
      throw AgentRuntimeError.unreadableTextFile(path)
    }
    try data.write(to: file, options: [.atomic])
    return ToolExecutionResult(
      success: true,
      output: "Geschrieben: \(file.path) (\(data.count) Bytes)"
    )
  }

  private func runCommand(
    _ command: String,
    workspace: URL
  ) async throws -> ToolExecutionResult {
    guard command.utf8.count <= 16 * 1024 else {
      throw AgentRuntimeError.inputTooLarge(limit: 16 * 1024)
    }

    try AppPaths.ensureDirectories()
    let id = UUID().uuidString
    let stdoutURL = AppPaths.runtimeDirectory.appendingPathComponent("\(id).stdout")
    let stderrURL = AppPaths.runtimeDirectory.appendingPathComponent("\(id).stderr")
    _ = FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
    _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

    defer {
      try? FileManager.default.removeItem(at: stdoutURL)
      try? FileManager.default.removeItem(at: stderrURL)
    }

    let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
    let stderrHandle = try FileHandle(forWritingTo: stderrURL)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", command]
    process.currentDirectoryURL = workspace
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle

    let waitState = ProcessWaitState()
    let processReference = ProcessReference(process)
    let outcome = await withCheckedContinuation {
      (continuation: CheckedContinuation<ProcessOutcome, Never>) in
      process.terminationHandler = { terminatedProcess in
        let state = waitState.finish()
        guard state.shouldResume else { return }
        continuation.resume(
          returning: .terminated(
            exitCode: terminatedProcess.terminationStatus,
            timedOut: state.timedOut
          )
        )
      }

      do {
        try process.run()
      } catch {
        let state = waitState.finish()
        guard state.shouldResume else { return }
        continuation.resume(
          returning: .launchFailed(error.localizedDescription)
        )
        return
      }

      DispatchQueue.global(qos: .utility).asyncAfter(
        deadline: .now() + Self.commandTimeout
      ) {
        let runningProcess = processReference.process
        guard waitState.markTimedOutIfRunning(), runningProcess.isRunning else {
          return
        }
        runningProcess.terminate()
      }
    }

    try? stdoutHandle.close()
    try? stderrHandle.close()

    let exitCode: Int32
    let timedOut: Bool
    switch outcome {
    case .terminated(let status, let didTimeOut):
      exitCode = status
      timedOut = didTimeOut
    case .launchFailed(let reason):
      throw AgentRuntimeError.commandLaunchFailed(reason)
    }

    let stdout = try readLimitedText(from: stdoutURL)
    let stderr = try readLimitedText(from: stderrURL)
    var sections: [String] = []
    if !stdout.isEmpty {
      sections.append("STDOUT:\n\(stdout)")
    }
    if !stderr.isEmpty {
      sections.append("STDERR:\n\(stderr)")
    }
    if timedOut {
      sections.append("TIMEOUT nach \(Int(Self.commandTimeout)) Sekunden")
    }
    sections.append("EXIT: \(exitCode)")

    return ToolExecutionResult(
      success: exitCode == 0 && !timedOut,
      output: sections.joined(separator: "\n\n"),
      exitCode: exitCode
    )
  }

  private func readLimitedText(from url: URL) throws -> String {
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    let limited = data.prefix(Self.maxOutputBytes)
    var text = String(decoding: limited, as: UTF8.self)
    if data.count > Self.maxOutputBytes {
      text += "\n… Ausgabe auf \(Self.maxOutputBytes) Bytes begrenzt."
    }
    return text
  }

  private func makeWorkspaceURL(_ path: String) throws -> URL {
    let expanded = NSString(string: path).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded, isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw AgentRuntimeError.invalidWorkspace(path)
    }
    return url
  }

  private func resolveExistingPath(
    _ path: String,
    workspace: URL,
    allowOutsideWorkspace: Bool
  ) throws -> URL {
    let candidate = makeCandidateURL(path, workspace: workspace)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    try enforceWorkspace(
      candidate,
      workspace: workspace,
      allowOutsideWorkspace: allowOutsideWorkspace
    )
    return candidate
  }

  private func resolveDestinationPath(
    _ path: String,
    workspace: URL,
    allowOutsideWorkspace: Bool
  ) throws -> URL {
    let candidate = makeCandidateURL(path, workspace: workspace).standardizedFileURL
    let resolvedParent = candidate.deletingLastPathComponent().resolvingSymlinksInPath()
    let resolved = resolvedParent.appendingPathComponent(candidate.lastPathComponent)
    try enforceWorkspace(
      resolved,
      workspace: workspace,
      allowOutsideWorkspace: allowOutsideWorkspace
    )
    return resolved
  }

  private func makeCandidateURL(_ path: String, workspace: URL) -> URL {
    let expanded = NSString(string: path).expandingTildeInPath
    if expanded.hasPrefix("/") {
      return URL(fileURLWithPath: expanded)
    }
    return workspace.appendingPathComponent(expanded)
  }

  private func enforceWorkspace(
    _ url: URL,
    workspace: URL,
    allowOutsideWorkspace: Bool
  ) throws {
    guard !allowOutsideWorkspace else { return }
    let workspacePath = workspace.standardizedFileURL.path
    let targetPath = url.standardizedFileURL.path
    guard targetPath == workspacePath || targetPath.hasPrefix(workspacePath + "/") else {
      throw AgentRuntimeError.pathOutsideWorkspace(targetPath)
    }
  }

  private func requiredString(
    _ name: String,
    in call: ProviderToolCall
  ) throws -> String {
    guard
      let value = call.function.arguments[name]?.stringValue,
      !value.isEmpty
    else {
      throw AgentRuntimeError.missingArgument(
        tool: call.function.name,
        name: name
      )
    }
    return value
  }

  private func isBlockedWorkspaceCommand(_ command: String) -> Bool {
    let normalized = command.lowercased()
    let blockedFragments = [
      "sudo ",
      "rm -rf /",
      "shutdown",
      "reboot",
      "diskutil erase",
      "diskutil partition",
      "mkfs",
      ":(){ :|:& };:",
      "dd if=",
    ]
    return blockedFragments.contains { normalized.contains($0) }
  }

  private static func objectSchema(
    required: [String] = [],
    properties: [String: JSONValue]
  ) -> JSONValue {
    var object: [String: JSONValue] = [
      "type": .string("object"),
      "properties": .object(properties),
      "additionalProperties": .bool(false),
    ]
    if !required.isEmpty {
      object["required"] = .array(required.map(JSONValue.string))
    }
    return .object(object)
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

private final class ProcessWaitState: @unchecked Sendable {
  private let lock = NSLock()
  private var finished = false
  private var timeoutRequested = false

  func markTimedOutIfRunning() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !finished else { return false }
    timeoutRequested = true
    return true
  }

  func finish() -> (shouldResume: Bool, timedOut: Bool) {
    lock.lock()
    defer { lock.unlock() }
    guard !finished else {
      return (false, timeoutRequested)
    }
    finished = true
    return (true, timeoutRequested)
  }
}

private enum ProcessOutcome: Sendable {
  case terminated(exitCode: Int32, timedOut: Bool)
  case launchFailed(String)
}

private final class ProcessReference: @unchecked Sendable {
  let process: Process

  init(_ process: Process) {
    self.process = process
  }
}
