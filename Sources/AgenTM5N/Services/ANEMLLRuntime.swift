import Foundation

public enum ANEMLLRuntimeError: LocalizedError {
  case helperUnavailable(String)
  case helperNotExecutable(String)
  case metaUnavailable(String)
  case invalidModelBundle(String)
  case missingPrompt
  case processFailed(exitCode: Int32, output: String)
  case emptyResponse

  public var errorDescription: String? {
    switch self {
    case .helperUnavailable(let path):
      return L10n.text(
        de: "Die native ANEMLL-Runtime wurde nicht gefunden: \(path)",
        en: "The native ANEMLL runtime was not found: \(path)",
        fr: "Le runtime ANEMLL natif est introuvable : \(path)"
      )
    case .helperNotExecutable(let path):
      return L10n.text(
        de: "Die ANEMLL-Runtime ist nicht ausführbar: \(path)",
        en: "The ANEMLL runtime is not executable: \(path)",
        fr: "Le runtime ANEMLL n’est pas exécutable : \(path)"
      )
    case .metaUnavailable(let path):
      return L10n.text(
        de: "Die ANEMLL meta.yaml ist nicht erreichbar: \(path)",
        en: "The ANEMLL meta.yaml is not accessible: \(path)",
        fr: "Le fichier meta.yaml ANEMLL n’est pas accessible : \(path)"
      )
    case .invalidModelBundle(let reason):
      return L10n.text(
        de: "Das ANEMLL-Modell-Bundle ist unvollständig: \(reason)",
        en: "The ANEMLL model bundle is incomplete: \(reason)",
        fr: "Le bundle de modèle ANEMLL est incomplet : \(reason)"
      )
    case .missingPrompt:
      return L10n.text(
        de: "ANEMLL benötigt eine nicht leere Benutzeranfrage.",
        en: "ANEMLL requires a non-empty user prompt.",
        fr: "ANEMLL nécessite une requête utilisateur non vide."
      )
    case .processFailed(let exitCode, let output):
      return L10n.text(
        de: "ANEMLL wurde mit Exit-Code \(exitCode) beendet: \(output)",
        en: "ANEMLL exited with code \(exitCode): \(output)",
        fr: "ANEMLL s’est terminé avec le code \(exitCode) : \(output)"
      )
    case .emptyResponse:
      return L10n.text(
        de: "ANEMLL hat keine Textantwort geliefert.",
        en: "ANEMLL did not produce a text response.",
        fr: "ANEMLL n’a produit aucune réponse texte."
      )
    }
  }
}

public struct ANEMLLRuntimeConfiguration: Codable, Equatable, Sendable {
  public var helperPath: String
  public var metaPath: String
  public var defaultMaxTokens: Int
  public var defaultTemperature: Double

  public init(
    helperPath: String = "",
    metaPath: String = "",
    defaultMaxTokens: Int = 256,
    defaultTemperature: Double = 0.0
  ) {
    self.helperPath = helperPath
    self.metaPath = metaPath
    self.defaultMaxTokens = max(1, min(defaultMaxTokens, 4_096))
    self.defaultTemperature = max(0, min(defaultTemperature, 2))
  }
}

public enum ANEMLLRuntimeStore {
  private static let defaultsKey = "AgenTM5N.ANEMLLRuntimeConfiguration"

  public static func load() -> ANEMLLRuntimeConfiguration {
    if let data = UserDefaults.standard.data(forKey: defaultsKey),
      let decoded = try? JSONDecoder().decode(ANEMLLRuntimeConfiguration.self, from: data)
    {
      return normalized(decoded)
    }
    return discoveredConfiguration()
  }

  public static func save(_ configuration: ANEMLLRuntimeConfiguration) {
    let normalized = normalized(configuration)
    if let data = try? JSONEncoder().encode(normalized) {
      UserDefaults.standard.set(data, forKey: defaultsKey)
    }
  }

  public static func discoveredConfiguration() -> ANEMLLRuntimeConfiguration {
    ANEMLLRuntimeConfiguration(
      helperPath: discoverHelperPath() ?? "",
      metaPath: discoverQwen3MetaPath() ?? "",
      defaultMaxTokens: 256,
      defaultTemperature: 0.0
    )
  }

