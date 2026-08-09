import Foundation

public struct ManagedBrowserStatus: Codable, Sendable {
  public let running: Bool
  public let browser: String?
  public let protocolVersion: String?
  public let profile: String
  public let tabCount: Int
}

public struct ManagedBrowserTab: Codable, Sendable {
  public let id: String
  public let title: String
  public let url: String
  public let selected: Bool
}

public struct BrowserInteractiveElement: Codable, Sendable {
  public let ref: String
  public let tag: String
  public let type: String?
  public let role: String?
  public let text: String?
  public let label: String?
  public let name: String?
  public let href: String?
  public let disabled: Bool
  public let checked: Bool?
  public let selectedText: String?
}

public struct ManagedBrowserSnapshot: Codable, Sendable {
  public let tabID: String
  public let title: String
  public let url: String
  public let text: String
  public let elements: [BrowserInteractiveElement]
}

public struct ManagedBrowserActionResult: Codable, Sendable {
  public let success: Bool
  public let action: String
  public let message: String
  public let tabID: String?
  public let title: String?
  public let url: String?
}

public enum MicrosoftEdgeBrowserError: LocalizedError {
  case edgeNotInstalled
  case launchFailed(String)
  case sessionNotRunning
  case devToolsUnavailable(String)
  case invalidURL(String)
  case tabNotFound(String)
  case invalidOperation(String)
  case missingArgument(String)
  case pageEvaluationFailed(String)
  case protocolFailure(String)

  public var errorDescription: String? {
    switch self {
    case .edgeNotInstalled:
      "Microsoft Edge wurde auf diesem Mac nicht gefunden."
    case .launchFailed(let reason):
      "Microsoft Edge konnte nicht für AgenTM5N gestartet werden: \(reason)"
    case .sessionNotRunning:
      "Die AgenTM5N-Microsoft-Edge-Sitzung läuft nicht."
    case .devToolsUnavailable(let reason):
      "Microsoft Edge DevTools Protocol ist nicht erreichbar: \(reason)"
    case .invalidURL(let value):
      "Ungültige oder nicht erlaubte Browser-URL: \(value)"
    case .tabNotFound(let value):
      "Der Microsoft-Edge-Tab wurde nicht gefunden: \(value)"
    case .invalidOperation(let value):
      "Nicht unterstützte Browser-Operation: \(value)"
    case .missingArgument(let value):
      "Für die Browser-Aktion fehlt das Argument: \(value)"
    case .pageEvaluationFailed(let reason):
      "Die Webseite konnte nicht ausgewertet werden: \(reason)"
    case .protocolFailure(let reason):
      "Microsoft Edge CDP Fehler: \(reason)"
    }
  }
}

