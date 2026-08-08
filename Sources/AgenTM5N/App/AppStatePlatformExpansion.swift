import AppKit
import Darwin
import Foundation

private struct WorkflowStepExecutionDescriptor: Encodable {
  let index: Int
  let tool: String
  let success: Bool
  let output: String
}

private struct WorkflowRunDescriptor: Encodable {
  let workflow: String
  let completed: Bool
  let steps: [WorkflowStepExecutionDescriptor]
}

private struct DelegatedAgentResultDescriptor: Encodable {
  let agent: String
  let provider: String
  let response: String
}

private struct AppVersionDescriptor: Encodable {
  let version: String
  let build: String
  let bundleIdentifier: String
}

private struct UpdateCheckDescriptor: Encodable {
  let currentVersion: String
  let currentBuild: String
  let availableVersion: String?
  let availableBuild: Int?
  let updateAvailable: Bool
  let downloadURL: String?
  let notes: String?
}

private struct ExpansionCoreMLModelDescriptor: Encodable {
  let id: String
  let name: String
  let active: Bool
  let inputs: [String]
  let outputs: [String]
  let computePolicy: String
}

private struct ExpansionCoreMLPredictionDescriptor: Encodable {
  let model: String
  let durationMilliseconds: Double
  let values: [String: String]
}