  public static func discoverHelperPath() -> String? {
    let manager = FileManager.default
    var candidates: [String] = []

    if let environment = ProcessInfo.processInfo.environment["AGENTM5N_ANEMLLCLI"],
      !environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      candidates.append(expanded(environment))
    }

    if let bundled = Bundle.main.executableURL?
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Helpers/ANEMLL/anemllcli")
      .path
    {
      candidates.append(bundled)
    }

    let home = FileManager.default.homeDirectoryForCurrentUser
    candidates.append(
      home.appendingPathComponent(
        "Downloads/AgenTM5N/.build-artifacts/anemll-runtime/anemllcli"
      ).path
    )

    let current = URL(fileURLWithPath: manager.currentDirectoryPath)
      .appendingPathComponent(".build-artifacts/anemll-runtime/anemllcli")
      .path
    candidates.append(current)

    return candidates.first { manager.isExecutableFile(atPath: $0) }
  }

  public static func discoverQwen3MetaPath() -> String? {
    let manager = FileManager.default
    var candidates: [String] = []

    if let environment = ProcessInfo.processInfo.environment["AGENTM5N_ANEMLL_META"],
      !environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      candidates.append(expanded(environment))
    }

    let home = manager.homeDirectoryForCurrentUser
    candidates.append(
      home.appendingPathComponent(
        "Downloads/AgenTM5N-Qwen3-ANE/anemll-Qwen-Qwen3-0.6B-ctx512_0.3.4/meta.yaml"
      ).path
    )

    return candidates.first { manager.fileExists(atPath: $0) }
  }

  public static func expanded(_ path: String) -> String {
    NSString(string: path).expandingTildeInPath
  }

  private static func normalized(
    _ configuration: ANEMLLRuntimeConfiguration
  ) -> ANEMLLRuntimeConfiguration {
    ANEMLLRuntimeConfiguration(
      helperPath: configuration.helperPath.trimmingCharacters(in: .whitespacesAndNewlines),
      metaPath: configuration.metaPath.trimmingCharacters(in: .whitespacesAndNewlines),
      defaultMaxTokens: configuration.defaultMaxTokens,
      defaultTemperature: configuration.defaultTemperature
    )
  }
}

public struct ANEMLLModelBundleDescriptor: Equatable, Sendable {
  public let modelDirectory: URL
  public let metaURL: URL
  public let tokenizerURL: URL
  public let tokenizerConfigurationURL: URL?
  public let embeddingsURL: URL
  public let ffnURLs: [URL]
  public let lmHeadURL: URL
  public let modelName: String
  public let contextLength: Int?
  public let batchSize: Int?

  public init(
    modelDirectory: URL,
    metaURL: URL,
    tokenizerURL: URL,
    tokenizerConfigurationURL: URL?,
    embeddingsURL: URL,
    ffnURLs: [URL],
    lmHeadURL: URL,
    modelName: String,
    contextLength: Int?,
    batchSize: Int?
  ) {
    self.modelDirectory = modelDirectory
    self.metaURL = metaURL
    self.tokenizerURL = tokenizerURL
    self.tokenizerConfigurationURL = tokenizerConfigurationURL
    self.embeddingsURL = embeddingsURL
    self.ffnURLs = ffnURLs
    self.lmHeadURL = lmHeadURL
    self.modelName = modelName
    self.contextLength = contextLength
    self.batchSize = batchSize
  }

  public var componentCount: Int {
    2 + ffnURLs.count
  }
}

