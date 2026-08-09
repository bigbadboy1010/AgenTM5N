import Foundation

private enum EdgeExecutionError: LocalizedError {
  case absolutePathRequired(String)
  case invalidTarget(String)
  case unsupportedOperation(String)
  case unsupportedAction(String, String)
  case missingCommand
  case contentTooLarge(Int)

  var errorDescription: String? {
    switch self {
    case .absolutePathRequired(let path):
      return "Edge-Pfade müssen absolut sein: \(path)"
    case .invalidTarget(let value):
      return "Ungültiger Edge-Zielname: \(value)"
    case .unsupportedOperation(let value):
      return "Nicht unterstützte Edge-Operation: \(value)"
    case .unsupportedAction(let operation, let action):
      return "Nicht unterstützte Edge-Aktion für \(operation): \(action)"
    case .missingCommand:
      return "Für edge_control operation=run fehlt command."
    case .contentTooLarge(let limit):
      return "Der Edge-Dateiinhalt überschreitet das Limit von \(limit) Bytes."
    }
  }
}

@MainActor
extension AppState {
  func executeEdgeTool(_ call: ProviderToolCall) async -> ToolExecutionResult {
    do {
      switch call.function.name {
      case "edge_list_nodes":
        return edgeEncode(
          sshHosts.map { host in
            [
              "name": host.name,
              "hostname": host.hostname,
              "port": String(host.port),
              "username": host.username,
              "authentication": host.authenticationKind.rawValue,
              "credential_configured": String(host.authenticationSecretID != nil),
            ]
          }
        )

      case "edge_list_directory":
        let host = try edgeRequiredString("host", in: call)
        let path = try edgeAbsoluteRemotePath(
          try edgeRequiredString("path", in: call)
        )
        let depth = max(1, min(edgeOptionalInt("depth", in: call) ?? 2, 4))
        let quoted = ShellEscaping.singleQuoted(path)
        return await edgeRunSSH(
          hostQuery: host,
          command: "test -d \(quoted) && find \(quoted) -mindepth 1 -maxdepth \(depth) -print 2>/dev/null | head -n 1000"
        )

      case "edge_read_file":
        let host = try edgeRequiredString("host", in: call)
        let path = try edgeAbsoluteRemotePath(
          try edgeRequiredString("path", in: call)
        )
        let maximumBytes = max(
          1,
          min(edgeOptionalInt("max_bytes", in: call) ?? 65_536, 524_288)
        )
        let quoted = ShellEscaping.singleQuoted(path)
        return await edgeRunSSH(
          hostQuery: host,
          command: "test -f \(quoted) && head -c \(maximumBytes) -- \(quoted)"
        )

      case "edge_write_file":
        return await edgeWriteFile(call)

      case "edge_control":
        return await edgeControl(call)

      default:
        return .init(
          success: false,
          output: "Unsupported Edge tool: \(call.function.name)"
        )
      }
    } catch {
      return .init(
        success: false,
        output: SecureSecretBroker.redact(error.localizedDescription, secrets: secrets)
      )
    }
  }

  private func edgeWriteFile(_ call: ProviderToolCall) async -> ToolExecutionResult {
    do {
      let host = try edgeRequiredString("host", in: call)
      let path = try edgeAbsoluteRemotePath(
        try edgeRequiredString("path", in: call)
      )
      let content = try edgeRequiredString("content", in: call, allowEmpty: true)
      let maximumBytes = 524_288
      guard content.utf8.count <= maximumBytes else {
        throw EdgeExecutionError.contentTooLarge(maximumBytes)
      }

      let createParent = call.function.arguments["create_parent"]?.boolValue ?? false
      let backup = call.function.arguments["backup"]?.boolValue ?? true
      let parent = NSString(string: path).deletingLastPathComponent
      let target = ShellEscaping.singleQuoted(path)
      let parentQuoted = ShellEscaping.singleQuoted(parent)
      let encoded = Data(content.utf8).base64EncodedString()
      let encodedQuoted = ShellEscaping.singleQuoted(encoded)

      var commands: [String] = ["set -e"]
      if createParent {
        commands.append("mkdir -p -- \(parentQuoted)")
      } else {
        commands.append("test -d \(parentQuoted)")
      }
      commands.append("target=\(target)")
      commands.append("tmp=\"${target}.agentm5n.$$\"")
      commands.append("trap 'rm -f -- \"$tmp\"' EXIT")
      commands.append("printf %s \(encodedQuoted) | base64 -d > \"$tmp\"")
      if backup {
        commands.append("if [ -e \"$target\" ]; then cp -p -- \"$target\" \"${target}.bak.$(date +%Y%m%d%H%M%S)\"; fi")
      }
      commands.append("if [ -e \"$target\" ]; then chmod --reference=\"$target\" \"$tmp\" 2>/dev/null || true; chown --reference=\"$target\" \"$tmp\" 2>/dev/null || true; fi")
      commands.append("mv -f -- \"$tmp\" \"$target\"")
      commands.append("trap - EXIT")
      commands.append("wc -c -- \"$target\"")

      return await edgeRunSSH(
        hostQuery: host,
        command: commands.joined(separator: "; ")
      )
    } catch {
      return .init(
        success: false,
        output: SecureSecretBroker.redact(error.localizedDescription, secrets: secrets)
      )
    }
  }