@MainActor
extension AppState {
  func executePlatformExpansionTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    switch call.function.name {
    case "secret_list":
      guard vaultUnlocked else {
        return .init(
          success: false,
          output: SecureSecretBrokerError.vaultLocked.localizedDescription
        )
      }
      return encodeExpansionResult(SecureSecretBroker.metadata(secrets))

    case "http_request":
      return await executeHTTPTool(call)

    case "system_info":
      return encodeExpansionResult(
        [
          "chip": hardwareProfile.chipName,
          "memory": hardwareProfile.memoryDescription,
          "operating_system": hardwareProfile.operatingSystem,
          "architecture": ProcessInfo.processInfo.machineArchitecture,
          "host_name": ProcessInfo.processInfo.hostName,
          "uptime_seconds": String(Int(ProcessInfo.processInfo.systemUptime)),
        ]
      )

    case "process_list":
      let limit = max(1, min(expansionOptionalInt("limit", in: call) ?? 25, 100))
      return await expansionCommand(
        "/bin/ps -Ao pid,pcpu,pmem,user,comm -r | /usr/bin/head -n \(limit + 1)"
      )

    case "disk_info":
      return await expansionCommand("/bin/df -h")

    case "network_info":
      return await expansionCommand(
        "/sbin/ifconfig -a; printf '\\nDEFAULT ROUTE\\n'; /sbin/route -n get default 2>/dev/null || true"
      )

    case "clipboard_read":
      let value = NSPasteboard.general.string(forType: .string) ?? ""
      return .init(success: true, output: String(value.prefix(100_000)))

    case "clipboard_write":
      return writeClipboardTool(call)

    case "notification_send":
      return await executeNotificationTool(call)

    case "shortcuts_list":
      return await expansionCommand("/usr/bin/shortcuts list")

    case "shortcuts_run":
      return await executeShortcutTool(call)

    case "finder_reveal":
      return revealFinderTool(call)

    case "ssh_upload":
      return await executeSSHTransferTool(call, upload: true)

    case "ssh_download":
      return await executeSSHTransferTool(call, upload: false)

    case "ssh_tail_log":
      return await executeSSHTailTool(call)

    case "ssh_run_batch":
      return await executeSSHBatchTool(call)

    case "reminders_list", "reminders_create", "reminders_complete":
      return await executeReminderTool(call)

    case "agent_delegate":
      return await executeAgentDelegationTool(call)

    case "workflow_list", "workflow_create", "workflow_delete", "workflow_run":
      return await executeWorkflowTool(call)

    case "app_version_info":
      return encodeExpansionResult(currentVersionDescriptor())

    case "app_check_update":
      return await executeUpdateCheckTool(call)

    default:
      return .init(
        success: false,
        output: "Unsupported AgenTM5N 1.1 platform tool: \(call.function.name)"
      )
    }
  }

  private func executeHTTPTool(_ call: ProviderToolCall) async -> ToolExecutionResult {
    do {
      let method = try expansionRequiredString("method", in: call)
      let url = try expansionRequiredString("url", in: call)
      let body = expansionOptionalString("body", in: call, allowEmpty: true)
      var headers: [String: String] = [:]
      if let headerValue = call.function.arguments["headers"],
        case .object(let values) = headerValue
      {
        for (key, value) in values {
          guard let text = value.stringValue else {
            throw AgentRuntimeError.missingArgument(
              tool: call.function.name,
              name: "headers.\(key)"
            )
          }
          headers[key] = text
        }
      }

      let secret: VaultSecret?
      if let secretRef = expansionOptionalString("secret_ref", in: call) {
        guard vaultUnlocked else { throw SecureSecretBrokerError.vaultLocked }
        secret = try SecureSecretBroker.resolve(secretRef, from: secrets)
      } else {
        secret = nil
      }

      let usageText = expansionOptionalString("secret_usage", in: call)?.lowercased()
      let usage = usageText.flatMap(SecretHTTPUsage.init(rawValue:))
      if usageText != nil, usage == nil {
        throw AgentRuntimeError.missingArgument(
          tool: call.function.name,
          name: "secret_usage (bearer/basic/header)"
        )
      }

      let response = try await SecureHTTPClient().request(
        method: method,
        urlText: url,
        headers: headers,
        body: body,
        secret: secret,
        secretUsage: usage,
        secretHeaderName: expansionOptionalString("secret_header", in: call)
      )
      return encodeExpansionResult(response)
    } catch {
      return .init(
        success: false,
        output: SecureSecretBroker.redact(error.localizedDescription, secrets: secrets)
      )
    }
  }

  private func writeClipboardTool(_ call: ProviderToolCall) -> ToolExecutionResult {
    do {
      let text = try expansionRequiredString("text", in: call, allowEmpty: true)
      NSPasteboard.general.clearContents()
      guard NSPasteboard.general.setString(text, forType: .string) else {
        return .init(
          success: false,
          output: "Der Text konnte nicht in die Zwischenablage geschrieben werden."
        )
      }
      return .init(
        success: true,
        output: "Text wurde in die macOS-Zwischenablage geschrieben."
      )
    } catch {
      return .init(success: false, output: error.localizedDescription)
    }
  }

  private func executeNotificationTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      let title = try expansionRequiredString("title", in: call)
      let message = try expansionRequiredString("message", in: call, allowEmpty: true)
      let subtitle = expansionOptionalString("subtitle", in: call, allowEmpty: true)
      var source = "display notification \(appleScriptLiteral(message)) with title \(appleScriptLiteral(title))"
      if let subtitle, !subtitle.isEmpty {
        source += " subtitle \(appleScriptLiteral(subtitle))"
      }
      return await expansionCommand(
        "/usr/bin/osascript -e \(ShellEscaping.singleQuoted(source))"
      )
    } catch {
      return .init(success: false, output: error.localizedDescription)
    }
  }

  private func executeShortcutTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      let name = try expansionRequiredString("name", in: call)
      return await expansionCommand(
        "/usr/bin/shortcuts run \(ShellEscaping.singleQuoted(name))"
      )
    } catch {
      return .init(success: false, output: error.localizedDescription)
    }
  }

  private func revealFinderTool(_ call: ProviderToolCall) -> ToolExecutionResult {
    do {
      let path = try expansionRequiredString("path", in: call)
      let url = try validatedLocalURL(path, mustExist: true)
      NSWorkspace.shared.activateFileViewerSelecting([url])
      return .init(success: true, output: "Finder zeigt \(url.lastPathComponent).")
    } catch {
      return .init(success: false, output: error.localizedDescription)
    }
  }

  private func executeSSHTransferTool(
    _ call: ProviderToolCall,
    upload: Bool
  ) async -> ToolExecutionResult {
    do {
      let host = try expansionResolveSSHHost(
        try expansionRequiredString("host", in: call)
      )
      let localPath = try expansionRequiredString("local_path", in: call)
      let remotePath = try expansionRequiredString("remote_path", in: call)
      try validateRemotePath(remotePath)
      let localURL = try validatedLocalURL(
        localPath,
        mustExist: upload,
        createParent: !upload
      )
      let credentials = try expansionAuthenticationSecrets(for: host)
      let launch = try SSHLaunchService().makeTransferLaunch(
        host: host,
        authenticationSecret: credentials.authentication,
        passphraseSecret: credentials.passphrase,
        localPath: localURL.path,
        remotePath: remotePath,
        upload: upload
      )
      defer { expansionCleanup(launch.cleanupPaths) }
      guard let command = launch.initialCommand else {
        throw SSHAgentToolError.missingLaunchCommand
      }
      let result = await expansionCommand(command)
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

  private func executeSSHTailTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      let path = try expansionRequiredString("path", in: call)
      try validateRemotePath(path)
      let lines = max(1, min(expansionOptionalInt("lines", in: call) ?? 200, 2_000))
      let forwarded = ProviderToolCall(
        function: .init(
          name: "ssh_run",
          arguments: [
            "host": .string(try expansionRequiredString("host", in: call)),
            "command": .string(
              "tail -n \(lines) -- \(ShellEscaping.singleQuoted(path))"
            ),
          ]
        )
      )
      return await expansionRunSSH(forwarded)
    } catch {
      return .init(success: false, output: error.localizedDescription)
    }
  }

  private func executeSSHBatchTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      guard let commandsValue = call.function.arguments["commands"],
        case .array(let values) = commandsValue
      else {
        throw AgentRuntimeError.missingArgument(
          tool: call.function.name,
          name: "commands"
        )
      }
      let commands = values.compactMap(\.stringValue)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      guard commands.count == values.count, !commands.isEmpty, commands.count <= 20 else {
        throw AgentRuntimeError.inputTooLarge(limit: 20)
      }
      for command in commands {
        guard command.utf8.count <= 32 * 1024 else {
          throw AgentRuntimeError.inputTooLarge(limit: 32 * 1024)
        }
      }

      let joined = commands.enumerated().map { index, command in
        "printf '\\n=== AgenTM5N step \(index + 1) ===\\n'; \(command)"
      }.joined(separator: "; ")
      let forwarded = ProviderToolCall(
        function: .init(
          name: "ssh_run",
          arguments: [
            "host": .string(try expansionRequiredString("host", in: call)),
            "command": .string(joined),
          ]
        )
      )
      return await expansionRunSSH(forwarded)
    } catch {
      return .init(success: false, output: error.localizedDescription)
    }
  }

  private func expansionRunSSH(_ call: ProviderToolCall) async -> ToolExecutionResult {
    do {
      let host = try expansionResolveSSHHost(
        try expansionRequiredString("host", in: call)
      )
      let command = try expansionRequiredString("command", in: call)
      let credentials = try expansionAuthenticationSecrets(for: host)
      let launch = try SSHLaunchService().makeExecutionLaunch(
        host: host,
        authenticationSecret: credentials.authentication,
        passphraseSecret: credentials.passphrase,
        command: command
      )
      defer { expansionCleanup(launch.cleanupPaths) }
      guard let localCommand = launch.initialCommand else {
        throw SSHAgentToolError.missingLaunchCommand
      }
      let result = await expansionCommand(localCommand)
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

  private func expansionOpenSSHTerminal(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      var host = try expansionResolveSSHHost(
        try expansionRequiredString("host", in: call)
      )
      if let command = expansionOptionalString("command", in: call) {
        host.remoteCommand = command
      }
      let credentials = try expansionAuthenticationSecrets(for: host)
      terminalLaunch = try SSHLaunchService().makeLaunch(
        host: host,
        authenticationSecret: credentials.authentication,
        passphraseSecret: credentials.passphrase
      )
      selectedSection = .terminal
      return .init(
        success: true,
        output: "Interaktive SSH-Sitzung zu \(host.name) wurde im sichtbaren Terminal geöffnet."
      )
    } catch {
      return .init(success: false, output: error.localizedDescription)
    }
  }

  private func executeReminderTool(_ call: ProviderToolCall) async -> ToolExecutionResult {
    do {
      let service = RemindersToolService.shared
      switch call.function.name {
      case "reminders_list":
        let limit = max(1, min(expansionOptionalInt("limit", in: call) ?? 25, 100))
        return encodeExpansionResult(try await service.list(limit: limit))
      case "reminders_create":
        return encodeExpansionResult(
          try await service.create(
            title: try expansionRequiredString("title", in: call),
            notes: expansionOptionalString("notes", in: call, allowEmpty: true),
            dueDateText: expansionOptionalString("due_date", in: call),
            listName: expansionOptionalString("list", in: call)
          )
        )
      case "reminders_complete":
        return encodeExpansionResult(
          try await service.complete(
            query: try expansionRequiredString("reminder", in: call)
          )
        )
      default:
        return .init(success: false, output: "Unsupported Reminders tool")
      }
    } catch {
      return .init(success: false, output: error.localizedDescription)
    }
  }

  private func executeWorkflowTool(_ call: ProviderToolCall) async -> ToolExecutionResult {
    do {
      let library = AgentWorkflowLibrary.shared
      switch call.function.name {
      case "workflow_list":
        return encodeExpansionResult(library.workflows)

      case "workflow_create":
        let steps = try WorkflowAgentTools.parseSteps(call.function.arguments["steps"])
        try rejectEmbeddedSecrets(in: call)
        let workflow = try library.create(
          name: try expansionRequiredString("name", in: call),
          purpose: try expansionRequiredString("purpose", in: call),
          steps: steps
        )
        return encodeExpansionResult(workflow)

      case "workflow_delete":
        return encodeExpansionResult(
          try library.delete(try expansionRequiredString("workflow", in: call))
        )

      case "workflow_run":
        let workflow = try library.resolve(
          try expansionRequiredString("workflow", in: call)
        )
        guard workflow.isEnabled else {
          throw AgentWorkflowError.disabled(workflow.name)
        }

        var results: [WorkflowStepExecutionDescriptor] = []
        var completed = true
        for (index, step) in workflow.steps.enumerated() {
          try Task.checkCancellation()
          let stepCall = ProviderToolCall(
            function: .init(name: step.toolName, arguments: step.arguments)
          )
          let result = await executeStandaloneWorkflowStep(stepCall)
          results.append(
            WorkflowStepExecutionDescriptor(
              index: index + 1,
              tool: step.toolName,
              success: result.success,
              output: String(
                SecureSecretBroker.redact(result.output, secrets: secrets)
                  .prefix(8_000)
              )
            )
          )
          if !result.success {
            completed = false
            break
          }
        }
        try library.markRun(id: workflow.id)
        return encodeExpansionResult(
          WorkflowRunDescriptor(
            workflow: workflow.name,
            completed: completed,
            steps: results
          )
        )

      default:
        return .init(success: false, output: "Unsupported workflow tool")
      }
    } catch {
      return .init(success: false, output: error.localizedDescription)
    }
  }

  private func executeStandaloneWorkflowStep(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    if PlatformExpansionAgentTools.handles(call)
      || RemindersAgentTools.handles(call)
      || AgentDelegationTools.handles(call)
    {
      return await executePlatformExpansionTool(call)
    }
    if MacNativeAgentTools.handles(call) {
      return await MacNativeAgentTools.execute(call: call)
    }
    if MacNativeMutationAgentTools.handles(call) {
      return await MacNativeMutationAgentTools.execute(call: call)
    }
    if PersistentAgentTools.handles(call) {
      return PersistentAgentTools.execute(call: call)
    }
    if GeneratedDocumentAgentTools.handles(call) {
      return await GeneratedDocumentAgentTools.execute(call: call)
    }
    if UnifiedContextAgentTools.handles(call) {
      return UnifiedContextAgentTools.execute(call: call, messages: messages)
    }
    if ConversationAttachmentAgentTools.handles(call) {
      return ConversationAttachmentAgentTools.execute(call: call, messages: messages)
    }
    if KnowledgeLibraryAgentTools.handles(call) {
      return await KnowledgeLibraryAgentTools.execute(
        call: call,
        workspacePath: configuration.workspacePath
      )
    }

    switch call.function.name {
    case "terminal_open":
      let command = expansionOptionalString("command", in: call)
      let title = expansionOptionalString("title", in: call) ?? "Workflow Terminal"
      openLocalTerminal(command: command, title: title)
      return .init(success: true, output: "Lokales Terminal wurde geöffnet.")

    case "ssh_list_hosts":
      return encodeExpansionResult(
        sshHosts.map {
          [
            "name": $0.name,
            "hostname": $0.hostname,
            "port": String($0.port),
            "username": $0.username,
          ]
        }
      )

    case "ssh_run":
      return await expansionRunSSH(call)

    case "ssh_open_terminal":
      return await expansionOpenSSHTerminal(call)

    case "coreml_list_models", "coreml_describe_model", "coreml_predict":
      return await executeStandaloneCoreMLTool(call)

    default:
      return await AgentRuntime().execute(
        call: call,
        workspacePath: configuration.workspacePath,
        permissionMode: configuration.permissionMode
      )
    }
  }

  private func executeStandaloneCoreMLTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      let service = CoreMLService()
      let snapshot = try await service.bootstrap()
      switch call.function.name {
      case "coreml_list_models":
        let activeID = snapshot.activeModelID
        return encodeExpansionResult(
          snapshot.models.map {
            ExpansionCoreMLModelDescriptor(
              id: $0.id.uuidString,
              name: $0.name,
              active: $0.id == activeID,
              inputs: $0.inputs,
              outputs: $0.outputs,
              computePolicy: $0.computeUnits
            )
          }
        )

      case "coreml_describe_model":
        let model = try await service.registeredModel(
          query: expansionOptionalString("model", in: call)
        )
        return encodeExpansionResult(
          ExpansionCoreMLModelDescriptor(
            id: model.id.uuidString,
            name: model.name,
            active: model.id == await service.activeModelID(),
            inputs: model.inputs,
            outputs: model.outputs,
            computePolicy: model.computeUnits
          )
        )

      case "coreml_predict":
        guard let input = call.function.arguments["input"]?.objectValue else {
          throw AgentRuntimeError.missingArgument(
            tool: call.function.name,
            name: "input"
          )
        }
        let data = try JSONEncoder().encode(JSONValue.object(input))
        let modelQuery = expansionOptionalString("model", in: call)
        let model = try await service.registeredModel(query: modelQuery)
        let result = try await service.predict(
          jsonInput: String(decoding: data, as: UTF8.self),
          modelQuery: modelQuery
        )
        return encodeExpansionResult(
          ExpansionCoreMLPredictionDescriptor(
            model: model.name,
            durationMilliseconds: result.durationMilliseconds,
            values: result.values
          )
        )

      default:
        return .init(success: false, output: "Unsupported Core ML workflow tool")
      }
    } catch {
      return .init(success: false, output: error.localizedDescription)
    }
  }

  private func executeAgentDelegationTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      let library = PersistentAgentLibrary.shared
      let profile = try library.resolve(
        try expansionRequiredString("agent", in: call)
      )
      guard profile.isEnabled else {
        throw PersistentAgentLibraryError.notFound(profile.name)
      }
      let task = try expansionRequiredString("task", in: call)
      let requestedTools = call.function.arguments["allow_tools"]?.boolValue
      let selectedProvider = profile.providerPreference.providerKind
        ?? configuration.providerKind

      let response: String
      switch selectedProvider {
      case .appleOnDevice:
        var delegateConfiguration = configuration
        delegateConfiguration.providerKind = .appleOnDevice
        delegateConfiguration.model = "Apple System Language Model"
        delegateConfiguration.agentEnabled = false
        delegateConfiguration.systemPrompt = configuration.systemPrompt
          + "\n\n" + profile.systemInstruction
        let event = try await AppleFoundationModelsProvider().complete(
          configuration: delegateConfiguration,
          messages: [ChatMessage(role: .user, content: task)]
        )
        response = event.contentDelta

      case .ollamaLocal, .ollamaCloud:
        var delegateConfiguration = configuration
        delegateConfiguration.providerKind = selectedProvider
        if profile.providerPreference != .current {
          delegateConfiguration.baseURL = selectedProvider.defaultBaseURL
          delegateConfiguration.model = selectedProvider == .ollamaLocal
            ? "qwen3:8b"
            : "glm-5.2"
        }
        delegateConfiguration.systemPrompt = configuration.systemPrompt
          + "\n\n" + profile.systemInstruction
        response = try await runDelegatedOllama(
          configuration: delegateConfiguration,
          task: task,
          useTools: requestedTools ?? true
        )
      }

      try library.markUsed(id: profile.id)
      return encodeExpansionResult(
        DelegatedAgentResultDescriptor(
          agent: profile.name,
          provider: selectedProvider.displayName,
          response: SecureSecretBroker.redact(
            String(response.prefix(60_000)),
            secrets: secrets
          )
        )
      )
    } catch {
      return .init(
        success: false,
        output: SecureSecretBroker.redact(error.localizedDescription, secrets: secrets)
      )
    }
  }

  private func runDelegatedOllama(
    configuration delegateConfiguration: AppConfiguration,
    task: String,
    useTools: Bool
  ) async throws -> String {
    let provider = OllamaProvider()
    let apiKey: String?
    if delegateConfiguration.providerKind == .ollamaCloud,
      let id = configuration.apiKeySecretID
    {
      apiKey = secrets.first(where: { $0.id == id })?.value
    } else {
      apiKey = nil
    }

    var providerMessages = [
      ProviderMessage(role: .system, content: delegateConfiguration.systemPrompt),
      ProviderMessage(role: .user, content: task),
    ]
    let tools = useTools
      ? AgentToolRegistry.ollamaDefinitions.filter {
        $0.function.name != "agent_delegate"
          && $0.function.name != "workflow_run"
      }
      : []

    var finalContent = ""
    for _ in 0..<4 {
      try Task.checkCancellation()
      var turnContent = ""
      var turnThinking = ""
      var calls: [ProviderToolCall] = []
      let stream = provider.streamChat(
        configuration: delegateConfiguration,
        apiKey: apiKey,
        messages: providerMessages,
        tools: tools
      )
      for try await event in stream {
        turnContent += event.contentDelta
        turnThinking += event.thinkingDelta
        for toolCall in event.toolCalls where !calls.contains(toolCall) {
          calls.append(toolCall)
        }
      }
      finalContent += turnContent
      providerMessages.append(
        ProviderMessage(
          role: .assistant,
          content: turnContent,
          thinking: turnThinking.isEmpty ? nil : turnThinking,
          toolCalls: calls.isEmpty ? nil : calls
        )
      )
      guard useTools, !calls.isEmpty else { break }
      for toolCall in calls {
        let result = await executeStandaloneWorkflowStep(toolCall)
        providerMessages.append(
          ProviderMessage(
            role: .tool,
            content: SecureSecretBroker.redact(result.output, secrets: secrets),
            toolName: toolCall.function.name
          )
        )
      }
    }
    return finalContent
  }

  private func executeUpdateCheckTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      let url = try expansionRequiredString("manifest_url", in: call)
      guard URL(string: url)?.scheme?.lowercased() == "https" else {
        throw SecureSecretBrokerError.unsupportedScheme(
          URL(string: url)?.scheme ?? ""
        )
      }
      let response = try await SecureHTTPClient().request(
        method: "GET",
        urlText: url,
        headers: [:],
        body: nil,
        secret: nil,
        secretUsage: nil,
        secretHeaderName: nil
      )
      guard (200...299).contains(response.statusCode),
        let data = response.body.data(using: .utf8),
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        return .init(
          success: false,
          output: "Update-Manifest konnte nicht gelesen werden (HTTP \(response.statusCode))."
        )
      }

      let current = currentVersionDescriptor()
      let availableVersion = object["version"] as? String
      let availableBuild = object["build"] as? Int
        ?? (object["build"] as? NSNumber)?.intValue
      return encodeExpansionResult(
        UpdateCheckDescriptor(
          currentVersion: current.version,
          currentBuild: current.build,
          availableVersion: availableVersion,
          availableBuild: availableBuild,
          updateAvailable: compareVersion(
            availableVersion,
            build: availableBuild,
            currentVersion: current.version,
            currentBuild: Int(current.build) ?? 0
          ),
          downloadURL: object["download_url"] as? String,
          notes: object["notes"] as? String
        )
      )
    } catch {
      return .init(success: false, output: error.localizedDescription)
    }
  }

  private func expansionCommand(_ command: String) async -> ToolExecutionResult {
    await AgentRuntime().executeCommand(
      command,
      workspacePath: configuration.workspacePath
    )
  }

  private func expansionResolveSSHHost(_ query: String) throws -> SSHHost {
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

  private func expansionAuthenticationSecrets(
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

  private func validatedLocalURL(
    _ path: String,
    mustExist: Bool,
    createParent: Bool = false
  ) throws -> URL {
    let expanded = NSString(string: path).expandingTildeInPath
    let workspace = URL(
      fileURLWithPath: NSString(string: configuration.workspacePath).expandingTildeInPath
    ).standardizedFileURL.resolvingSymlinksInPath()
    let rawCandidate = URL(
      fileURLWithPath: expanded.hasPrefix("/")
        ? expanded
        : workspace.appendingPathComponent(expanded).path
    ).standardizedFileURL

    let checked: URL
    if FileManager.default.fileExists(atPath: rawCandidate.path) {
      checked = rawCandidate.resolvingSymlinksInPath()
      if mustExist == false,
        let values = try? rawCandidate.resourceValues(forKeys: [.isDirectoryKey]),
        values.isDirectory == true
      {
        throw CocoaError(.fileWriteFileExists)
      }
    } else {
      guard !mustExist else { throw CocoaError(.fileNoSuchFile) }
      var parent = rawCandidate.deletingLastPathComponent()
      if createParent {
        try FileManager.default.createDirectory(
          at: parent,
          withIntermediateDirectories: true
        )
      }
      guard FileManager.default.fileExists(atPath: parent.path) else {
        throw CocoaError(.fileNoSuchFile)
      }
      parent = parent.resolvingSymlinksInPath()
      checked = parent
        .appendingPathComponent(rawCandidate.lastPathComponent, isDirectory: false)
        .standardizedFileURL
    }

    if configuration.permissionMode != .fullAccess {
      try enforceWorkspaceBoundary(checked, workspace: workspace)
      let parent = checked.deletingLastPathComponent().resolvingSymlinksInPath()
      try enforceWorkspaceBoundary(parent, workspace: workspace)
    }
    return checked
  }

  private func enforceWorkspaceBoundary(_ url: URL, workspace: URL) throws {
    let pathValue = url.standardizedFileURL.path
    let workspacePath = workspace.standardizedFileURL.path
    guard pathValue == workspacePath || pathValue.hasPrefix(workspacePath + "/") else {
      throw AgentRuntimeError.pathOutsideWorkspace(pathValue)
    }
  }

  private func validateRemotePath(_ path: String) throws {
    let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-~"
    )
    let segments = normalized.split(separator: "/", omittingEmptySubsequences: false)
    guard !normalized.isEmpty,
      !normalized.contains("\n"),
      !normalized.contains("\r"),
      normalized.unicodeScalars.allSatisfy({ allowed.contains($0) }),
      !segments.contains(where: { $0 == ".." })
    else {
      throw SSHLaunchServiceError.emptyTransferPath
    }
  }

  private func rejectEmbeddedSecrets(in call: ProviderToolCall) throws {
    let rendered = call.function.arguments.keys.sorted().map { key in
      "\(key)=\(call.function.arguments[key]?.compactDescription ?? "null")"
    }.joined(separator: "&")
    for secret in secrets where secret.value.count >= 4 {
      if rendered.contains(secret.value) {
        throw AgentWorkflowError.unsafeSecretArgument("embedded_secret_value")
      }
    }
  }

  private func expansionCleanup(_ paths: [URL]) {
    for path in paths {
      try? FileManager.default.removeItem(at: path)
    }
  }

  private func currentVersionDescriptor() -> AppVersionDescriptor {
    AppVersionDescriptor(
      version: Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String ?? "1.1.0",
      build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        ?? "24",
      bundleIdentifier: Bundle.main.bundleIdentifier ?? AppPaths.bundleIdentifier
    )
  }

  private func compareVersion(
    _ candidate: String?,
    build candidateBuild: Int?,
    currentVersion: String,
    currentBuild: Int
  ) -> Bool {
    guard let candidate, !candidate.isEmpty else { return false }
    let comparison = candidate.compare(currentVersion, options: .numeric)
    if comparison == .orderedDescending { return true }
    if comparison == .orderedAscending { return false }
    return (candidateBuild ?? 0) > currentBuild
  }

  private func expansionRequiredString(
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

  private func expansionOptionalString(
    _ name: String,
    in call: ProviderToolCall,
    allowEmpty: Bool = false
  ) -> String? {
    guard let value = call.function.arguments[name]?.stringValue else { return nil }
    if allowEmpty { return value }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }

  private func expansionOptionalInt(
    _ name: String,
    in call: ProviderToolCall
  ) -> Int? {
    guard let value = call.function.arguments[name],
      case .number(let number) = value,
      number.isFinite
    else {
      return nil
    }
    return Int(number)
  }

  private func encodeExpansionResult<T: Encodable>(_ value: T) -> ToolExecutionResult {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
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

  private func appleScriptLiteral(_ value: String) -> String {
    var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
    escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
    escaped = escaped.replacingOccurrences(of: "\r\n", with: "\\n")
    escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
    escaped = escaped.replacingOccurrences(of: "\r", with: "\\n")
    return "\"\(escaped)\""
  }
}

private extension ProcessInfo {
  var machineArchitecture: String {
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafePointer(to: &systemInfo.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) {
        String(cString: $0)
      }
    }
  }
}
