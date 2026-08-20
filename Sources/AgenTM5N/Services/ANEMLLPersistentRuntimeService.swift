import Darwin
import Foundation

public enum ANEMLLPersistentRuntimeError: LocalizedError {
  case timeout(Int)
  case protocolFailure(String)
  case processStopped(String)
  case inputWriteFailed(String)
  case cleanupUnconfirmed

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
    case .cleanupUnconfirmed:
      return L10n.text(
        de: "Der ANEMLL-Hilfsprozess hat seinen Exit auch nach SIGKILL nicht bestätigt. AgenTM5N blockiert weitere schwere lokale Inferenz, bis die Runtime sicher bereinigt wurde.",
        en: "The ANEMLL helper did not confirm exit even after SIGKILL. AgenTM5N is blocking further heavy local inference until the runtime is safely cleaned up.",
        fr: "Le processus auxiliaire ANEMLL n’a pas confirmé son arrêt même après SIGKILL. AgenTM5N bloque toute nouvelle inférence locale lourde jusqu’à ce que le runtime soit nettoyé en toute sécurité."
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

    // The upstream interactive CLI accepts exactly one physical input line per
    // turn. U+2028 preserves a semantic line boundary without accidentally
    // submitting additional CLI turns. The small-context transport no longer
    // relies on physical newlines for priority semantics.
    value = value
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(of: "\n", with: "\u{2028}")

    // The upstream interactive CLI reserves slash-prefixed input for commands.
    if value.hasPrefix("/") {
      value = "\u{2060}" + value
    }
    return value
  }

  public static func containsPromptMarker(_ rawOutput: String) -> Bool {
    containsTerminalPrompt(rawOutput, requireCompletedTurn: false)
  }

  public static func containsTerminalPrompt(
    _ rawOutput: String,
    requireCompletedTurn: Bool
  ) -> Bool {
    let clean = stripANSI(rawOutput)
    let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasSuffix(promptMarker) else { return false }
    guard requireCompletedTurn else { return true }
    return completedTurnMetricsRange(in: clean) != nil
  }

