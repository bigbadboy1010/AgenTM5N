import Foundation

public actor AgentToolExecutionBridge {
  public typealias Executor = @Sendable (ProviderToolCall) async -> String

  public static let shared = AgentToolExecutionBridge()

  private struct CapabilityScopeFrame: Sendable {
    let id: UUID
    let capabilities: Set<AgentToolCapability>
  }

  private var sessionID: UUID?
  private var executor: Executor?
  private var capabilityScopes: [CapabilityScopeFrame] = []
  private var executionBusy = false
  private var executionWaiters: [CheckedContinuation<Void, Never>] = []

  public init() {}

  public func install(
    sessionID: UUID,
    executor: @escaping Executor
  ) {
    self.sessionID = sessionID
    self.executor = executor
    capabilityScopes.removeAll(keepingCapacity: true)
    executionBusy = false
    let waiters = executionWaiters
    executionWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters {
      waiter.resume()
    }
  }

  public func clear(sessionID: UUID) {
    guard self.sessionID == sessionID else { return }
    self.sessionID = nil
    executor = nil
    capabilityScopes.removeAll(keepingCapacity: true)
    executionBusy = false
    let waiters = executionWaiters
    executionWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters {
      waiter.resume()
    }
  }

  /// Persists a delegated capability scope across Foundation Models-created
  /// tool-call tasks. Nested scopes can only reduce the currently active scope;
  /// they can never add a capability that an outer specialist did not have.
  @discardableResult
  public func pushCapabilityScope(
    _ requested: Set<AgentToolCapability>
  ) -> UUID {
    let effective = capabilityScopes.last
      .map { $0.capabilities.intersection(requested) }
      ?? requested
    let id = UUID()
    capabilityScopes.append(
      CapabilityScopeFrame(id: id, capabilities: effective)
    )
    return id
  }

  public func popCapabilityScope(_ id: UUID) {
    guard let index = capabilityScopes.lastIndex(where: { $0.id == id }) else {
      return
    }
    capabilityScopes.remove(at: index)
  }

  public func execute(_ call: ProviderToolCall) async -> String {
    await acquireExecutionPermit()
    defer { releaseExecutionPermit() }

    let scope = capabilityScopes.last?.capabilities
      ?? AgentCapabilityExecutionContext.allowedCapabilities

    if let scope,
      !AgentToolRegistry.isAllowed(call.function.name, within: scope)
    {
      let capability = AgentToolRegistry.entry(named: call.function.name)?.capability.rawValue
        ?? "unknown"
      return "TOOL_ERROR: CAPABILITY_DENIED — \(call.function.name) benötigt Capability \(capability)."
    }

    guard let executor else {
      return "TOOL_ERROR: AgenTM5N provider-neutral tool router is not active."
    }

    if let scope {
      return await AgentCapabilityExecutionContext.$allowedCapabilities
        .withValue(scope) {
          await executor(call)
        }
    }

    return await executor(call)
  }

  /// Foundation Models may schedule several tool adapters concurrently. AppState
  /// intentionally displays one approval sheet at a time, so native tool execution
  /// is serialized here before it reaches the shared permission/audit router. The
  /// Ollama loops are already sequential; this closes the framework-concurrency gap
  /// without allowing one pending approval continuation to overwrite another.
  private func acquireExecutionPermit() async {
    if !executionBusy {
      executionBusy = true
      return
    }

    await withCheckedContinuation { continuation in
      executionWaiters.append(continuation)
    }
  }

  private func releaseExecutionPermit() {
    if executionWaiters.isEmpty {
      executionBusy = false
      return
    }

    let next = executionWaiters.removeFirst()
    // Keep executionBusy true: ownership transfers directly to the next waiter.
    next.resume()
  }
}