  private func edgeControl(_ call: ProviderToolCall) async -> ToolExecutionResult {
    do {
      let host = try edgeRequiredString("host", in: call)
      let operation = try edgeRequiredString("operation", in: call).lowercased()
      let lines = max(1, min(edgeOptionalInt("lines", in: call) ?? 200, 2_000))
      let command: String

      switch operation {
      case "status":
        command = """
          printf '=== HOST ===\\n'; hostname; \
          printf '\\n=== SYSTEM ===\\n'; uname -a; uptime; \
          printf '\\n=== DISK ===\\n'; df -h / /data 2>/dev/null || df -h; \
          printf '\\n=== EDGE ROOT ===\\n'; ls -ld /data/edge 2>/dev/null || true; \
          printf '\\n=== CONTAINERS ===\\n'; docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Image}}' 2>/dev/null || true; \
          printf '\\n=== FAILED SERVICES ===\\n'; systemctl --failed --no-pager 2>/dev/null || true
          """

      case "run":
        guard let requested = edgeOptionalString("command", in: call) else {
          throw EdgeExecutionError.missingCommand
        }
        guard requested.utf8.count <= 64 * 1024 else {
          throw AgentRuntimeError.inputTooLarge(limit: 64 * 1024)
        }
        command = requested

      case "container":
        let target = try edgeValidatedTarget(
          try edgeRequiredString("target", in: call),
          allowAtSign: false
        )
        let action = try edgeRequiredString("action", in: call).lowercased()
        let quoted = ShellEscaping.singleQuoted(target)
        switch action {
        case "status":
          command = "docker ps -a --filter name=^/\(target)$ --format 'table {{.Names}}\\t{{.Status}}\\t{{.Image}}'"
        case "logs":
          command = "docker logs --tail \(lines) -- \(quoted) 2>&1"
        case "start", "stop", "restart":
          command = "docker \(action) -- \(quoted)"
        default:
          throw EdgeExecutionError.unsupportedAction(operation, action)
        }

      case "service":
        let target = try edgeValidatedTarget(
          try edgeRequiredString("target", in: call),
          allowAtSign: true
        )
        let action = try edgeRequiredString("action", in: call).lowercased()
        let quoted = ShellEscaping.singleQuoted(target)
        switch action {
        case "status":
          command = "systemctl status --no-pager \(quoted)"
        case "start", "stop", "restart":
          command = "systemctl \(action) \(quoted)"
        default:
          throw EdgeExecutionError.unsupportedAction(operation, action)
        }

      case "tail":
        let path = try edgeAbsoluteRemotePath(
          try edgeRequiredString("path", in: call)
        )
        command = "tail -n \(lines) -- \(ShellEscaping.singleQuoted(path))"

      default:
        throw EdgeExecutionError.unsupportedOperation(operation)
      }

      return await edgeRunSSH(hostQuery: host, command: command)
    } catch {
      return .init(
        success: false,
        output: SecureSecretBroker.redact(error.localizedDescription, secrets: secrets)
      )
    }
  }