public actor MicrosoftEdgeBrowserService {
  public static let shared = MicrosoftEdgeBrowserService()

  private struct EdgeTarget: Codable, Sendable {
    let id: String
    let title: String
    let type: String
    let url: String
    let webSocketDebuggerUrl: String?
  }

  private struct BrowserVersion: Codable, Sendable {
    let browser: String?
    let protocolVersion: String?
    let webSocketDebuggerUrl: String?

    enum CodingKeys: String, CodingKey {
      case browser = "Browser"
      case protocolVersion = "Protocol-Version"
      case webSocketDebuggerUrl
    }
  }

  private struct EmptyParams: Codable, Sendable {}
  private struct EmptyResult: Codable, Sendable {}

  private struct RuntimeEvaluateParams: Codable, Sendable {
    let expression: String
    let returnByValue: Bool
    let awaitPromise: Bool
    let userGesture: Bool
  }

  private struct RuntimeRemoteObject: Codable, Sendable {
    let type: String?
    let value: String?
    let description: String?
  }

  private struct RuntimeExceptionDetails: Codable, Sendable {
    let text: String?
  }

  private struct RuntimeEvaluateResult: Codable, Sendable {
    let result: RuntimeRemoteObject
    let exceptionDetails: RuntimeExceptionDetails?
  }

  private struct PageNavigateParams: Codable, Sendable {
    let url: String
  }

  private struct PageNavigateResult: Codable, Sendable {
    let frameId: String?
    let loaderId: String?
    let errorText: String?
  }

  private struct KeyEventParams: Codable, Sendable {
    let type: String
    let key: String
    let code: String
    let windowsVirtualKeyCode: Int
    let nativeVirtualKeyCode: Int
    let text: String?
  }

  private struct CDPErrorPayload: Codable, Sendable {
    let code: Int
    let message: String
  }

  private struct CDPEnvelope<Result: Codable & Sendable>: Codable, Sendable {
    let id: Int?
    let result: Result?
    let error: CDPErrorPayload?
  }

  private struct CDPHeader: Codable, Sendable {
    let id: Int?
  }

  private struct CDPCommand<Params: Codable & Sendable>: Codable, Sendable {
    let id: Int
    let method: String
    let params: Params
  }

  private struct KeySpec: Sendable {
    let key: String
    let code: String
    let virtualKey: Int
    let text: String?
  }

  private struct SnapshotPayload: Codable, Sendable {
    let title: String
    let url: String
    let text: String
    let elements: [BrowserInteractiveElement]
  }

  private struct ActionPayload: Codable, Sendable {
    let success: Bool
    let message: String
    let title: String?
    let url: String?
  }

  private let fileManager = FileManager.default
  private let session: URLSession
  private var process: Process?
  private var activePort: Int?
  private var selectedTabID: String?
  private var nextCommandID = 1

  public init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 30
    session = URLSession(configuration: configuration)
  }

  public func execute(call: ProviderToolCall) async -> ToolExecutionResult {
    do {
      switch call.function.name {
      case "browser_session":
        let operation = try requiredString("operation", in: call).lowercased()
        switch operation {
        case "start":
          return encoded(try await start())
        case "status":
          return encoded(await status())
        case "stop":
          return encoded(try await stop())
        default:
          throw MicrosoftEdgeBrowserError.invalidOperation(operation)
        }

      case "browser_tabs":
        _ = try await ensureStarted()
        return encoded(try await listTabs())

      case "browser_open":
        _ = try await ensureStarted()
        return encoded(
          try await open(
            urlText: try requiredString("url", in: call),
            tabID: optionalString("tab_id", in: call)
          )
        )

      case "browser_read":
        _ = try await ensureStarted()
        let maxCharacters = max(
          1_000,
          min(optionalInt("max_chars", in: call) ?? 30_000, 60_000)
        )
        let maxElements = max(
          10,
          min(optionalInt("max_elements", in: call) ?? 120, 250)
        )
        return encoded(
          try await readPage(
            tabID: optionalString("tab_id", in: call),
            maxCharacters: maxCharacters,
            maxElements: maxElements
          )
        )

      case "browser_action":
        _ = try await ensureStarted()
        let result = try await performAction(
          action: try requiredString("action", in: call),
          tabID: optionalString("tab_id", in: call),
          ref: optionalString("ref", in: call),
          selector: optionalString("selector", in: call),
          targetText: optionalString("target_text", in: call),
          text: optionalStringAllowingEmpty("text", in: call),
          key: optionalString("key", in: call),
          amount: optionalInt("amount", in: call),
          timeoutMilliseconds: optionalInt("timeout_ms", in: call)
        )
        return encoded(result, success: result.success)

      default:
        throw AgentRuntimeError.unsupportedTool(call.function.name)
      }
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  public func start() async throws -> ManagedBrowserStatus {
    let port = try await ensureStarted()
    let version = try await browserVersion(port: port)
    let allTargets = try await targets(port: port)
    let tabs = allTargets.filter { $0.type == "page" }
    return ManagedBrowserStatus(
      running: true,
      browser: version.browser,
      protocolVersion: version.protocolVersion,
      profile: "AgenTM5N Managed Microsoft Edge",
      tabCount: tabs.count
    )
  }

  public func status() async -> ManagedBrowserStatus {
    do {
      guard let port = await connectedPortIfAvailable() else {
        return stoppedStatus()
      }
      let version = try await browserVersion(port: port)
      let allTargets = try await targets(port: port)
      let tabs = allTargets.filter { $0.type == "page" }
      return ManagedBrowserStatus(
        running: true,
        browser: version.browser,
        protocolVersion: version.protocolVersion,
        profile: "AgenTM5N Managed Microsoft Edge",
        tabCount: tabs.count
      )
    } catch {
      return stoppedStatus()
    }
  }

  public func stop() async throws -> ManagedBrowserStatus {
    guard let port = await connectedPortIfAvailable() else {
      activePort = nil
      selectedTabID = nil
      process = nil
      return stoppedStatus()
    }

    do {
      let version = try await browserVersion(port: port)
      if let websocket = version.webSocketDebuggerUrl,
        let websocketURL = URL(string: websocket)
      {
        let validatedSocket = try validatedCDPWebSocketURL(websocketURL)
        let _: EmptyResult = try await sendCDP(
          websocketURL: validatedSocket,
          method: "Browser.close",
          params: EmptyParams(),
          resultType: EmptyResult.self
        )
      } else if let process, process.isRunning {
        process.terminate()
      }
    } catch {
      if let process, process.isRunning {
        process.terminate()
      }
    }

    try? await Task.sleep(for: .milliseconds(250))
    process = nil
    activePort = nil
    selectedTabID = nil
    try? fileManager.removeItem(at: devToolsActivePortURL)
    return stoppedStatus()
  }

  public func listTabs() async throws -> [ManagedBrowserTab] {
    let port = try await requireConnectedPort()
    let allTargets = try await targets(port: port)
    let pages = allTargets.filter { $0.type == "page" }
    if selectedTabID == nil {
      selectedTabID = pages.first?.id
    }
    return pages.map { target in
      ManagedBrowserTab(
        id: target.id,
        title: boundedDisplayText(target.title, limit: 300),
        url: sanitizedDisplayURL(target.url),
        selected: target.id == selectedTabID
      )
    }
  }

  public func open(urlText: String, tabID: String?) async throws -> ManagedBrowserTab {
    let validated = try validateBrowserURL(urlText)
    let port = try await requireConnectedPort()
    let target: EdgeTarget

    if let tabID {
      target = try await resolveTarget(tabID: tabID, port: port)
      let websocketURL = try targetWebSocketURL(target)
      let result: PageNavigateResult = try await sendCDP(
        websocketURL: websocketURL,
        method: "Page.navigate",
        params: PageNavigateParams(url: validated),
        resultType: PageNavigateResult.self
      )
      if let errorText = result.errorText, !errorText.isEmpty {
        throw MicrosoftEdgeBrowserError.protocolFailure(errorText)
      }
    } else {
      target = try await createTab(urlText: validated, port: port)
    }

    selectedTabID = target.id
    try? await activateTarget(id: target.id, port: port)
    try? await waitForReadyState(tabID: target.id, timeoutMilliseconds: 15_000)

    let refreshed = try await resolveTarget(tabID: target.id, port: port)
    return ManagedBrowserTab(
      id: refreshed.id,
      title: boundedDisplayText(refreshed.title, limit: 300),
      url: sanitizedDisplayURL(refreshed.url),
      selected: true
    )
  }

  public func readPage(
    tabID: String?,
    maxCharacters: Int,
    maxElements: Int
  ) async throws -> ManagedBrowserSnapshot {
    let port = try await requireConnectedPort()
    let target = try await resolveTarget(tabID: tabID, port: port)
    selectedTabID = target.id
    try? await activateTarget(id: target.id, port: port)

    let expression = """
      (() => {
        const MAX_CHARS = \(maxCharacters);
        const MAX_ELEMENTS = \(maxElements);
        const visible = (el) => {
          if (!el) return false;
          const style = getComputedStyle(el);
          if (style.display === 'none' || style.visibility === 'hidden') return false;
          const rect = el.getBoundingClientRect();
          return rect.width > 0 && rect.height > 0;
        };
        const clean = (value, max = 220) => {
          const text = String(value ?? '').replace(/\\s+/g, ' ').trim();
          return text.length > max ? text.slice(0, max) + '…' : text;
        };
        const labelFor = (el) => {
          const aria = el.getAttribute('aria-label');
          if (aria) return clean(aria);
          const placeholder = el.getAttribute('placeholder');
          if (placeholder) return clean(placeholder);
          if (el.id) {
            try {
              const label = document.querySelector(`label[for="${CSS.escape(el.id)}"]`);
              if (label) return clean(label.innerText || label.textContent);
            } catch (_) {}
          }
          const wrapping = el.closest('label');
          if (wrapping) return clean(wrapping.innerText || wrapping.textContent);
          return null;
        };
        document.querySelectorAll('[data-agentm5n-ref]').forEach((el) => {
          el.removeAttribute('data-agentm5n-ref');
        });
        const selector = [
          'a[href]', 'button', 'input', 'textarea', 'select',
          '[role="button"]', '[role="link"]', '[role="checkbox"]',
          '[role="menuitem"]', '[contenteditable="true"]'
        ].join(',');
        const nodes = Array.from(document.querySelectorAll(selector))
          .filter(visible)
          .slice(0, MAX_ELEMENTS);
        const elements = nodes.map((el, index) => {
          const ref = `b${index + 1}`;
          el.setAttribute('data-agentm5n-ref', ref);
          const tag = el.tagName.toLowerCase();
          const inputType = tag === 'input'
            ? (el.getAttribute('type') || 'text').toLowerCase()
            : null;
          const selectedText = tag === 'select' && el.selectedOptions && el.selectedOptions.length
            ? clean(el.selectedOptions[0].textContent)
            : null;
          return {
            ref,
            tag,
            type: inputType,
            role: el.getAttribute('role'),
            text: clean(el.innerText || (tag === 'button' ? el.value : '') || ''),
            label: labelFor(el),
            name: el.getAttribute('name'),
            href: tag === 'a' ? el.href : null,
            disabled: Boolean(el.disabled || el.getAttribute('aria-disabled') === 'true'),
            checked: typeof el.checked === 'boolean' ? Boolean(el.checked) : null,
            selectedText
          };
        });
        const bodyText = clean(document.body ? document.body.innerText : '', MAX_CHARS);
        return JSON.stringify({
          title: document.title || '',
          url: location.href,
          text: bodyText,
          elements
        });
      })()
      """

    let raw = try await evaluateString(on: target, expression: expression)
    guard let data = raw.data(using: .utf8) else {
      throw MicrosoftEdgeBrowserError.pageEvaluationFailed(
        "Snapshot ist kein UTF-8-JSON."
      )
    }
    let payload = try JSONDecoder().decode(SnapshotPayload.self, from: data)
    let elements = payload.elements.map { element in
      BrowserInteractiveElement(
        ref: element.ref,
        tag: element.tag,
        type: element.type,
        role: element.role,
        text: element.text.map { boundedDisplayText($0, limit: 300) },
        label: element.label.map { boundedDisplayText($0, limit: 300) },
        name: element.name.map { boundedDisplayText($0, limit: 200) },
        href: element.href.map { sanitizedDisplayURL($0) },
        disabled: element.disabled,
        checked: element.checked,
        selectedText: element.selectedText.map { boundedDisplayText($0, limit: 300) }
      )
    }
    return ManagedBrowserSnapshot(
      tabID: target.id,
      title: boundedDisplayText(payload.title, limit: 300),
      url: sanitizedDisplayURL(payload.url),
      text: String(payload.text.prefix(maxCharacters)),
      elements: elements
    )
  }

  public func performAction(
    action: String,
    tabID: String?,
    ref: String?,
    selector: String?,
    targetText: String?,
    text: String?,
    key: String?,
    amount: Int?,
    timeoutMilliseconds: Int?
  ) async throws -> ManagedBrowserActionResult {
    let normalizedAction = action
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let port = try await requireConnectedPort()

    if normalizedAction == "activate_tab" {
      let id = try requiredValue(tabID, name: "tab_id")
      let target = try await resolveTarget(tabID: id, port: port)
      try await activateTarget(id: target.id, port: port)
      selectedTabID = target.id
      return actionResult(
        success: true,
        action: normalizedAction,
        message: "Tab aktiviert.",
        target: target
      )
    }

    if normalizedAction == "close_tab" {
      let id = try requiredValue(tabID, name: "tab_id")
      let target = try await resolveTarget(tabID: id, port: port)
      try await closeTarget(id: target.id, port: port)
      if selectedTabID == target.id {
        selectedTabID = nil
      }
      return ManagedBrowserActionResult(
        success: true,
        action: normalizedAction,
        message: "Tab geschlossen.",
        tabID: target.id,
        title: boundedDisplayText(target.title, limit: 300),
        url: sanitizedDisplayURL(target.url)
      )
    }

    let target = try await resolveTarget(tabID: tabID, port: port)
    selectedTabID = target.id
    try? await activateTarget(id: target.id, port: port)

    switch normalizedAction {
    case "click":
      let script = actionScript(
        action: "click",
        ref: ref,
        selector: selector,
        targetText: targetText,
        text: nil,
        timeoutMilliseconds: timeoutMilliseconds
      )
      let result = try await evaluateAction(
        on: target,
        expression: script,
        action: normalizedAction
      )
      try? await Task.sleep(for: .milliseconds(250))
      try? await waitForReadyState(
        tabID: target.id,
        timeoutMilliseconds: 8_000
      )
      return try await refreshedActionResult(
        result,
        targetID: target.id,
        port: port
      )

    case "fill":
      guard let text else {
        throw MicrosoftEdgeBrowserError.missingArgument("text")
      }
      guard text.utf8.count <= 128 * 1024 else {
        throw AgentRuntimeError.inputTooLarge(limit: 128 * 1024)
      }
      let script = actionScript(
        action: "fill",
        ref: ref,
        selector: selector,
        targetText: targetText,
        text: text,
        timeoutMilliseconds: timeoutMilliseconds
      )
      return try await evaluateAction(
        on: target,
        expression: script,
        action: normalizedAction
      )

    case "select":
      guard let text else {
        throw MicrosoftEdgeBrowserError.missingArgument("text")
      }
      let script = actionScript(
        action: "select",
        ref: ref,
        selector: selector,
        targetText: targetText,
        text: text,
        timeoutMilliseconds: timeoutMilliseconds
      )
      return try await evaluateAction(
        on: target,
        expression: script,
        action: normalizedAction
      )

    case "check", "uncheck":
      let script = actionScript(
        action: normalizedAction,
        ref: ref,
        selector: selector,
        targetText: targetText,
        text: nil,
        timeoutMilliseconds: timeoutMilliseconds
      )
      return try await evaluateAction(
        on: target,
        expression: script,
        action: normalizedAction
      )

    case "press":
      if ref != nil || selector != nil || targetText != nil {
        let focusScript = actionScript(
          action: "focus",
          ref: ref,
          selector: selector,
          targetText: targetText,
          text: nil,
          timeoutMilliseconds: timeoutMilliseconds
        )
        let focusResult = try await evaluateAction(
          on: target,
          expression: focusScript,
          action: "focus"
        )
        guard focusResult.success else {
          return focusResult
        }
      }
      let keyName = key ?? text
      guard let keyName, !keyName.isEmpty else {
        throw MicrosoftEdgeBrowserError.missingArgument("key")
      }
      try await dispatchKey(keyName, on: target)
      try? await Task.sleep(for: .milliseconds(200))
      try? await waitForReadyState(
        tabID: target.id,
        timeoutMilliseconds: 8_000
      )
      let refreshed = try? await resolveTarget(tabID: target.id, port: port)
      return actionResult(
        success: true,
        action: normalizedAction,
        message: "Taste \(keyName) gesendet.",
        target: refreshed ?? target
      )

    case "scroll":
      let distance = max(-20_000, min(amount ?? 700, 20_000))
      let expression = """
        (() => {
          window.scrollBy({ top: \(distance), left: 0, behavior: 'auto' });
          return JSON.stringify({
            success: true,
            message: 'Seite gescrollt.',
            title: document.title || '',
            url: location.href
          });
        })()
        """
      return try await evaluateAction(
        on: target,
        expression: expression,
        action: normalizedAction
      )

    case "wait":
      let timeout = max(
        100,
        min(timeoutMilliseconds ?? 5_000, 30_000)
      )
      if ref == nil && selector == nil && targetText == nil {
        try await Task.sleep(for: .milliseconds(timeout))
        let refreshed = try? await resolveTarget(tabID: target.id, port: port)
        return actionResult(
          success: true,
          action: normalizedAction,
          message: "\(timeout) ms gewartet.",
          target: refreshed ?? target
        )
      }
      let script = actionScript(
        action: "wait",
        ref: ref,
        selector: selector,
        targetText: targetText,
        text: nil,
        timeoutMilliseconds: timeout
      )
      return try await evaluateAction(
        on: target,
        expression: script,
        action: normalizedAction
      )

    case "back", "forward", "reload":
      let call = switch normalizedAction {
      case "back": "history.back()"
      case "forward": "history.forward()"
      default: "location.reload()"
      }
      let expression = """
        (() => {
          setTimeout(() => { \(call); }, 0);
          return JSON.stringify({
            success: true,
            message: '\(normalizedAction) ausgelöst.',
            title: document.title || '',
            url: location.href
          });
        })()
        """
      let result = try await evaluateAction(
        on: target,
        expression: expression,
        action: normalizedAction
      )
      try? await Task.sleep(for: .milliseconds(250))
      try? await waitForReadyState(
        tabID: target.id,
        timeoutMilliseconds: 8_000
      )
      return try await refreshedActionResult(
        result,
        targetID: target.id,
        port: port
      )

    default:
      throw MicrosoftEdgeBrowserError.invalidOperation(normalizedAction)
    }
  }

  private func ensureStarted() async throws -> Int {
    if let port = await connectedPortIfAvailable() {
      activePort = port
      return port
    }

    try ensureProfileDirectory()
    try? fileManager.removeItem(at: devToolsActivePortURL)
    let binary = try edgeBinaryURL()
    let launchedProcess = Process()
    launchedProcess.executableURL = binary
    launchedProcess.arguments = [
      "--remote-debugging-port=0",
      "--remote-debugging-address=127.0.0.1",
      "--user-data-dir=\(profileDirectory.path)",
      "--no-first-run",
      "--no-default-browser-check",
      "about:blank",
    ]
    launchedProcess.standardOutput = FileHandle.nullDevice
    launchedProcess.standardError = FileHandle.nullDevice

    do {
      try launchedProcess.run()
    } catch {
      throw MicrosoftEdgeBrowserError.launchFailed(error.localizedDescription)
    }
    process = launchedProcess

    for _ in 0..<150 {
      try Task.checkCancellation()
      if let port = readActivePort(), await canConnect(port: port) {
        activePort = port
        if let allTargets = try? await targets(port: port) {
          selectedTabID = allTargets.first(where: { $0.type == "page" })?.id
        }
        return port
      }
      if process?.isRunning == false {
        throw MicrosoftEdgeBrowserError.launchFailed(
          "Der Edge-Prozess wurde vorzeitig beendet."
        )
      }
      try await Task.sleep(for: .milliseconds(100))
    }

    if process?.isRunning == true {
      process?.terminate()
    }
    process = nil
    throw MicrosoftEdgeBrowserError.devToolsUnavailable(
      "DevToolsActivePort wurde nicht rechtzeitig bereitgestellt."
    )
  }

  private func connectedPortIfAvailable() async -> Int? {
    if let activePort, await canConnect(port: activePort) {
      return activePort
    }
    if let stored = readActivePort(), await canConnect(port: stored) {
      activePort = stored
      return stored
    }
    activePort = nil
    return nil
  }

  private func requireConnectedPort() async throws -> Int {
    guard let port = await connectedPortIfAvailable() else {
      throw MicrosoftEdgeBrowserError.sessionNotRunning
    }
    return port
  }

  private func canConnect(port: Int) async -> Bool {
    do {
      _ = try await browserVersion(port: port)
      return true
    } catch {
      return false
    }
  }

  private func browserVersion(port: Int) async throws -> BrowserVersion {
    try await requestJSON(
      port: port,
      path: "/json/version",
      method: "GET",
      as: BrowserVersion.self
    )
  }

  private func targets(port: Int) async throws -> [EdgeTarget] {
    try await requestJSON(
      port: port,
      path: "/json/list",
      method: "GET",
      as: [EdgeTarget].self
    )
  }

  private func createTab(urlText: String, port: Int) async throws -> EdgeTarget {
    let allowed = CharacterSet.alphanumerics.union(
      CharacterSet(charactersIn: "-._~")
    )
    guard let encodedURL = urlText.addingPercentEncoding(
      withAllowedCharacters: allowed
    ) else {
      throw MicrosoftEdgeBrowserError.invalidURL(urlText)
    }
    return try await requestJSON(
      port: port,
      path: "/json/new?\(encodedURL)",
      method: "PUT",
      as: EdgeTarget.self
    )
  }

  private func activateTarget(id: String, port: Int) async throws {
    _ = try await requestText(
      port: port,
      path: "/json/activate/\(id)",
      method: "GET"
    )
  }

  private func closeTarget(id: String, port: Int) async throws {
    _ = try await requestText(
      port: port,
      path: "/json/close/\(id)",
      method: "GET"
    )
  }

  private func resolveTarget(tabID: String?, port: Int) async throws -> EdgeTarget {
    let allTargets = try await targets(port: port)
    let pages = allTargets.filter { $0.type == "page" }
    if let tabID {
      guard let target = pages.first(where: {
        $0.id.caseInsensitiveCompare(tabID) == .orderedSame
      }) else {
        throw MicrosoftEdgeBrowserError.tabNotFound(tabID)
      }
      return target
    }
    if let selectedTabID,
      let target = pages.first(where: { $0.id == selectedTabID })
    {
      return target
    }
    guard let first = pages.first else {
      throw MicrosoftEdgeBrowserError.tabNotFound("kein Page-Tab")
    }
    return first
  }

  private func waitForReadyState(
    tabID: String,
    timeoutMilliseconds: Int
  ) async throws {
    let port = try await requireConnectedPort()
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(
      by: .milliseconds(timeoutMilliseconds)
    )
    while clock.now < deadline {
      try Task.checkCancellation()
      if let target = try? await resolveTarget(tabID: tabID, port: port),
        let state = try? await evaluateString(
          on: target,
          expression: "document.readyState"
        ),
        state == "complete" || state == "interactive"
      {
        return
      }
      try await Task.sleep(for: .milliseconds(150))
    }
  }

  private func evaluateString(
    on target: EdgeTarget,
    expression: String
  ) async throws -> String {
    let websocketURL = try targetWebSocketURL(target)
    let result: RuntimeEvaluateResult = try await sendCDP(
      websocketURL: websocketURL,
      method: "Runtime.evaluate",
      params: RuntimeEvaluateParams(
        expression: expression,
        returnByValue: true,
        awaitPromise: true,
        userGesture: true
      ),
      resultType: RuntimeEvaluateResult.self
    )
    if let exception = result.exceptionDetails {
      throw MicrosoftEdgeBrowserError.pageEvaluationFailed(
        exception.text ?? result.result.description ?? "JavaScript exception"
      )
    }
    guard let value = result.result.value else {
      throw MicrosoftEdgeBrowserError.pageEvaluationFailed(
        result.result.description ?? "Kein Ergebnis"
      )
    }
    return value
  }

  private func evaluateAction(
    on target: EdgeTarget,
    expression: String,
    action: String
  ) async throws -> ManagedBrowserActionResult {
    let raw = try await evaluateString(on: target, expression: expression)
    guard let data = raw.data(using: .utf8) else {
      throw MicrosoftEdgeBrowserError.pageEvaluationFailed(
        "Action-Ergebnis ist kein UTF-8-JSON."
      )
    }
    let payload = try JSONDecoder().decode(ActionPayload.self, from: data)
    return ManagedBrowserActionResult(
      success: payload.success,
      action: action,
      message: payload.message,
      tabID: target.id,
      title: payload.title.map { boundedDisplayText($0, limit: 300) },
      url: payload.url.map { sanitizedDisplayURL($0) }
    )
  }

  private func refreshedActionResult(
    _ result: ManagedBrowserActionResult,
    targetID: String,
    port: Int
  ) async throws -> ManagedBrowserActionResult {
    guard result.success else {
      return result
    }
    let target = try? await resolveTarget(tabID: targetID, port: port)
    return ManagedBrowserActionResult(
      success: result.success,
      action: result.action,
      message: result.message,
      tabID: target?.id ?? result.tabID,
      title: target.map { boundedDisplayText($0.title, limit: 300) }
        ?? result.title,
      url: target.map { sanitizedDisplayURL($0.url) }
        ?? result.url
    )
  }

  private func actionScript(
    action: String,
    ref: String?,
    selector: String?,
    targetText: String?,
    text: String?,
    timeoutMilliseconds: Int?
  ) -> String {
    let refJSON = jsLiteral(ref ?? "")
    let selectorJSON = jsLiteral(selector ?? "")
    let targetTextJSON = jsLiteral(targetText ?? "")
    let textJSON = jsLiteral(text ?? "")
    let timeout = max(
      100,
      min(timeoutMilliseconds ?? 5_000, 30_000)
    )

    return """
      (async () => {
        const REF = \(refJSON);
        const SELECTOR = \(selectorJSON);
        const TARGET_TEXT = \(targetTextJSON);
        const VALUE = \(textJSON);
        const TIMEOUT = \(timeout);
        const visible = (el) => {
          if (!el) return false;
          const style = getComputedStyle(el);
          if (style.display === 'none' || style.visibility === 'hidden') return false;
          const rect = el.getBoundingClientRect();
          return rect.width > 0 && rect.height > 0;
        };
        const labelText = (el) => [
          el.innerText,
          el.textContent,
          el.getAttribute && el.getAttribute('aria-label'),
          el.getAttribute && el.getAttribute('placeholder'),
          el.getAttribute && el.getAttribute('title'),
          el.tagName === 'INPUT' && ['button','submit','reset'].includes((el.type || '').toLowerCase()) ? el.value : ''
        ].filter(Boolean).join(' ').replace(/\\s+/g, ' ').trim();
        const findTarget = () => {
          if (REF) {
            try {
              const byRef = document.querySelector(`[data-agentm5n-ref="${CSS.escape(REF)}"]`);
              if (byRef) return byRef;
            } catch (_) {}
          }
          if (SELECTOR) {
            try {
              const bySelector = document.querySelector(SELECTOR);
              if (bySelector) return bySelector;
            } catch (_) {}
          }
          if (TARGET_TEXT) {
            const needle = TARGET_TEXT.toLocaleLowerCase();
            const candidates = Array.from(document.querySelectorAll('a,button,input,textarea,select,[role="button"],[role="link"],[role="checkbox"],[role="menuitem"],[contenteditable="true"]'))
              .filter(visible)
              .filter((el) => labelText(el).toLocaleLowerCase().includes(needle))
              .sort((a, b) => labelText(a).length - labelText(b).length);
            if (candidates.length) return candidates[0];
          }
          return null;
        };
        const result = (success, message) => JSON.stringify({
          success,
          message,
          title: document.title || '',
          url: location.href
        });
        try {
          if ('\(action)' === 'wait') {
            const started = Date.now();
            while (Date.now() - started < TIMEOUT) {
              const el = findTarget();
              if (el && visible(el)) return result(true, 'Element ist verfügbar.');
              await new Promise((resolve) => setTimeout(resolve, 100));
            }
            return result(false, 'Element wurde innerhalb des Timeouts nicht gefunden.');
          }

          const el = findTarget();
          if (!el) {
            return result(false, 'Zielelement wurde nicht gefunden. Bitte browser_read erneut ausführen.');
          }
          if (!visible(el)) return result(false, 'Zielelement ist nicht sichtbar.');
          if (el.disabled || el.getAttribute('aria-disabled') === 'true') {
            return result(false, 'Zielelement ist deaktiviert.');
          }
          el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'auto' });

          if ('\(action)' === 'focus') {
            el.focus();
            return result(true, 'Element fokussiert.');
          }
          if ('\(action)' === 'click') {
            el.focus();
            setTimeout(() => el.click(), 0);
            return result(true, 'Klick ausgelöst.');
          }
          if ('\(action)' === 'fill') {
            const tag = el.tagName.toLowerCase();
            const inputType = tag === 'input'
              ? (el.getAttribute('type') || 'text').toLowerCase()
              : '';
            if (tag === 'input' && inputType === 'file') {
              return result(false, 'Datei-Inputs werden nicht durch Text-Fill gesetzt.');
            }
            if (tag === 'input' && inputType === 'password') {
              return result(false, 'Passwortfelder werden nicht mit modellseitigem Klartext gefüllt. Melde dich bei Bedarf einmal manuell im persistenten AgenTM5N-Edge-Profil an.');
            }
            el.focus();
            if (el.isContentEditable) {
              el.textContent = VALUE;
            } else if ('value' in el) {
              const prototype = Object.getPrototypeOf(el);
              const descriptor = Object.getOwnPropertyDescriptor(prototype, 'value');
              if (descriptor && descriptor.set) descriptor.set.call(el, VALUE);
              else el.value = VALUE;
            } else {
              return result(false, 'Element unterstützt keine Texteingabe.');
            }
            el.dispatchEvent(new InputEvent('input', {
              bubbles: true,
              inputType: 'insertText',
              data: VALUE
            }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            return result(true, 'Text eingegeben.');
          }
          if ('\(action)' === 'select') {
            if (el.tagName.toLowerCase() !== 'select') {
              return result(false, 'Zielelement ist kein Select-Feld.');
            }
            const needle = VALUE.toLocaleLowerCase();
            const option = Array.from(el.options).find((item) =>
              String(item.value).toLocaleLowerCase() === needle ||
              String(item.textContent || '').trim().toLocaleLowerCase() === needle
            );
            if (!option) return result(false, 'Select-Option wurde nicht gefunden.');
            el.value = option.value;
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            return result(true, 'Option ausgewählt.');
          }
          if ('\(action)' === 'check' || '\(action)' === 'uncheck') {
            if (typeof el.checked !== 'boolean') {
              return result(false, 'Zielelement ist keine Checkbox/Radio-Auswahl.');
            }
            const desired = '\(action)' === 'check';
            const prototype = Object.getPrototypeOf(el);
            const descriptor = Object.getOwnPropertyDescriptor(prototype, 'checked');
            if (descriptor && descriptor.set) descriptor.set.call(el, desired);
            else el.checked = desired;
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            return result(true, desired ? 'Auswahl aktiviert.' : 'Auswahl deaktiviert.');
          }
          return result(false, 'Nicht unterstützte DOM-Aktion.');
        } catch (error) {
          return result(false, String(error && error.message ? error.message : error));
        }
      })()
      """
  }

  private func dispatchKey(
    _ keyName: String,
    on target: EdgeTarget
  ) async throws {
    let websocketURL = try targetWebSocketURL(target)
    let spec = keySpec(keyName)
    let down = KeyEventParams(
      type: "keyDown",
      key: spec.key,
      code: spec.code,
      windowsVirtualKeyCode: spec.virtualKey,
      nativeVirtualKeyCode: spec.virtualKey,
      text: spec.text
    )
    let up = KeyEventParams(
      type: "keyUp",
      key: spec.key,
      code: spec.code,
      windowsVirtualKeyCode: spec.virtualKey,
      nativeVirtualKeyCode: spec.virtualKey,
      text: nil
    )
    let _: EmptyResult = try await sendCDP(
      websocketURL: websocketURL,
      method: "Input.dispatchKeyEvent",
      params: down,
      resultType: EmptyResult.self
    )
    let _: EmptyResult = try await sendCDP(
      websocketURL: websocketURL,
      method: "Input.dispatchKeyEvent",
      params: up,
      resultType: EmptyResult.self
    )
  }

  private func keySpec(_ value: String) -> KeySpec {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "enter", "return":
      KeySpec(key: "Enter", code: "Enter", virtualKey: 13, text: "\r")
    case "tab":
      KeySpec(key: "Tab", code: "Tab", virtualKey: 9, text: "\t")
    case "escape", "esc":
      KeySpec(key: "Escape", code: "Escape", virtualKey: 27, text: nil)
    case "backspace":
      KeySpec(key: "Backspace", code: "Backspace", virtualKey: 8, text: nil)
    case "arrowdown", "down":
      KeySpec(key: "ArrowDown", code: "ArrowDown", virtualKey: 40, text: nil)
    case "arrowup", "up":
      KeySpec(key: "ArrowUp", code: "ArrowUp", virtualKey: 38, text: nil)
    case "arrowleft", "left":
      KeySpec(key: "ArrowLeft", code: "ArrowLeft", virtualKey: 37, text: nil)
    case "arrowright", "right":
      KeySpec(key: "ArrowRight", code: "ArrowRight", virtualKey: 39, text: nil)
    case "space", "spacebar":
      KeySpec(key: " ", code: "Space", virtualKey: 32, text: " ")
    default:
      let first = String(value.prefix(1))
      let scalarValue = first.uppercased().unicodeScalars.first.map {
        Int($0.value)
      } ?? 0
      return KeySpec(
        key: first,
        code: first,
        virtualKey: scalarValue,
        text: first
      )
    }
  }

  private func sendCDP<
    Params: Codable & Sendable,
    Result: Codable & Sendable
  >(
    websocketURL: URL,
    method: String,
    params: Params,
    resultType: Result.Type
  ) async throws -> Result {
    let validatedURL = try validatedCDPWebSocketURL(websocketURL)
    let id = nextCommandID
    nextCommandID += 1
    let command = CDPCommand(id: id, method: method, params: params)
    let data = try JSONEncoder().encode(command)
    let task = session.webSocketTask(with: validatedURL)
    task.resume()
    defer {
      task.cancel(with: .normalClosure, reason: nil)
    }

    try await task.send(.data(data))
    while true {
      try Task.checkCancellation()
      let message = try await task.receive()
      let responseData: Data
      switch message {
      case .data(let data):
        responseData = data
      case .string(let string):
        responseData = Data(string.utf8)
      @unknown default:
        continue
      }
      let header = try JSONDecoder().decode(CDPHeader.self, from: responseData)
      guard header.id == id else {
        continue
      }
      let envelope = try JSONDecoder().decode(
        CDPEnvelope<Result>.self,
        from: responseData
      )
      if let error = envelope.error {
        throw MicrosoftEdgeBrowserError.protocolFailure(
          "\(error.code): \(error.message)"
        )
      }
      guard let result = envelope.result else {
        throw MicrosoftEdgeBrowserError.protocolFailure(
          "CDP-Antwort enthält kein result für \(method)."
        )
      }
      return result
    }
  }

  private func requestJSON<T: Decodable & Sendable>(
    port: Int,
    path: String,
    method: String,
    as type: T.Type
  ) async throws -> T {
    let data = try await requestData(port: port, path: path, method: method)
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw MicrosoftEdgeBrowserError.protocolFailure(
        "Ungültige JSON-Antwort für \(path): \(error.localizedDescription)"
      )
    }
  }

  private func requestText(
    port: Int,
    path: String,
    method: String
  ) async throws -> String {
    let data = try await requestData(port: port, path: path, method: method)
    return String(decoding: data, as: UTF8.self)
  }

  private func requestData(
    port: Int,
    path: String,
    method: String
  ) async throws -> Data {
    guard (1...65_535).contains(port),
      let url = URL(string: "http://127.0.0.1:\(port)\(path)")
    else {
      throw MicrosoftEdgeBrowserError.devToolsUnavailable(
        "Ungültiger lokaler DevTools-Endpunkt."
      )
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 10
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse,
      (200...299).contains(http.statusCode)
    else {
      let status = (response as? HTTPURLResponse)?.statusCode ?? -1
      throw MicrosoftEdgeBrowserError.devToolsUnavailable(
        "HTTP \(status) für \(path)"
      )
    }
    guard data.count <= 4 * 1024 * 1024 else {
      throw MicrosoftEdgeBrowserError.protocolFailure(
        "DevTools-Antwort überschreitet das 4-MiB-Limit."
      )
    }
    return data
  }

  private func validateBrowserURL(_ value: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty,
      let url = URL(string: normalized)
    else {
      throw MicrosoftEdgeBrowserError.invalidURL(value)
    }
    let scheme = url.scheme?.lowercased() ?? ""
    guard ["http", "https", "edge", "about"].contains(scheme) else {
      throw MicrosoftEdgeBrowserError.invalidURL(value)
    }
    if scheme == "http" || scheme == "https" {
      guard url.host != nil,
        url.user == nil,
        url.password == nil
      else {
        throw MicrosoftEdgeBrowserError.invalidURL(value)
      }
    }
    return normalized
  }

  private func targetWebSocketURL(_ target: EdgeTarget) throws -> URL {
    guard let websocket = target.webSocketDebuggerUrl,
      let url = URL(string: websocket)
    else {
      throw MicrosoftEdgeBrowserError.protocolFailure(
        "Tab besitzt keinen DevTools-WebSocket."
      )
    }
    return try validatedCDPWebSocketURL(url)
  }

  private func validatedCDPWebSocketURL(_ url: URL) throws -> URL {
    let scheme = url.scheme?.lowercased() ?? ""
    let host = url.host?.lowercased() ?? ""
    guard ["ws", "wss"].contains(scheme),
      ["127.0.0.1", "localhost", "::1"].contains(host)
    else {
      throw MicrosoftEdgeBrowserError.protocolFailure(
        "Nicht-lokaler DevTools-WebSocket wurde blockiert."
      )
    }
    return url
  }

  private func actionResult(
    success: Bool,
    action: String,
    message: String,
    target: EdgeTarget
  ) -> ManagedBrowserActionResult {
    ManagedBrowserActionResult(
      success: success,
      action: action,
      message: message,
      tabID: target.id,
      title: boundedDisplayText(target.title, limit: 300),
      url: sanitizedDisplayURL(target.url)
    )
  }

  private func stoppedStatus() -> ManagedBrowserStatus {
    ManagedBrowserStatus(
      running: false,
      browser: nil,
      protocolVersion: nil,
      profile: "AgenTM5N Managed Microsoft Edge",
      tabCount: 0
    )
  }

  private func sanitizedDisplayURL(_ value: String) -> String {
    guard var components = URLComponents(string: value) else {
      return boundedDisplayText(value, limit: 2_000)
    }
    components.user = nil
    components.password = nil
    components.fragment = nil
    if let queryItems = components.queryItems {
      components.queryItems = queryItems.map { item in
        URLQueryItem(
          name: item.name,
          value: item.value == nil ? nil : "<redacted>"
        )
      }
    }
    return boundedDisplayText(components.string ?? value, limit: 2_000)
  }

  private func boundedDisplayText(_ value: String, limit: Int) -> String {
    value.count > limit ? String(value.prefix(limit)) + "…" : value
  }

  private func requiredString(
    _ name: String,
    in call: ProviderToolCall
  ) throws -> String {
    guard let value = optionalString(name, in: call) else {
      throw AgentRuntimeError.missingArgument(
        tool: call.function.name,
        name: name
      )
    }
    return value
  }

  private func optionalString(
    _ name: String,
    in call: ProviderToolCall
  ) -> String? {
    guard let value = call.function.arguments[name]?.stringValue else {
      return nil
    }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }

  private func optionalStringAllowingEmpty(
    _ name: String,
    in call: ProviderToolCall
  ) -> String? {
    call.function.arguments[name]?.stringValue
  }

  private func optionalInt(
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

  private func requiredValue(_ value: String?, name: String) throws -> String {
    guard let value, !value.isEmpty else {
      throw MicrosoftEdgeBrowserError.missingArgument(name)
    }
    return value
  }

  private func encoded<T: Encodable>(
    _ value: T,
    success: Bool = true
  ) -> ToolExecutionResult {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(value)
      return ToolExecutionResult(
        success: success,
        output: String(decoding: data, as: UTF8.self)
      )
    } catch {
      return ToolExecutionResult(
        success: false,
        output: error.localizedDescription
      )
    }
  }

  private func jsLiteral(_ value: String) -> String {
    guard let data = try? JSONEncoder().encode(value) else {
      return "\"\""
    }
    return String(decoding: data, as: UTF8.self)
  }

  private func ensureProfileDirectory() throws {
    try fileManager.createDirectory(
      at: profileDirectory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try? fileManager.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: profileDirectory.path
    )
  }

  private func readActivePort() -> Int? {
    guard let text = try? String(
      contentsOf: devToolsActivePortURL,
      encoding: .utf8
    ) else {
      return nil
    }
    return text
      .split(whereSeparator: { $0.isNewline })
      .first
      .flatMap { Int($0) }
  }

  private func edgeBinaryURL() throws -> URL {
    let candidates = [
      "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
      NSString(
        string: "~/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
      ).expandingTildeInPath,
      "/Applications/Microsoft Edge Beta.app/Contents/MacOS/Microsoft Edge Beta",
      "/Applications/Microsoft Edge Dev.app/Contents/MacOS/Microsoft Edge Dev",
      "/Applications/Microsoft Edge Canary.app/Contents/MacOS/Microsoft Edge Canary",
    ]
    guard let path = candidates.first(where: {
      fileManager.isExecutableFile(atPath: $0)
    }) else {
      throw MicrosoftEdgeBrowserError.edgeNotInstalled
    }
    return URL(fileURLWithPath: path)
  }

  private var profileDirectory: URL {
    let base = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first
      ?? fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support", isDirectory: true)
    return base
      .appendingPathComponent("AgenTM5N", isDirectory: true)
      .appendingPathComponent("Browser", isDirectory: true)
      .appendingPathComponent("MicrosoftEdge", isDirectory: true)
  }

  private var devToolsActivePortURL: URL {
    profileDirectory.appendingPathComponent(
      "DevToolsActivePort",
      isDirectory: false
    )
  }
}
