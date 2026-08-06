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
  case invalidSearchQuery
  case invalidGlobPattern(String)
  case patchOccurrenceMismatch(path: String, count: Int)
  case invalidGitBranch(String)
  case invalidGitPaths
  case repeatedToolCall(String)

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
    case .invalidSearchQuery:
      "Die Suchabfrage muss eine einzelne, nicht leere Textzeile sein."
    case .invalidGlobPattern(let pattern):
      "Das Glob-Muster ist ungültig: \(pattern)"
    case .patchOccurrenceMismatch(let path, let count):
      "Der Patch wurde nicht angewendet. Der alte Text kommt in \(path) \(count)-mal statt genau einmal vor."
    case .invalidGitBranch(let branch):
      "Der Git-Branchname ist ungültig: \(branch)"
    case .invalidGitPaths:
      "git_commit benötigt mindestens einen konkreten Workspace-Pfad; '.' und Pfade außerhalb des Workspace sind nicht erlaubt."
    case .repeatedToolCall(let name):
      "Wiederholungssperre: Der äquivalente Tool-Aufruf \(name) wurde innerhalb kurzer Zeit bereits zweimal ausgeführt. Prüfe die vorhandenen Ergebnisse, bevor du ihn erneut aufrufst."
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
      name: "glob_files",
      description: "Find workspace files whose relative path or filename matches a glob pattern such as **/*.swift, *.yml or Sources/**. Returns relative paths only.",
      parameters: objectSchema(
        required: ["pattern"],
        properties: [
          "pattern": stringSchema("Glob pattern. Use ** for recursive directories, * inside one path segment and ? for one character."),
          "path": stringSchema("Optional directory or file to search below. Defaults to the workspace root."),
          "include_hidden": boolSchema("Include hidden files and directories. Defaults to false.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "search_text",
      description: "Search UTF-8 workspace files for an exact text fragment and return relative path, line, column and a bounded line preview. Use glob to restrict file types.",
      parameters: objectSchema(
        required: ["query"],
        properties: [
          "query": stringSchema("Single-line literal text to search for."),
          "path": stringSchema("Optional directory or file to search below. Defaults to the workspace root."),
          "glob": stringSchema("Optional glob filter such as *.swift or Sources/**/*.swift."),
          "case_sensitive": boolSchema("Use case-sensitive matching. Defaults to false."),
          "include_hidden": boolSchema("Include hidden files and directories. Defaults to false.")
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
      name: "apply_patch",
      description: "Safely replace exactly one known text block in an existing UTF-8 file. The patch fails if old_text occurs zero or multiple times. Prefer this over write_file for edits.",
      parameters: objectSchema(
        required: ["path", "old_text", "new_text"],
        properties: [
          "path": stringSchema("Relative or absolute target file path."),
          "old_text": stringSchema("Exact existing text block that must occur exactly once."),
          "new_text": stringSchema("Replacement text block. May be empty to remove the old block.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "write_file",
      description: "Create or replace a UTF-8 text file. Use apply_patch instead when changing an existing file. Parent directories may be created.",
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
      description: "Run a local zsh command in the configured workspace and return stdout, stderr and exit status. Use this for non-interactive local work.",
      parameters: objectSchema(
        required: ["command"],
        properties: [
          "command": stringSchema("Local shell command to execute.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "terminal_open",
      description: "Open the visible local AgenTM5N terminal, optionally with an initial command. Use run_command instead when command output must be analyzed.",
      parameters: objectSchema(
        properties: [
          "command": stringSchema("Optional initial command shown in the interactive terminal."),
          "title": stringSchema("Optional terminal session title.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "ssh_list_hosts",
      description: "List configured AgenTM5N SSH host profiles without exposing passwords, private keys, passphrases or secret identifiers.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "ssh_run",
      description: "Execute a non-interactive command on a configured SSH host profile. AgenTM5N resolves authentication internally and returns stdout, stderr and exit status. Never request secret values.",
      parameters: objectSchema(
        required: ["host", "command"],
        properties: [
          "host": stringSchema("Configured SSH host name, hostname or host UUID."),
          "command": stringSchema("Remote shell command to execute non-interactively.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "ssh_open_terminal",
      description: "Open a configured SSH host in the visible interactive AgenTM5N terminal. An optional initial remote command may be supplied.",
      parameters: objectSchema(
        required: ["host"],
        properties: [
          "host": stringSchema("Configured SSH host name, hostname or host UUID."),
          "command": stringSchema("Optional remote command to start after connecting.")
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
    ProviderToolDefinition(
      name: "git_branches",
      description: "Show the current branch and local Git branches for the configured workspace.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "git_checkout",
      description: "Switch to an existing local branch or create a new branch. The operation is blocked when the working tree is not clean and never forces or discards changes.",
      parameters: objectSchema(
        required: ["branch"],
        properties: [
          "branch": stringSchema("Valid local Git branch name."),
          "create": boolSchema("Create the branch from the current HEAD before switching. Defaults to false.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "git_commit",
      description: "Stage only the explicitly listed workspace paths and create a local Git commit. Existing staged changes cause the operation to fail. This tool never pushes.",
      parameters: objectSchema(
        required: ["message", "paths"],
        properties: [
          "message": stringSchema("Commit message, 1 to 500 characters."),
          "paths": arraySchema(
            item: stringSchema("Concrete relative workspace path to stage. Do not use '.'."),
            description: "One or more concrete workspace paths to stage and commit."
          )
        ]
      )
    ),
  ]

  private static let maxReadBytes = 512 * 1024
  private static let maxSearchFileBytes = 1 * 1024 * 1024
  private static let maxWriteBytes = 1 * 1024 * 1024
  private static let maxOutputBytes = 256 * 1024
  private static let maxSearchResults = 200
  private static let maxGlobResults = 500
  private static let commandTimeout: TimeInterval = 120
  private static let repetitionWindow: TimeInterval = 90
  private static let excludedDirectoryNames: Set<String> = [
    ".git", ".build", ".swiftpm", "dist", "DerivedData", "node_modules", ".idea", ".vscode"
  ]

  private var repetitionLedger: [String: RepetitionEntry] = [:]

  public init() {}

  public func risk(for call: ProviderToolCall) -> ToolRisk {
    switch call.function.name {
    case "list_directory", "glob_files", "search_text", "read_file", "git_status",
      "git_diff", "git_branches", "ssh_list_hosts":
      .read
    case "apply_patch", "write_file", "git_checkout", "git_commit":
      .write
    case "run_command", "terminal_open", "ssh_run", "ssh_open_terminal":
      .execute
    default:
      .execute
    }
  }

  public func summary(for call: ProviderToolCall) -> String {
    let arguments = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      let rendered: String
      if key == "content" || key == "old_text" || key == "new_text" {
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
      if let repeated = repetitionBlock(for: call) {
        throw repeated
      }

      let workspace = try makeWorkspaceURL(workspacePath)
      switch call.function.name {
      case "list_directory":
        return try listDirectory(
          call: call,
          workspace: workspace,
          allowOutsideWorkspace: permissionMode == .fullAccess
        )
      case "glob_files":
        return try globFiles(
          call: call,
          workspace: workspace,
          allowOutsideWorkspace: permissionMode == .fullAccess
        )
      case "search_text":
        return try searchText(
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
      case "apply_patch":
        return try applyPatch(
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
      case "git_branches":
        return try await runCommand(
          "printf 'CURRENT: '; git branch --show-current; printf '\nLOCAL BRANCHES:\n'; git branch --format='%(refname:short)'",
          workspace: workspace
        )
      case "git_checkout":
        return try await gitCheckout(call: call, workspace: workspace)
      case "git_commit":
        return try await gitCommit(call: call, workspace: workspace)
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

  public func executeCommand(
    _ command: String,
    workspacePath: String
  ) async -> ToolExecutionResult {
    do {
      let workspace = try makeWorkspaceURL(workspacePath)
      return try await runCommand(command, workspace: workspace)
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

  private func globFiles(
    call: ProviderToolCall,
    workspace: URL,
    allowOutsideWorkspace: Bool
  ) throws -> ToolExecutionResult {
    let pattern = try requiredString("pattern", in: call)
    let rootPath = call.function.arguments["path"]?.stringValue ?? "."
    let root = try resolveExistingPath(
      rootPath,
      workspace: workspace,
      allowOutsideWorkspace: allowOutsideWorkspace
    )
    let includeHidden = call.function.arguments["include_hidden"]?.boolValue ?? false
    let matcher = try GlobMatcher(pattern: pattern)
    let candidates = try collectFiles(
      below: root,
      workspace: workspace,
      includeHidden: includeHidden,
      limit: Self.maxGlobResults * 4
    )

    let matches = candidates
      .filter { candidate in
        matcher.matches(
          relativePath: relativePath(candidate, from: workspace),
          basename: candidate.lastPathComponent
        )
      }
      .map { relativePath($0, from: workspace) }
      .sorted()
      .prefix(Self.maxGlobResults)

    return ToolExecutionResult(
      success: true,
      output: matches.isEmpty ? "(keine Treffer)" : matches.joined(separator: "\n")
    )
  }

  private func searchText(
    call: ProviderToolCall,
    workspace: URL,
    allowOutsideWorkspace: Bool
  ) throws -> ToolExecutionResult {
    let query = try requiredString("query", in: call)
    guard !query.contains("\n"), !query.contains("\r") else {
      throw AgentRuntimeError.invalidSearchQuery
    }

    let rootPath = call.function.arguments["path"]?.stringValue ?? "."
    let root = try resolveExistingPath(
      rootPath,
      workspace: workspace,
      allowOutsideWorkspace: allowOutsideWorkspace
    )
    let includeHidden = call.function.arguments["include_hidden"]?.boolValue ?? false
    let caseSensitive = call.function.arguments["case_sensitive"]?.boolValue ?? false
    let glob = call.function.arguments["glob"]?.stringValue
    let matcher = try glob.map(GlobMatcher.init(pattern:))
    let candidates = try collectFiles(
      below: root,
      workspace: workspace,
      includeHidden: includeHidden,
      limit: 20_000
    )

    var results: [String] = []
    let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]

    for file in candidates {
      let relative = relativePath(file, from: workspace)
      if let matcher,
        !matcher.matches(relativePath: relative, basename: file.lastPathComponent)
      {
        continue
      }

      let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      guard values.isRegularFile == true else { continue }
      guard (values.fileSize ?? 0) <= Self.maxSearchFileBytes else { continue }
      let data = try Data(contentsOf: file, options: [.mappedIfSafe])
      guard let text = String(data: data, encoding: .utf8) else { continue }

      var lineNumber = 0
      text.enumerateLines { line, stop in
        lineNumber += 1
        guard let range = line.range(of: query, options: options) else { return }
        let column = line.distance(from: line.startIndex, to: range.lowerBound) + 1
        var preview = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.count > 500 {
          preview = String(preview.prefix(500)) + "…"
        }
        results.append("\(relative):\(lineNumber):\(column): \(preview)")
        if results.count >= Self.maxSearchResults {
          stop = true
        }
      }

      if results.count >= Self.maxSearchResults {
        break
      }
    }

    if results.isEmpty {
      return ToolExecutionResult(success: true, output: "(keine Treffer)")
    }
    if results.count >= Self.maxSearchResults {
      results.append("… Suche auf \(Self.maxSearchResults) Treffer begrenzt.")
    }
    return ToolExecutionResult(success: true, output: results.joined(separator: "\n"))
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

  private func applyPatch(
    call: ProviderToolCall,
    workspace: URL,
    allowOutsideWorkspace: Bool
  ) throws -> ToolExecutionResult {
    let path = try requiredString("path", in: call)
    let oldText = try requiredString("old_text", in: call)
    let newText = call.function.arguments["new_text"]?.stringValue ?? ""
    guard !oldText.isEmpty else {
      throw AgentRuntimeError.missingArgument(tool: call.function.name, name: "old_text")
    }

    let file = try resolveExistingPath(
      path,
      workspace: workspace,
      allowOutsideWorkspace: allowOutsideWorkspace
    )
    let data = try Data(contentsOf: file, options: [.mappedIfSafe])
    guard data.count <= Self.maxWriteBytes else {
      throw AgentRuntimeError.inputTooLarge(limit: Self.maxWriteBytes)
    }
    guard let text = String(data: data, encoding: .utf8) else {
      throw AgentRuntimeError.unreadableTextFile(file.path)
    }

    let occurrenceCount = text.components(separatedBy: oldText).count - 1
    guard occurrenceCount == 1 else {
      throw AgentRuntimeError.patchOccurrenceMismatch(path: file.path, count: occurrenceCount)
    }

    let updated = text.replacingOccurrences(of: oldText, with: newText)
    guard updated.utf8.count <= Self.maxWriteBytes else {
      throw AgentRuntimeError.inputTooLarge(limit: Self.maxWriteBytes)
    }
    guard let updatedData = updated.data(using: .utf8) else {
      throw AgentRuntimeError.unreadableTextFile(file.path)
    }
    try updatedData.write(to: file, options: [.atomic])

    let removedLines = oldText.split(separator: "\n", omittingEmptySubsequences: false).count
    let addedLines = newText.split(separator: "\n", omittingEmptySubsequences: false).count
    return ToolExecutionResult(
      success: true,
      output: "Patch angewendet: \(relativePath(file, from: workspace)) (-\(removedLines) / +\(addedLines) Zeilen, \(updatedData.count) Bytes)."
    )
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

  private func gitCheckout(
    call: ProviderToolCall,
    workspace: URL
  ) async throws -> ToolExecutionResult {
    let branch = try requiredString("branch", in: call)
    guard isValidGitBranchName(branch) else {
      throw AgentRuntimeError.invalidGitBranch(branch)
    }
    let create = call.function.arguments["create"]?.boolValue ?? false
    let quotedBranch = ShellEscaping.singleQuoted(branch)
    let switchCommand = create
      ? "git switch -c \(quotedBranch)"
      : "git switch \(quotedBranch)"
    let command = """
      if [[ -n "$(git status --porcelain)" ]]; then
        print -u2 -- 'Arbeitsbaum ist nicht sauber; Branchwechsel wurde abgebrochen.'
        exit 20
      fi
      \(switchCommand)
      git status --short --branch
      """
    return try await runCommand(command, workspace: workspace)
  }

  private func gitCommit(
    call: ProviderToolCall,
    workspace: URL
  ) async throws -> ToolExecutionResult {
    let message = try requiredString("message", in: call)
    guard message.count <= 500 else {
      throw AgentRuntimeError.inputTooLarge(limit: 500)
    }
    let paths = try gitPaths(from: call, workspace: workspace)
    let quotedPaths = paths.map(ShellEscaping.singleQuoted).joined(separator: " ")
    let quotedMessage = ShellEscaping.singleQuoted(message)
    let command = """
      if ! git diff --cached --quiet; then
        print -u2 -- 'Es existieren bereits staged Änderungen; Commit wurde abgebrochen.'
        exit 21
      fi
      git add -- \(quotedPaths)
      if git diff --cached --quiet; then
        print -u2 -- 'Die angegebenen Pfade enthalten keine commitfähigen Änderungen.'
        exit 22
      fi
      if ! git commit -m \(quotedMessage); then
        status=$?
        git restore --staged -- \(quotedPaths) >/dev/null 2>&1 || true
        exit $status
      fi
      git log -1 --oneline --decorate
      """
    return try await runCommand(command, workspace: workspace)
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

  private func collectFiles(
    below root: URL,
    workspace: URL,
    includeHidden: Bool,
    limit: Int
  ) throws -> [URL] {
    let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
    if values.isRegularFile == true {
      return [root]
    }
    guard values.isDirectory == true else { return [] }

    var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
    if !includeHidden {
      options.insert(.skipsHiddenFiles)
    }
    let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: keys,
      options: options,
      errorHandler: { _, _ in true }
    ) else {
      return []
    }

    var files: [URL] = []
    for case let url as URL in enumerator {
      let resourceValues = try url.resourceValues(forKeys: Set(keys))
      if resourceValues.isDirectory == true {
        if Self.excludedDirectoryNames.contains(url.lastPathComponent) {
          enumerator.skipDescendants()
        }
        continue
      }
      guard resourceValues.isRegularFile == true, resourceValues.isSymbolicLink != true else {
        continue
      }
      files.append(url)
      if files.count >= limit {
        break
      }
    }
    return files
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

  private func relativePath(_ url: URL, from workspace: URL) -> String {
    let workspacePath = workspace.standardizedFileURL.path
    let targetPath = url.standardizedFileURL.path
    guard targetPath.hasPrefix(workspacePath + "/") else { return targetPath }
    return String(targetPath.dropFirst(workspacePath.count + 1))
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

  private func gitPaths(
    from call: ProviderToolCall,
    workspace: URL
  ) throws -> [String] {
    guard case .array(let values) = call.function.arguments["paths"] else {
      throw AgentRuntimeError.invalidGitPaths
    }
    var results: [String] = []
    for value in values {
      guard let path = value.stringValue else {
        throw AgentRuntimeError.invalidGitPaths
      }
      let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, trimmed != "." else {
        throw AgentRuntimeError.invalidGitPaths
      }
      let candidate = makeCandidateURL(trimmed, workspace: workspace).standardizedFileURL
      try enforceWorkspace(candidate, workspace: workspace, allowOutsideWorkspace: false)
      let relative = relativePath(candidate, from: workspace)
      guard !relative.isEmpty, relative != "." else {
        throw AgentRuntimeError.invalidGitPaths
      }
      results.append(relative)
    }
    guard !results.isEmpty else {
      throw AgentRuntimeError.invalidGitPaths
    }
    return Array(Set(results)).sorted()
  }

  private func isValidGitBranchName(_ branch: String) -> Bool {
    guard !branch.isEmpty, branch.count <= 255 else { return false }
    guard !branch.hasPrefix("-"), !branch.hasPrefix("/"), !branch.hasSuffix("/") else {
      return false
    }
    guard !branch.contains(".."), !branch.contains("@{"), !branch.hasSuffix(".lock") else {
      return false
    }
    let forbidden = CharacterSet(charactersIn: " ~^:?*[\\\t\n\r")
    return branch.rangeOfCharacter(from: forbidden) == nil
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

  private func repetitionBlock(for call: ProviderToolCall) -> AgentRuntimeError? {
    let now = Date()
    repetitionLedger = repetitionLedger.filter {
      now.timeIntervalSince($0.value.lastSeen) <= Self.repetitionWindow
    }

    let signature = canonicalSignature(for: call)
    let existing = repetitionLedger[signature]
    if let existing, existing.count >= 2 {
      return .repeatedToolCall(call.function.name)
    }
    repetitionLedger[signature] = RepetitionEntry(
      count: (existing?.count ?? 0) + 1,
      lastSeen: now
    )
    return nil
  }

  private func canonicalSignature(for call: ProviderToolCall) -> String {
    let arguments = call.function.arguments.keys.sorted().map { key in
      "\(key)=\(call.function.arguments[key]?.compactDescription ?? "null")"
    }
    return "\(call.function.name)|\(arguments.joined(separator: "|"))"
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

  private static func arraySchema(item: JSONValue, description: String) -> JSONValue {
    .object([
      "type": .string("array"),
      "description": .string(description),
      "items": item,
      "minItems": .number(1),
    ])
  }
}

private struct RepetitionEntry: Sendable {
  let count: Int
  let lastSeen: Date
}

private struct GlobMatcher: Sendable {
  private let expression: NSRegularExpression
  private let matchesBasenameOnly: Bool
  private let pattern: String

  init(pattern: String) throws {
    let normalized = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, normalized.count <= 512 else {
      throw AgentRuntimeError.invalidGlobPattern(pattern)
    }
    self.pattern = normalized
    matchesBasenameOnly = !normalized.contains("/")

    var regex = "^"
    var index = normalized.startIndex
    let regexSpecial = CharacterSet(charactersIn: ".+()|^$[]{}\\")
    while index < normalized.endIndex {
      let character = normalized[index]
      if character == "*" {
        let next = normalized.index(after: index)
        if next < normalized.endIndex, normalized[next] == "*" {
          let afterDoubleStar = normalized.index(after: next)
          if afterDoubleStar < normalized.endIndex, normalized[afterDoubleStar] == "/" {
            regex += "(?:.*/)?"
            index = normalized.index(after: afterDoubleStar)
          } else {
            regex += ".*"
            index = afterDoubleStar
          }
          continue
        }
        regex += "[^/]*"
      } else if character == "?" {
        regex += "[^/]"
      } else {
        let scalar = String(character)
        if scalar.rangeOfCharacter(from: regexSpecial) != nil {
          regex += "\\"
        }
        regex += scalar
      }
      index = normalized.index(after: index)
    }
    regex += "$"

    do {
      expression = try NSRegularExpression(pattern: regex)
    } catch {
      throw AgentRuntimeError.invalidGlobPattern(pattern)
    }
  }

  func matches(relativePath: String, basename: String) -> Bool {
    let candidate = matchesBasenameOnly ? basename : relativePath
    let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
    return expression.firstMatch(in: candidate, range: range) != nil
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
