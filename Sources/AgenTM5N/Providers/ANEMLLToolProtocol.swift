import Foundation

public enum ANEMLLToolProtocolError: LocalizedError, Equatable {
  case unknownTool(String)
  case malformedEnvelope
  case multipleToolCalls

  public var errorDescription: String? {
    switch self {
    case .unknownTool(let name):
      return L10n.text(
        de: "Qwen3 hat ein nicht freigegebenes AgenTM5N-Werkzeug angefordert: \(name)",
        en: "Qwen3 requested an AgenTM5N tool that was not advertised: \(name)",
        fr: "Qwen3 a demandé un outil AgenTM5N qui n’était pas autorisé : \(name)"
      )
    case .malformedEnvelope:
      return L10n.text(
        de: "Der strukturierte Qwen3-Werkzeugaufruf ist ungültig.",
        en: "The structured Qwen3 tool call is invalid.",
        fr: "L’appel d’outil structuré de Qwen3 n’est pas valide."
      )
    case .multipleToolCalls:
      return L10n.text(
        de: "Qwen3 darf in einer ANEMLL-Runde nur ein Werkzeug anfordern.",
        en: "Qwen3 may request only one tool per ANEMLL round.",
        fr: "Qwen3 ne peut demander qu’un seul outil par tour ANEMLL."
      )
    }
  }
}

public struct ANEMLLToolTransportRequest: Equatable, Sendable {
  public let prompt: String
  public let userTurnCount: Int
  public let isFreshConversation: Bool
  public let isToolContinuation: Bool

  public init(
    prompt: String,
    userTurnCount: Int,
    isFreshConversation: Bool,
    isToolContinuation: Bool
  ) {
    self.prompt = prompt
    self.userTurnCount = userTurnCount
    self.isFreshConversation = isFreshConversation
    self.isToolContinuation = isToolContinuation
  }
}

public enum ANEMLLToolProtocol {
  public static let callPrefix = "<agentm5n_tool_call>"
  public static let callSuffix = "</agentm5n_tool_call>"
  public static let maximumToolsPerTurn = 6
  public static let maximumToolResultCharacters = 1_400

  private struct Envelope: Decodable {
    let name: String
    let arguments: [String: JSONValue]?
  }

  public static func selectTools(
    _ tools: [ProviderToolDefinition],
    messages: [ProviderMessage],
    operatingConfiguration: AgentOperatingLayerConfiguration
  ) -> [ProviderToolDefinition] {
    guard !tools.isEmpty else { return [] }

    let allowedCapabilities = operatingConfiguration.enabledCapabilities
    let prompt = latestUserText(messages).lowercased()
    var candidates = tools.filter { definition in
      guard let entry = AgentToolRegistry.entry(named: definition.function.name) else {
        return false
      }
      guard allowedCapabilities.contains(entry.capability) else { return false }
      if !operatingConfiguration.bundledToolsEnabled,
        BundledToolPackInstaller.isBundledToolName(definition.function.name)
      {
        return false
      }
      return true
    }

    candidates.sort { lhs, rhs in
      let left = priority(lhs, prompt: prompt)
      let right = priority(rhs, prompt: prompt)
      if left != right { return left < right }
      return lhs.function.name.localizedCaseInsensitiveCompare(rhs.function.name) == .orderedAscending
    }

    let configuredLimit = max(1, operatingConfiguration.maxAdvertisedTools)
    let limit = min(Self.maximumToolsPerTurn, configuredLimit)
    return Array(candidates.prefix(limit))
  }