public enum ANEMLLModelBundleInspector {
  public static func inspect(metaPath: String) throws -> ANEMLLModelBundleDescriptor {
    let expandedPath = ANEMLLRuntimeStore.expanded(metaPath)
    let metaURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
    let manager = FileManager.default
    guard manager.fileExists(atPath: metaURL.path) else {
      throw ANEMLLRuntimeError.metaUnavailable(metaURL.path)
    }

    let directory = metaURL.deletingLastPathComponent()
    let tokenizerURL = directory.appendingPathComponent("tokenizer.json")
    guard manager.fileExists(atPath: tokenizerURL.path) else {
      throw ANEMLLRuntimeError.invalidModelBundle("tokenizer.json fehlt")
    }

    let tokenizerConfigurationURL = directory.appendingPathComponent("tokenizer_config.json")
    let entries = try manager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    let compiled = entries.filter {
      $0.pathExtension.lowercased() == "mlmodelc"
    }

    guard let embeddingsURL = compiled.first(where: {
      $0.lastPathComponent.lowercased().contains("embeddings")
    }) else {
      throw ANEMLLRuntimeError.invalidModelBundle("Embeddings .mlmodelc fehlt")
    }

    let ffnURLs = compiled.filter {
      let name = $0.lastPathComponent.lowercased()
      return name.contains("ffn") && (name.contains("pf") || name.contains("prefill"))
    }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !ffnURLs.isEmpty else {
      throw ANEMLLRuntimeError.invalidModelBundle("FFN/PREFILL .mlmodelc fehlt")
    }

    let lmHeadCandidates = compiled.filter {
      $0.lastPathComponent.lowercased().contains("lm_head")
    }.sorted { lhs, rhs in
      lmHeadScore(lhs) > lmHeadScore(rhs)
    }
    guard let lmHeadURL = lmHeadCandidates.first else {
      throw ANEMLLRuntimeError.invalidModelBundle("LM-Head .mlmodelc fehlt")
    }

    let yaml = (try? String(contentsOf: metaURL, encoding: .utf8)) ?? ""
    let prefix = scalar("model_prefix", in: yaml)
      ?? scalar("model", in: yaml)
      ?? directory.lastPathComponent
    let contextLength = intScalar("context_length", in: yaml)
    let batchSize = intScalar("batch_size", in: yaml)

    return ANEMLLModelBundleDescriptor(
      modelDirectory: directory,
      metaURL: metaURL,
      tokenizerURL: tokenizerURL,
      tokenizerConfigurationURL: manager.fileExists(atPath: tokenizerConfigurationURL.path)
        ? tokenizerConfigurationURL
        : nil,
      embeddingsURL: embeddingsURL,
      ffnURLs: ffnURLs,
      lmHeadURL: lmHeadURL,
      modelName: prefix,
      contextLength: contextLength,
      batchSize: batchSize
    )
  }

  private static func lmHeadScore(_ url: URL) -> Int {
    let name = url.lastPathComponent.lowercased()
    var score = 0
    if name.contains("lut") { score += 100 }
    if name.contains("lut6") { score += 20 }
    if name.contains("argmax") { score += 5 }
    return score
  }

  private static func scalar(_ key: String, in yaml: String) -> String? {
    for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { continue }
      let candidate = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
      guard candidate == key else { continue }
      let value = String(line[line.index(after: colon)...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      return value.isEmpty ? nil : value
    }
    return nil
  }

  private static func intScalar(_ key: String, in yaml: String) -> Int? {
    guard let value = scalar(key, in: yaml) else { return nil }
    return Int(value)
  }
}

public struct ANEMLLRuntimeMetrics: Equatable, Sendable {
  public let modelLoadSeconds: Double?
  public let timeToFirstTokenMilliseconds: Double?
  public let prefillTokensPerSecond: Double?
  public let inferenceTokensPerSecond: Double?
  public let generatedTokens: Int?
  public let totalTokens: Int?
  public let stopReason: String?
  public let wallMilliseconds: Double

  public init(
    modelLoadSeconds: Double?,
    timeToFirstTokenMilliseconds: Double?,
    prefillTokensPerSecond: Double?,
    inferenceTokensPerSecond: Double?,
    generatedTokens: Int?,
    totalTokens: Int?,
    stopReason: String?,
    wallMilliseconds: Double
  ) {
    self.modelLoadSeconds = modelLoadSeconds
    self.timeToFirstTokenMilliseconds = timeToFirstTokenMilliseconds
    self.prefillTokensPerSecond = prefillTokensPerSecond
    self.inferenceTokensPerSecond = inferenceTokensPerSecond
    self.generatedTokens = generatedTokens
    self.totalTokens = totalTokens
    self.stopReason = stopReason
    self.wallMilliseconds = max(0, wallMilliseconds)
  }

