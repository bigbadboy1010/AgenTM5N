import Foundation

public enum ANEMLLPersistentRuntimeError: LocalizedError {
  case timeout(Int)
  case protocolFailure(String)
  case processStopped(String)
  case inputWriteFailed(String)

  public var errorDescription: String? {
    switch self {
    case .timeout(let seconds):
      return L10n.text(
        de: "Die persistente ANEMLL-Runtime hat nach \(seconds) Sekunden nicht geantwortet.",
        en: "The persistent ANEMLL runtime did not respond within \(seconds) seconds.",
        fr: "Le runtime ANEMLL persistant n’a pas répondu dans les \(seconds) secondes."
      )
    case .protocolFailure(let detail):
      return L10n.text(
        de: "Das ANEMLL-Chatprotokoll konnte nicht ausgewertet werden: \(detail)",
        en: "The ANEMLL chat protocol could not be parsed: \(detail)",
        fr: "Le protocole de chat ANEMLL n’a pas pu être analysé : \(detail)"
      )
    case .processStopped(let detail):
      return L10n.text(
        de: "Die persistente ANEMLL-Runtime wurde unerwartet beendet: \(detail)",
        en: "The persistent ANEMLL runtime stopped unexpectedly: \(detail)",
        fr: "Le runtime ANEMLL persistant s’est arrêté de manière inattendue : \(detail)"
      )
    case .inputWriteFailed(let detail):
      return L10n.text(
        de: "Die Anfrage konnte nicht an ANEMLL gesendet werden: \(detail)",
        en: "The request could not be sent to ANEMLL: \(detail)",
        fr: "La requête n’a pas pu être envoyée à ANEMLL : \(detail)"
      )
    }
  }
}

public struct ANEMLLPersistentSessionSignature: Equatable, Sendable {
  public let helperPath: String
  public let metaPath: String
  public let systemPrompt: String
  public let thinkingEnabled: Bool
  public let maxTokens: Int
  public let temperature: Double

  public init(
    helperPath: String,
    metaPath: String,
    systemPrompt: String,
    thinkingEnabled: Bool,
    maxTokens: Int,
    temperature: Double
  ) {
    self.helperPath = helperPath
    self.metaPath = metaPath
    self.systemPrompt = systemPrompt
    self.thinkingEnabled = thinkingEnabled
    self.maxTokens = maxTokens
    self.temperature = temperature
  }
}

public struct ANEMLLInteractiveTurn: Equatable, Sendable {
  public let response: String
  public let diagnosticOutput: String

  public init(response: String, diagnosticOutput: String) {
    self.response = response
    self.diagnosticOutput = diagnosticOutput
  }
}

public enum ANEMLLInteractiveProtocol {
  public static let promptMarker = "You:"
  public static let assistantMarker = "Assistant:"

  public static func normalizePrompt(_ prompt: String) throws -> String {
    var value = PromptAttachmentService.providerPrompt(from: prompt)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      throw ANEMLLRuntimeError.missingPrompt
    }

    value = value
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(of: "\n", with: "\u{2028}")