  private func edgeRunSSH(
    hostQuery: String,
    command: String
  ) async -> ToolExecutionResult {
    do {
      let host = try edgeResolveSSHHost(hostQuery)
      let credentials = try edgeAuthenticationSecrets(for: host)
      let launch = try SSHLaunchService().makeExecutionLaunch(
        host: host,
        authenticationSecret: credentials.authentication,
        passphraseSecret: credentials.passphrase,
        command: command
      )
      defer {
        for path in launch.cleanupPaths {
          try? FileManager.default.removeItem(at: path)
        }
      }
      guard let localCommand = launch.initialCommand else {
        throw SSHAgentToolError.missingLaunchCommand
      }
      let result = await AgentRuntime().executeCommand(
        localCommand,
        workspacePath: configuration.workspacePath
      )
      return .init(
        success: result.success,
        output: SecureSecretBroker.redact(result.output, secrets: secrets)
      )
    } catch {
      return .init(
        success: false,
        output: SecureSecretBroker.redact(error.localizedDescription, secrets: secrets)
      )
    }
  }

  private func edgeResolveSSHHost(_ query: String) throws -> SSHHost {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = sshHosts.filter {
      $0.id.uuidString.caseInsensitiveCompare(normalized) == .orderedSame
        || $0.name.caseInsensitiveCompare(normalized) == .orderedSame
        || $0.hostname.caseInsensitiveCompare(normalized) == .orderedSame
    }
    guard !matches.isEmpty else { throw SSHAgentToolError.hostNotFound(query) }
    guard matches.count == 1, let host = matches.first else {
      throw SSHAgentToolError.ambiguousHost(query, matches.map(\.name))
    }
    return host
  }

  private func edgeAuthenticationSecrets(
    for host: SSHHost
  ) throws -> (authentication: VaultSecret?, passphrase: VaultSecret?) {
    let authentication = host.authenticationSecretID.flatMap { id in
      secrets.first(where: { $0.id == id })
    }
    let passphrase = host.passphraseSecretID.flatMap { id in
      secrets.first(where: { $0.id == id })
    }
    if host.authenticationSecretID != nil, authentication == nil {
      throw SecureSecretBrokerError.vaultLocked
    }
    if host.passphraseSecretID != nil, passphrase == nil {
      throw SecureSecretBrokerError.vaultLocked
    }
    return (authentication, passphrase)
  }

  private func edgeAbsoluteRemotePath(_ value: String) throws -> String {
    let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard path.hasPrefix("/") else {
      throw EdgeExecutionError.absolutePathRequired(value)
    }
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-"
    )
    let segments = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !path.contains("\n"),
      !path.contains("\r"),
      path.unicodeScalars.allSatisfy({ allowed.contains($0) }),
      !segments.contains(where: { $0 == ".." })
    else {
      throw EdgeExecutionError.absolutePathRequired(value)
    }
    return path
  }

  private func edgeValidatedTarget(
    _ value: String,
    allowAtSign: Bool
  ) throws -> String {
    let target = value.trimmingCharacters(in: .whitespacesAndNewlines)
    var characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    if allowAtSign { characters += "@" }
    let allowed = CharacterSet(charactersIn: characters)
    guard !target.isEmpty,
      target.unicodeScalars.allSatisfy({ allowed.contains($0) })
    else {
      throw EdgeExecutionError.invalidTarget(value)
    }
    return target
  }

  private func edgeRequiredString(
    _ name: String,
    in call: ProviderToolCall,
    allowEmpty: Bool = false
  ) throws -> String {
    guard let value = call.function.arguments[name]?.stringValue else {
      throw AgentRuntimeError.missingArgument(tool: call.function.name, name: name)
    }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if !allowEmpty, normalized.isEmpty {
      throw AgentRuntimeError.missingArgument(tool: call.function.name, name: name)
    }
    return allowEmpty ? value : normalized
  }

  private func edgeOptionalString(
    _ name: String,
    in call: ProviderToolCall
  ) -> String? {
    guard let value = call.function.arguments[name]?.stringValue else { return nil }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }

  private func edgeOptionalInt(
    _ name: String,
    in call: ProviderToolCall
  ) -> Int? {
    guard let value = call.function.arguments[name],
      case .number(let number) = value,
      number.isFinite
    else { return nil }
    return Int(number)
  }

  private func edgeEncode<T: Encodable>(_ value: T) -> ToolExecutionResult {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(value)
      return .init(
        success: true,
        output: SecureSecretBroker.redact(
          String(decoding: data, as: UTF8.self),
          secrets: secrets
        )
      )
    } catch {
      return .init(success: false, output: error.localizedDescription)
    }
  }
}