  public var chatMetrics: ChatMetrics {
    let promptTokens: Int?
    if let totalTokens, let generatedTokens {
      promptTokens = max(0, totalTokens - generatedTokens)
    } else {
      promptTokens = nil
    }

    let evaluationDuration: UInt64?
    if let generatedTokens,
      let inferenceTokensPerSecond,
      inferenceTokensPerSecond > 0
    {
      evaluationDuration = UInt64(
        (Double(generatedTokens) / inferenceTokensPerSecond) * 1_000_000_000
      )
    } else {
      evaluationDuration = nil
    }

    return ChatMetrics(
      promptTokens: promptTokens,
      generatedTokens: generatedTokens,
      totalDurationNanoseconds: UInt64(wallMilliseconds * 1_000_000),
      evaluationDurationNanoseconds: evaluationDuration
    )
  }
}

public struct ANEMLLRuntimeResult: Equatable, Sendable {
  public let response: String
  public let diagnosticOutput: String
  public let metrics: ANEMLLRuntimeMetrics
  public let descriptor: ANEMLLModelBundleDescriptor

  public init(
    response: String,
    diagnosticOutput: String,
    metrics: ANEMLLRuntimeMetrics,
    descriptor: ANEMLLModelBundleDescriptor
  ) {
    self.response = response
    self.diagnosticOutput = diagnosticOutput
    self.metrics = metrics
    self.descriptor = descriptor
  }
}

private final class ANEMLLProcessBox: @unchecked Sendable {
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
    let running = process
    lock.unlock()
    if running?.isRunning == true {
      running?.terminate()
    }
  }
}

public enum ANEMLLNativeRuntime {
  private struct ProcessResult: Sendable {
    let response: String
    let output: String
    let exitCode: Int32
    let wallMilliseconds: Double
  }