  public static func makeTransportRequest(
    messages: [ProviderMessage],
    tools: [ProviderToolDefinition]
  ) throws -> ANEMLLToolTransportRequest {
    let userTurnCount = messages.reduce(into: 0) { count, message in
      if message.role == .user { count += 1 }
    }
    let hasAssistantHistory = messages.contains { $0.role == .assistant }

    let trailingTools = Array(
      messages.reversed().prefix { $0.role == .tool }.reversed()
    )
    if !trailingTools.isEmpty {
      let resultText = trailingTools.suffix(2).map { message in
        let name = message.toolName ?? "unknown"
        return "TOOL RESULT [\(name)]:\n\(bounded(message.content, limit: maximumToolResultCharacters / 2))"
      }.joined(separator: "\n\n")
      let prompt = toolCatalogPrefix(tools)
        + resultText
        + "\n\nContinue the original user task. Use another advertised tool only if necessary; otherwise answer from the real tool result."
      return ANEMLLToolTransportRequest(
        prompt: prompt,
        userTurnCount: max(1, userTurnCount),
        isFreshConversation: false,
        isToolContinuation: true
      )
    }

    guard let userMessage = messages.last(where: { $0.role == .user }) else {
      throw ANEMLLRuntimeError.missingPrompt
    }
    let userText = PromptAttachmentService.providerPrompt(from: userMessage.content)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !userText.isEmpty else { throw ANEMLLRuntimeError.missingPrompt }

    return ANEMLLToolTransportRequest(
      prompt: toolCatalogPrefix(tools) + userText,
      userTurnCount: max(1, userTurnCount),
      isFreshConversation: userTurnCount <= 1 && !hasAssistantHistory,
      isToolContinuation: false
    )
  }

  public static func parseToolCalls(
    from response: String,
    allowedTools: [ProviderToolDefinition]
  ) throws -> [ProviderToolCall] {
    guard !allowedTools.isEmpty else { return [] }
    let visible = removingThinkingBlocks(response)
    var payloads: [String] = []
    var cursor = visible.startIndex

    while let start = visible.range(of: callPrefix, range: cursor..<visible.endIndex) {
      guard let end = visible.range(of: callSuffix, range: start.upperBound..<visible.endIndex) else {
        throw ANEMLLToolProtocolError.malformedEnvelope
      }
      payloads.append(
        String(visible[start.upperBound..<end.lowerBound])
          .trimmingCharacters(in: .whitespacesAndNewlines)
      )
      cursor = end.upperBound
    }

    guard !payloads.isEmpty else { return [] }
    guard payloads.count == 1, let payload = payloads.first else {
      throw ANEMLLToolProtocolError.multipleToolCalls
    }
    guard let data = payload.data(using: .utf8),
      let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
    else {
      throw ANEMLLToolProtocolError.malformedEnvelope
    }

    let allowedNames = Set(allowedTools.map { $0.function.name })
    guard allowedNames.contains(envelope.name) else {
      throw ANEMLLToolProtocolError.unknownTool(envelope.name)
    }

    return [
      ProviderToolCall(
        function: .init(
          index: 0,
          name: envelope.name,
          arguments: envelope.arguments ?? [:]
        )
      )
    ]
  }

  public static func toolCatalogPrefix(_ tools: [ProviderToolDefinition]) -> String {
    guard !tools.isEmpty else { return "" }
    let catalog = tools.map { definition in
      let arguments = argumentNames(definition.function.parameters)
      let signature = arguments.isEmpty
        ? definition.function.name + "()"
        : definition.function.name + "(" + arguments.joined(separator: ",") + ")"
      let description = bounded(
        definition.function.description.replacingOccurrences(of: "\n", with: " "),
        limit: 96
      )
      return "- \(signature): \(description)"
    }.joined(separator: "\n")

    return """
    AGEN TM5N TOOLS AVAILABLE FOR THIS TURN:
    \(catalog)
    If a real action or data lookup requires one of these tools, output ONLY one exact envelope and no prose:
    \(callPrefix){"name":"tool_name","arguments":{}}\(callSuffix)
    Never invent a tool name. Use at most one tool per round. Otherwise answer normally.

    USER/TASK INPUT:
    """
  }