  public static func parseTurn(_ rawOutput: String) throws -> ANEMLLInteractiveTurn {
    let clean = stripANSI(rawOutput)
    guard let assistantRange = clean.range(of: assistantMarker) else {
      throw ANEMLLPersistentRuntimeError.protocolFailure(
        "Assistant-Marker fehlt"
      )
    }

    let afterAssistant = assistantRange.upperBound..<clean.endIndex
    let metricsRange = completedTurnMetricsRange(in: clean, range: afterAssistant)
    let responseEnd = metricsRange?.lowerBound ?? clean.endIndex
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
  /// is still generating. A model-generated literal `You:` is treated as model
  /// content; only a terminal prompt after the metrics line ends a turn.
  public static func streamableAssistantText(_ rawOutput: String) -> String {
    let clean = stripANSI(rawOutput)
    guard let assistantRange = clean.range(of: assistantMarker) else {
      return ""
    }

    let afterAssistant = assistantRange.upperBound..<clean.endIndex
    let metricsRange = completedTurnMetricsRange(in: clean, range: afterAssistant)
    var responseEnd = metricsRange?.lowerBound ?? clean.endIndex

    if metricsRange == nil {
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

  private static func completedTurnMetricsRange(
    in value: String,
    range: Range<String.Index>? = nil
  ) -> Range<String.Index>? {
    let searchRange = range ?? value.startIndex..<value.endIndex
    return value.range(
      of: "\\n[0-9]+(?:\\.[0-9]+)?\\s+t/s,\\s*TTFT:",
      options: .regularExpression,
      range: searchRange
    )
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
    let current = snapshot()
    if current?.isRunning == true {
      current?.terminate()
    }
  }

  /// Blocks only on a detached worker thread. SIGTERM gets a short grace period;
  /// a stalled helper is then escalated to SIGKILL so cancellation cannot leave
  /// model memory resident indefinitely.
  func terminateAndWait(
    graceSeconds: TimeInterval = 2,
    killWaitSeconds: TimeInterval = 1
  ) -> Bool {
    guard let current = snapshot() else { return true }

    if current.isRunning {
      current.terminate()
    }
    if waitUntilStopped(current, timeoutSeconds: graceSeconds) {
      return true
    }

    if current.isRunning {
      _ = Darwin.kill(current.processIdentifier, SIGKILL)
    }
    return waitUntilStopped(current, timeoutSeconds: killWaitSeconds)
  }

  private func snapshot() -> Process? {
    lock.lock()
    defer { lock.unlock() }
    return process
  }

  private func waitUntilStopped(
    _ process: Process,
    timeoutSeconds: TimeInterval
  ) -> Bool {
    let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))
    while process.isRunning, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    return !process.isRunning
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
  private var cleanupFailed = false

  // Swift actors are reentrant across awaits. The helper owns exactly one
  // stdin/stdout conversation, so we explicitly serialize complete turns.
  private var turnInFlight = false
  private var turnWaiters: [CheckedContinuation<Void, Never>] = []

  public init() {}

  public func complete(
    prompt: String,
    systemPrompt: String,
    thinkingEnabled: Bool,
    maxTokens: Int,
    temperature: Double,
    requestTimeoutSeconds: Int,
    userTurnCount: Int,
    isFreshConversation: Bool,
    isToolContinuation: Bool,
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
      isFreshConversation: isFreshConversation,
      isToolContinuation: isToolContinuation,
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
    isFreshConversation: Bool,
    isToolContinuation: Bool,
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
      isFreshConversation: isFreshConversation,
      isToolContinuation: isToolContinuation,
      runtimeConfiguration: runtimeConfiguration,
      onAssistantDelta: onAssistantDelta
    )
  }

  @discardableResult
  public func resetConversation() async -> Bool {
    await acquireTurnPermit()
    defer { releaseTurnPermit() }
    return await shutdownInternal()
  }

  @discardableResult
  public func shutdown() async -> Bool {
    await acquireTurnPermit()
    defer { releaseTurnPermit() }
    return await shutdownInternal()
  }

  /// Best-effort immediate stop request that intentionally bypasses the turn
  /// permit. The actor can service this while `completeInternal` is suspended in
  /// its pipe reader; final cleanup still happens through `shutdownInternal`.
  public func requestTermination() {
    processBox.terminate()
  }

  public func isRunning() -> Bool {
    process?.isRunning == true
  }

  public func requiresRecovery() -> Bool {
    cleanupFailed
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
    isFreshConversation: Bool,
    isToolContinuation: Bool,
    runtimeConfiguration: ANEMLLRuntimeConfiguration,
    onAssistantDelta: (@Sendable (String) -> Void)?
  ) async throws -> ANEMLLRuntimeResult {
    await acquireTurnPermit()
    defer { releaseTurnPermit() }
    try Task.checkCancellation()
    guard !cleanupFailed else {
      throw ANEMLLPersistentRuntimeError.cleanupUnconfirmed
    }

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

    if ANEMLLContextBudget.shouldRotateBeforeUserTurn(
      contextLength: modelDescriptor.contextLength,
      activeTurns: conversationTurns,
      isFreshConversation: isFreshConversation,
      isToolContinuation: isToolContinuation
    ) {
      let stopped = await shutdownInternal()
      guard stopped else {
        throw ANEMLLPersistentRuntimeError.cleanupUnconfirmed
      }
    }

    if shouldRestart(
      requestedSignature: requestedSignature,
      requestedUserTurnCount: userTurnCount
    ) {
      let stopped = await shutdownInternal()
      guard stopped else {
        throw ANEMLLPersistentRuntimeError.cleanupUnconfirmed
      }
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
      _ = await shutdownInternal()
      throw ANEMLLPersistentRuntimeError.inputWriteFailed(error.localizedDescription)
    }

    let startedAt = Date.timeIntervalSinceReferenceDate
    let output: String
    do {
      output = try await readUntilPrompt(
        handle: outputPipe.fileHandleForReading,
        timeoutSeconds: timeout,
        requireCompletedTurn: true,
        onAssistantDelta: onAssistantDelta
      )
    } catch {
      _ = await shutdownInternal()
      throw error
    }
    try Task.checkCancellation()

    guard process.isRunning else {
      let termination = "Exit \(process.terminationStatus)"
      _ = await shutdownInternal()
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

    if requestedUserTurnCount <= 1, conversationTurns > 0 {
      return true
    }
    if requestedUserTurnCount < conversationTurns {
      return true
    }
    return false
  }

  private func acquireTurnPermit() async {
    if !turnInFlight {
      turnInFlight = true
      return
    }
    await withCheckedContinuation { continuation in
      turnWaiters.append(continuation)
    }
  }

  private func releaseTurnPermit() {
    guard !turnWaiters.isEmpty else {
      turnInFlight = false
      return
    }
    let next = turnWaiters.removeFirst()
    next.resume()
  }

  private func start(
    signature: ANEMLLPersistentSessionSignature,
    descriptor: ANEMLLModelBundleDescriptor,
    timeoutSeconds: Int
  ) async throws {
    guard !cleanupFailed else {
      throw ANEMLLPersistentRuntimeError.cleanupUnconfirmed
    }

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
        requireCompletedTurn: false,
        onAssistantDelta: nil
      )
    } catch {
      _ = await shutdownInternal()
      throw error
    }

    guard process.isRunning else {
      let output = ANEMLLInteractiveProtocol.stripANSI(startupOutput)
      _ = await shutdownInternal()
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
    requireCompletedTurn: Bool,
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
            if data.count > maximumBytes {
              throw ANEMLLPersistentRuntimeError.protocolFailure(
                "Ausgabe überschreitet 8 MiB ohne Prompt-Marker"
              )
            }

            // Do not decode an incomplete UTF-8 scalar. The previous lossy
            // decode could emit U+FFFD, permanently breaking the prefix-based
            // streaming delta cursor after a split umlaut/emoji.
            guard let output = String(data: data, encoding: .utf8) else {
              continue
            }

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

            if ANEMLLInteractiveProtocol.containsTerminalPrompt(
              output,
              requireCompletedTurn: requireCompletedTurn
            ) {
              return output
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
          Task.detached(priority: .userInitiated) {
            _ = box.terminateAndWait()
          }
          group.cancelAll()
          throw error
        }
      }
    } onCancel: {
      box.terminate()
      Task.detached(priority: .userInitiated) {
        _ = box.terminateAndWait()
      }
    }
  }

  @discardableResult
  private func shutdownInternal() async -> Bool {
    let box = processBox
    try? inputPipe?.fileHandleForWriting.close()

    let stopped = await Task.detached(priority: .userInitiated) {
      box.terminateAndWait()
    }.value

    guard stopped else {
      cleanupFailed = true
      AppLogger.app.error(
        "ANEMLL helper did not confirm process exit after SIGKILL escalation; runtime remains fail-closed."
      )
      return false
    }

    try? outputPipe?.fileHandleForReading.close()
    box.clear()
    process = nil
    inputPipe = nil
    outputPipe = nil
    signature = nil
    descriptor = nil
    startupOutput = ""
    conversationTurns = 0
    modelLoadReported = false
    cleanupFailed = false
    return true
  }
}