  public static func complete(
    prompt: String,
    systemPrompt: String,
    thinkingEnabled: Bool,
    maxTokens: Int,
    temperature: Double,
    runtimeConfiguration: ANEMLLRuntimeConfiguration
  ) async throws -> ANEMLLRuntimeResult {
    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPrompt.isEmpty else {
      throw ANEMLLRuntimeError.missingPrompt
    }

    let helperPath = ANEMLLRuntimeStore.expanded(runtimeConfiguration.helperPath)
    let manager = FileManager.default
    guard manager.fileExists(atPath: helperPath) else {
      throw ANEMLLRuntimeError.helperUnavailable(helperPath)
    }
    guard manager.isExecutableFile(atPath: helperPath) else {
      throw ANEMLLRuntimeError.helperNotExecutable(helperPath)
    }

    let descriptor = try ANEMLLModelBundleInspector.inspect(
      metaPath: runtimeConfiguration.metaPath
    )
    try AppPaths.ensureDirectories()

    let boundedMaxTokens = max(
      1,
      min(
        maxTokens,
        descriptor.contextLength ?? 4_096
      )
    )
    let boundedTemperature = max(0, min(temperature, 2))
    let responseURL = AppPaths.runtimeDirectory.appendingPathComponent(
      "anemll-response-\(UUID().uuidString.lowercased()).txt"
    )
    defer { try? manager.removeItem(at: responseURL) }

    let arguments = makeArguments(
      metaURL: descriptor.metaURL,
      prompt: trimmedPrompt,
      systemPrompt: systemPrompt,
      thinkingEnabled: thinkingEnabled,
      maxTokens: boundedMaxTokens,
      temperature: boundedTemperature,
      responseURL: responseURL
    )

    let processBox = ANEMLLProcessBox()
    let processResult = try await withTaskCancellationHandler {
      try await Task.detached(priority: .userInitiated) {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = arguments
        process.currentDirectoryURL = descriptor.modelDirectory
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.environment = ProcessInfo.processInfo.environment.merging(
          ["NSUnbufferedIO": "YES"]
        ) { _, new in new }
        processBox.install(process)

        let startedAt = Date.timeIntervalSinceReferenceDate
        do {
          try process.run()
        } catch {
          processBox.clear()
          throw error
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        processBox.clear()
        let wallMilliseconds = max(
          0,
          (Date.timeIntervalSinceReferenceDate - startedAt) * 1_000
        )
        let output = String(decoding: outputData, as: UTF8.self)
        let response = (try? String(contentsOf: responseURL, encoding: .utf8)) ?? ""
        return ProcessResult(
          response: response,
          output: output,
          exitCode: process.terminationStatus,
          wallMilliseconds: wallMilliseconds
        )
      }.value
    } onCancel: {
      processBox.terminate()
    }

    try Task.checkCancellation()
    guard processResult.exitCode == 0 else {
      throw ANEMLLRuntimeError.processFailed(
        exitCode: processResult.exitCode,
        output: boundedDiagnostic(processResult.output)
      )
    }

    let response = processResult.response.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !response.isEmpty else {
      throw ANEMLLRuntimeError.emptyResponse
    }

    return ANEMLLRuntimeResult(
      response: response,
      diagnosticOutput: stripANSI(processResult.output),
      metrics: parseMetrics(
        processResult.output,
        wallMilliseconds: processResult.wallMilliseconds
      ),
      descriptor: descriptor
    )
  }

  private static func makeArguments(
    metaURL: URL,
    prompt: String,
    systemPrompt: String,
    thinkingEnabled: Bool,
    maxTokens: Int,
    temperature: Double,
    responseURL: URL
  ) -> [String] {
    var arguments = [
      "--meta", metaURL.path,
      "--prompt", prompt,
      "--max-tokens", String(maxTokens),
      "--temperature", String(format: "%.4f", temperature),
      "--save", responseURL.path,
      "--template", "auto",
    ]
    let trimmedSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedSystem.isEmpty {
      arguments.append(contentsOf: ["--system", trimmedSystem])
    }
    if thinkingEnabled {
      arguments.append("--thinking-mode")
    }
    return arguments
  }

  public static func parseMetrics(
    _ rawOutput: String,
    wallMilliseconds: Double
  ) -> ANEMLLRuntimeMetrics {
    let output = stripANSI(rawOutput)
    let summary = captures(
      pattern: "([0-9]+(?:\\.[0-9]+)?)\\s+t/s,\\s*TTFT:\\s*([0-9]+(?:\\.[0-9]+)?)ms\\s*\\(([0-9]+(?:\\.[0-9]+)?)\\s+t/s\\),\\s*([0-9]+)\\s+tokens",
      in: output
    )
    let modelLoad = captures(
      pattern: "Models loaded successfully in\\s+([0-9]+(?:\\.[0-9]+)?)s",
      in: output
    ).first.flatMap(Double.init)
    let totalTokens = captures(
      pattern: "\\[(?:Total|History):\\s*([0-9]+)\\s+tokens\\]",
      in: output
    ).first.flatMap(Int.init)
    let stopReason = captures(
      pattern: "\\[Stop:\\s*([^\\]]+)\\]",
      in: output
    ).first

    return ANEMLLRuntimeMetrics(
      modelLoadSeconds: modelLoad,
      timeToFirstTokenMilliseconds: summary.count > 1 ? Double(summary[1]) : nil,
      prefillTokensPerSecond: summary.count > 2 ? Double(summary[2]) : nil,
      inferenceTokensPerSecond: summary.first.flatMap(Double.init),
      generatedTokens: summary.count > 3 ? Int(summary[3]) : nil,
      totalTokens: totalTokens,
      stopReason: stopReason,
      wallMilliseconds: wallMilliseconds
    )
  }

  private static func captures(pattern: String, in text: String) -> [String] {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = expression.firstMatch(in: text, range: range) else { return [] }
    return (1..<match.numberOfRanges).compactMap { index in
      guard let range = Range(match.range(at: index), in: text) else { return nil }
      return String(text[range])
    }
  }

  private static func stripANSI(_ value: String) -> String {
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

  private static func boundedDiagnostic(_ output: String) -> String {
    let cleaned = stripANSI(output)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let limit = 4_000
    return cleaned.count <= limit
      ? cleaned
      : String(cleaned.suffix(limit))
  }
}

public final class ANEMLLRuntimeTelemetry: @unchecked Sendable {
  public static let shared = ANEMLLRuntimeTelemetry()

  private let lock = NSLock()
  private var lastResult: ANEMLLRuntimeResult?

  public init() {}

  public func record(_ result: ANEMLLRuntimeResult) {
    lock.lock()
    lastResult = result
    lock.unlock()
  }

  public func latest() -> ANEMLLRuntimeResult? {
    lock.lock()
    defer { lock.unlock() }
    return lastResult
  }

  public func clear() {
    lock.lock()
    lastResult = nil
    lock.unlock()
  }
}