  public static func removeToolEnvelopes(from response: String) -> String {
    var result = response
    while let start = result.range(of: callPrefix) {
      guard let end = result.range(of: callSuffix, range: start.upperBound..<result.endIndex) else {
        break
      }
      result.removeSubrange(start.lowerBound..<end.upperBound)
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func latestUserText(_ messages: [ProviderMessage]) -> String {
    messages.last(where: { $0.role == .user })?.content ?? ""
  }

  private static func argumentNames(_ parameters: JSONValue) -> [String] {
    guard case .object(let root) = parameters,
      case .object(let properties)? = root["properties"]
    else {
      return []
    }
    return properties.keys.sorted()
  }

  private static func priority(
    _ tool: ProviderToolDefinition,
    prompt: String
  ) -> Int {
    let name = tool.function.name.lowercased()
    let description = tool.function.description.lowercased()
    let affinity: [([String], [String])] = [
      (["kalender", "calendar", "termin", "event"], ["calendar"]),
      (["mail", "email", "e-mail"], ["mail"]),
      (["kontakt", "contact"], ["contact"]),
      (["reminder", "erinnerung"], ["reminder"]),
      (["ssh", "server", "remote", "host"], ["ssh"]),
      (["docker", "container", "compose"], ["docker"]),
      (["git", "commit", "branch", "diff"], ["git"]),
      (["datei", "file", "ordner", "folder"], ["file", "read", "list", "glob", "search"]),
      (["terminal", "shell", "command", "befehl"], ["terminal", "command", "shell"]),
      (["clipboard", "zwischenablage"], ["clipboard"]),
      (["shortcut", "kurzbefehl"], ["shortcut"]),
    ]

    for (keywords, fragments) in affinity
    where keywords.contains(where: { prompt.contains($0) })
      && fragments.contains(where: { name.contains($0) || description.contains($0) })
    {
      return 0
    }

    let promptWords = Set(
      prompt.split { !$0.isLetter && !$0.isNumber }
        .map(String.init)
        .filter { $0.count >= 4 }
    )
    if promptWords.contains(where: { name.contains($0) }) { return 1 }
    if promptWords.contains(where: { description.contains($0) }) { return 2 }
    return 3
  }

  private static func removingThinkingBlocks(_ value: String) -> String {
    var result = value
    while let start = result.range(of: "<think>") {
      guard let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) else {
        return String(result[..<start.lowerBound])
      }
      result.removeSubrange(start.lowerBound..<end.upperBound)
    }
    return result
  }

  private static func bounded(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    return String(value.prefix(limit)) + "…"
  }
}

public final class ANEMLLToolEnvelopeFilter: @unchecked Sendable {
  private let lock = NSLock()
  private var buffer = ""
  private var capturing = false
  private var capturedPayload = ""

  public init() {}

  public func consume(_ delta: String) -> String {
    lock.lock()
    defer { lock.unlock() }
    buffer += delta
    return drain(flushAll: false)
  }

  public func finish() -> String {
    lock.lock()
    defer { lock.unlock() }
    return drain(flushAll: true)
  }

  private func drain(flushAll: Bool) -> String {
    var visible = ""

    while !buffer.isEmpty {
      if capturing {
        if let end = buffer.range(of: ANEMLLToolProtocol.callSuffix) {
          capturedPayload += String(buffer[..<end.lowerBound])
          buffer.removeSubrange(buffer.startIndex..<end.upperBound)
          capturing = false
          capturedPayload = ""
          continue
        }
        if flushAll {
          visible += ANEMLLToolProtocol.callPrefix + capturedPayload + buffer
          buffer.removeAll(keepingCapacity: true)
          capturedPayload = ""
          capturing = false
        }
        break
      }

      if let start = buffer.range(of: ANEMLLToolProtocol.callPrefix) {
        visible += String(buffer[..<start.lowerBound])
        buffer.removeSubrange(buffer.startIndex..<start.upperBound)
        capturing = true
        continue
      }

      if flushAll {
        visible += buffer
        buffer.removeAll(keepingCapacity: true)
        break
      }

      let retained = longestSuffixMatchingPrefix(
        marker: ANEMLLToolProtocol.callPrefix,
        value: buffer
      )
      let emitCount = buffer.count - retained
      guard emitCount > 0 else { break }
      let boundary = buffer.index(buffer.startIndex, offsetBy: emitCount)
      visible += String(buffer[..<boundary])
      buffer.removeSubrange(buffer.startIndex..<boundary)
    }

    return visible
  }

  private func longestSuffixMatchingPrefix(marker: String, value: String) -> Int {
    let maximum = min(max(marker.count - 1, 0), value.count)
    guard maximum > 0 else { return 0 }
    for count in stride(from: maximum, through: 1, by: -1) {
      if marker.hasPrefix(value.suffix(count)) { return count }
    }
    return 0
  }
}