    // The upstream interactive CLI reserves slash-prefixed input for commands.
    // WORD JOINER keeps the user's text intact for the tokenizer while avoiding
    // accidental command dispatch such as /t.
    if value.hasPrefix("/") {
      value = "\u{2060}" + value
    }
    return value
  }

  public static func containsPromptMarker(_ rawOutput: String) -> Bool {
    let clean = stripANSI(rawOutput)
    return clean.contains("\n\(promptMarker)")
      || clean.hasSuffix(promptMarker)
      || clean.hasSuffix("\(promptMarker) ")
  }

  public static func parseTurn(_ rawOutput: String) throws -> ANEMLLInteractiveTurn {
    let clean = stripANSI(rawOutput)
    guard let assistantRange = clean.range(of: assistantMarker) else {
      throw ANEMLLPersistentRuntimeError.protocolFailure(
        "Assistant-Marker fehlt"
      )
    }

    let afterAssistant = assistantRange.upperBound..<clean.endIndex
    let metricsRange = clean.range(
      of: "\\n[0-9]+(?:\\.[0-9]+)?\\s+t/s,\\s*TTFT:",
      options: .regularExpression,
      range: afterAssistant
    )
    let nextPrompt = clean.range(
      of: "\n\(promptMarker)",
      range: afterAssistant
    )
    let responseEnd = earliestIndex(
      metricsRange?.lowerBound,
      nextPrompt?.lowerBound,
      fallback: clean.endIndex
    )
    let response = String(clean[assistantRange.upperBound..<responseEnd])
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !response.isEmpty else {
      throw ANEMLLRuntimeError.emptyResponse
    }

    return ANEMLLInteractiveTurn(
      response: response,
      diagnosticOutput: clean.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }

  /// Returns only assistant text that is safe to expose while the upstream CLI
  /// is still generating. Diagnostic throughput output and the next `You:`
  /// prompt are deliberately excluded so they can never leak into chat text.
  public static func streamableAssistantText(_ rawOutput: String) -> String {
    let clean = stripANSI(rawOutput)
    guard let assistantRange = clean.range(of: assistantMarker) else {
      return ""
    }

    let afterAssistant = assistantRange.upperBound..<clean.endIndex
    let metricsRange = clean.range(
      of: "\\n[0-9]+(?:\\.[0-9]+)?\\s+t/s,\\s*TTFT:",
      options: .regularExpression,
      range: afterAssistant
    )
    let nextPrompt = clean.range(
      of: "\n\(promptMarker)",
      range: afterAssistant
    )
    var responseEnd = earliestIndex(
      metricsRange?.lowerBound,
      nextPrompt?.lowerBound,
      fallback: clean.endIndex
    )

    // The metrics line can arrive split across pipe reads. Until its `t/s,
    // TTFT:` marker is complete, hold back a short numeric-looking final line
    // so fragments such as `84.7 t/` are not rendered as model text. Once the
    // next prompt is present, the exact response boundary is authoritative.
    if metricsRange == nil, nextPrompt == nil {
      let candidate = String(clean[assistantRange.upperBound..<responseEnd])
      if let heldBoundary = potentialMetricsBoundary(in: candidate) {
        responseEnd = clean.index(
          assistantRange.upperBound,
          offsetBy: candidate.distance(from: candidate.startIndex, to: heldBoundary)
        )
      }
    }

    return String(clean[assistantRange.upperBound..<responseEnd])
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func stripANSI(_ value: String) -> String {
    guard let expression = try? NSRegularExpression(
      pattern: "\\u001B\\[[0-9;?]*[ -/]*[@-~]"
    ) else {
      return value
    }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return expression.stringByReplacingMatches(
      in: value,
      range: range,
      withTemplate: ""
    )
  }

  private static func earliestIndex(
    _ lhs: String.Index?,
    _ rhs: String.Index?,
    fallback: String.Index
  ) -> String.Index {
    switch (lhs, rhs) {
    case let (lhs?, rhs?): min(lhs, rhs)
    case let (lhs?, nil): lhs
    case let (nil, rhs?): rhs
    case (nil, nil): fallback
    }
  }

  private static func potentialMetricsBoundary(in response: String) -> String.Index? {
    guard let newline = response.lastIndex(of: "\n") else { return nil }
    let suffixStart = response.index(after: newline)
    let suffix = response[suffixStart...]
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !suffix.isEmpty, suffix.count <= 96, suffix.first?.isNumber == true else {
      return nil
    }

    let allowedLetters = CharacterSet(charactersIn: "tTsSfFmM")
    let allowedPunctuation = CharacterSet(charactersIn: ".,/:()[]%+- ")
    let isMetricsLike = suffix.unicodeScalars.allSatisfy { scalar in
      CharacterSet.decimalDigits.contains(scalar)
        || allowedLetters.contains(scalar)
        || allowedPunctuation.contains(scalar)
    }
    return isMetricsLike ? newline : nil
  }
}

private final class ANEMLLPersistentProcessBox: @unchecked Sendable {
  private let lock = NSLock()
  private var process: Process?

  func install(_ process: Process) {
    lock.lock()
    self.process = process
    lock.unlock()
  }

  func clear() {
    lock.lock()
    process = nil
    lock.unlock()
  }

  func terminate() {
    lock.lock()
    let current = process
    lock.unlock()
    if current?.isRunning == true {
      current?.terminate()
    }
  }
}

public actor ANEMLLPersistentRuntimeService {
  public static let shared = ANEMLLPersistentRuntimeService()

  private var process: Process?
  private var inputPipe: Pipe?
  private var outputPipe: Pipe?
  private var processBox = ANEMLLPersistentProcessBox()
  private var signature: ANEMLLPersistentSessionSignature?
  private var descriptor: ANEMLLModelBundleDescriptor?
  private var startupOutput = ""
  private var conversationTurns = 0
  private var modelLoadReported = false

  public init() {}

  public func complete(
    prompt: String,
    systemPrompt: String,
    thinkingEnabled: Bool,
    maxTokens: Int,
    temperature: Double,
    requestTimeoutSeconds: Int,
    userTurnCount: Int,
    runtimeConfiguration: ANEMLLRuntimeConfiguration
  ) async throws -> ANEMLLRuntimeResult {
    try await completeInternal(
      prompt: prompt,
      systemPrompt: systemPrompt,
      thinkingEnabled: thinkingEnabled,
      maxTokens: maxTokens,
      temperature: temperature,
      requestTimeoutSeconds: requestTimeoutSeconds,
      userTurnCount: userTurnCount,
      runtimeConfiguration: runtimeConfiguration,
      onAssistantDelta: nil
    )
  }

  public func completeStreaming(
    prompt: String,
    systemPrompt: String,
    thinkingEnabled: Bool,
    maxTokens: Int,
    temperature: Double,
    requestTimeoutSeconds: Int,
    userTurnCount: Int,
    runtimeConfiguration: ANEMLLRuntimeConfiguration,
    onAssistantDelta: @escaping @Sendable (String) -> Void
  ) async throws -> ANEMLLRuntimeResult {
    try await completeInternal(
      prompt: prompt,
      systemPrompt: systemPrompt,
      thinkingEnabled: thinkingEnabled,
      maxTokens: maxTokens,
      temperature: temperature,
      requestTimeoutSeconds: requestTimeoutSeconds,
      userTurnCount: userTurnCount,
      runtimeConfiguration: runtimeConfiguration,
      onAssistantDelta: onAssistantDelta
    )
  }

  public func resetConversation() {
    shutdownInternal()
  }

  public func shutdown() {
    shutdownInternal()
  }

  public func isRunning() -> Bool {
    process?.isRunning == true
  }

  public func activeTurns() -> Int {
    conversationTurns
  }

  private func completeInternal(
    prompt: String,
    systemPrompt: String,
    thinkingEnabled: Bool,
    maxTokens: Int,
    temperature: Double,
    requestTimeoutSeconds: Int,
    userTurnCount: Int,
    runtimeConfiguration: ANEMLLRuntimeConfiguration,
    onAssistantDelta: (@Sendable (String) -> Void)?
  ) async throws -> ANEMLLRuntimeResult {
    let normalizedPrompt = try ANEMLLInteractiveProtocol.normalizePrompt(prompt)
    let helperPath = ANEMLLRuntimeStore.expanded(runtimeConfiguration.helperPath)
    let manager = FileManager.default
    guard manager.fileExists(atPath: helperPath) else {
      throw ANEMLLRuntimeError.helperUnavailable(helperPath)
    }
    guard manager.isExecutableFile(atPath: helperPath) else {
      throw ANEMLLRuntimeError.helperNotExecutable(helperPath)
    }

    let modelDescriptor = try ANEMLLModelBundleInspector.inspect(
      metaPath: runtimeConfiguration.metaPath
    )
    let boundedMaxTokens = max(1, min(maxTokens, modelDescriptor.contextLength ?? 4_096))
    let boundedTemperature = max(0, min(temperature, 2))
    let timeout = max(30, min(requestTimeoutSeconds, 3_600))
    let requestedSignature = ANEMLLPersistentSessionSignature(
      helperPath: helperPath,
      metaPath: modelDescriptor.metaURL.path,
      systemPrompt: systemPrompt,
      thinkingEnabled: thinkingEnabled,
      maxTokens: boundedMaxTokens,
      temperature: boundedTemperature
    )

    if shouldRestart(
      requestedSignature: requestedSignature,
      requestedUserTurnCount: userTurnCount
    ) {
      shutdownInternal()
    }

    if process?.isRunning != true {
      try await start(
        signature: requestedSignature,
        descriptor: modelDescriptor,
        timeoutSeconds: timeout
      )
    }

    guard let process, process.isRunning,
      let inputPipe,
      let outputPipe
    else {
      throw ANEMLLPersistentRuntimeError.processStopped("Prozess ist nicht aktiv")
    }

    let payload = Data((normalizedPrompt + "\n").utf8)
    do {
      try inputPipe.fileHandleForWriting.write(contentsOf: payload)
    } catch {
      shutdownInternal()
      throw ANEMLLPersistentRuntimeError.inputWriteFailed(error.localizedDescription)
    }

    let startedAt = Date.timeIntervalSinceReferenceDate
    let output: String
    do {
      output = try await readUntilPrompt(
        handle: outputPipe.fileHandleForReading,
        timeoutSeconds: timeout,
        onAssistantDelta: onAssistantDelta
      )
    } catch {
      shutdownInternal()
      throw error
    }
    try Task.checkCancellation()

    guard process.isRunning else {
      let termination = "Exit \(process.terminationStatus)"
      shutdownInternal()
      throw ANEMLLPersistentRuntimeError.processStopped(termination)
    }

    let wallMilliseconds = max(
      0,
      (Date.timeIntervalSinceReferenceDate - startedAt) * 1_000
    )
    let turn = try ANEMLLInteractiveProtocol.parseTurn(output)
    let metricSource: String
    if modelLoadReported {
      metricSource = output
    } else {
      metricSource = startupOutput + "\n" + output
      modelLoadReported = true
    }
    let metrics = ANEMLLNativeRuntime.parseMetrics(
      metricSource,
      wallMilliseconds: wallMilliseconds
    )

    conversationTurns = max(conversationTurns + 1, userTurnCount)
    descriptor = modelDescriptor
    return ANEMLLRuntimeResult(
      response: turn.response,
      diagnosticOutput: turn.diagnosticOutput,
      metrics: metrics,
      descriptor: modelDescriptor
    )
  }

  private func shouldRestart(
    requestedSignature: ANEMLLPersistentSessionSignature,
    requestedUserTurnCount: Int
  ) -> Bool {
    guard process?.isRunning == true else { return false }
    guard signature == requestedSignature else { return true }

    // AppState starts a new conversation with one user turn. If the helper
    // already owns prior turns, restart it so its hidden conversation does not
    // leak into the new AgenTM5N session.
    if requestedUserTurnCount <= 1, conversationTurns > 0 {
      return true
    }
    if requestedUserTurnCount < conversationTurns {
      return true
    }
    return false
  }

  private func start(
    signature: ANEMLLPersistentSessionSignature,
    descriptor: ANEMLLModelBundleDescriptor,
    timeoutSeconds: Int
  ) async throws {
    let process = Process()
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: signature.helperPath)
    process.arguments = makeInteractiveArguments(signature: signature)
    process.currentDirectoryURL = descriptor.modelDirectory
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = outputPipe
    process.environment = ProcessInfo.processInfo.environment.merging(
      ["NSUnbufferedIO": "YES"]
    ) { _, new in new }

    processBox = ANEMLLPersistentProcessBox()
    processBox.install(process)
    do {
      try process.run()
    } catch {
      processBox.clear()
      throw error
    }

    self.process = process
    self.inputPipe = inputPipe
    self.outputPipe = outputPipe
    self.signature = signature
    self.descriptor = descriptor
    conversationTurns = 0
    modelLoadReported = false

    do {
      startupOutput = try await readUntilPrompt(
        handle: outputPipe.fileHandleForReading,
        timeoutSeconds: timeoutSeconds,
        onAssistantDelta: nil
      )
    } catch {
      shutdownInternal()
      throw error
    }

    guard process.isRunning else {
      let output = ANEMLLInteractiveProtocol.stripANSI(startupOutput)
      shutdownInternal()
      throw ANEMLLPersistentRuntimeError.processStopped(output)
    }
  }

  private func makeInteractiveArguments(
    signature: ANEMLLPersistentSessionSignature
  ) -> [String] {
    var arguments = [
      "--meta", signature.metaPath,
      "--max-tokens", String(signature.maxTokens),
      "--temperature", String(format: "%.4f", signature.temperature),
      "--template", "auto",
    ]
    let system = signature.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if !system.isEmpty {
      arguments.append(contentsOf: ["--system", system])
    }
    if signature.thinkingEnabled {
      arguments.append("--thinking-mode")
    }
    return arguments
  }

  private func readUntilPrompt(
    handle: FileHandle,
    timeoutSeconds: Int,
    onAssistantDelta: (@Sendable (String) -> Void)?
  ) async throws -> String {
    let box = processBox
    return try await withTaskCancellationHandler {
      try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask {
          var data = Data()
          var emittedAssistantText = ""
          let maximumBytes = 8 * 1_024 * 1_024
          while true {
            try Task.checkCancellation()
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
              let output = String(decoding: data, as: UTF8.self)
              throw ANEMLLPersistentRuntimeError.processStopped(
                ANEMLLInteractiveProtocol.stripANSI(output)
              )
            }
            data.append(chunk)
            let output = String(decoding: data, as: UTF8.self)

            if let onAssistantDelta {
              let visible = ANEMLLInteractiveProtocol.streamableAssistantText(output)
              if visible.hasPrefix(emittedAssistantText) {
                let delta = String(visible.dropFirst(emittedAssistantText.count))
                if !delta.isEmpty {
                  onAssistantDelta(delta)
                  emittedAssistantText = visible
                }
              }
            }

            if ANEMLLInteractiveProtocol.containsPromptMarker(output) {
              return output
            }
            if data.count > maximumBytes {
              throw ANEMLLPersistentRuntimeError.protocolFailure(
                "Ausgabe überschreitet 8 MiB ohne Prompt-Marker"
              )
            }
          }
        }
        group.addTask {
          try await Task.sleep(for: .seconds(timeoutSeconds))
          throw ANEMLLPersistentRuntimeError.timeout(timeoutSeconds)
        }

        do {
          guard let first = try await group.next() else {
            throw ANEMLLPersistentRuntimeError.protocolFailure("Kein Reader-Ergebnis")
          }
          group.cancelAll()
          return first
        } catch {
          box.terminate()
          group.cancelAll()
          throw error
        }
      }
    } onCancel: {
      box.terminate()
    }
  }

  private func shutdownInternal() {
    processBox.terminate()
    try? inputPipe?.fileHandleForWriting.close()
    try? outputPipe?.fileHandleForReading.close()
    processBox.clear()
    process = nil
    inputPipe = nil
    outputPipe = nil
    signature = nil
    descriptor = nil
    startupOutput = ""
    conversationTurns = 0
    modelLoadReported = false
  }
}
