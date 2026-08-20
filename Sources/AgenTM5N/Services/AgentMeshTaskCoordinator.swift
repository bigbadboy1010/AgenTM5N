import Foundation

public enum AgentMeshTaskCoordinatorError: LocalizedError, Equatable {
  case executorUnavailable
  case invalidPrompt
  case taskNotFound
  case peerMismatch
  case busy
  case timedOut

  public var errorDescription: String? {
    switch self {
    case .executorUnavailable:
      return "Agent Mesh Task Executor ist noch nicht verfuegbar."
    case .invalidPrompt:
      return "Agent Mesh Task Prompt ist leer oder zu gross."
    case .taskNotFound:
      return "Agent Mesh Task wurde nicht gefunden."
    case .peerMismatch:
      return "Agent Mesh Task gehoert zu einem anderen Peer."
    case .busy:
      return "Agent Mesh Node verarbeitet bereits einen delegierten Task."
    case .timedOut:
      return "Agent Mesh Task hat sein Zeitlimit erreicht."
    }
  }
}

public actor AgentMeshTaskCoordinator {
  public typealias EventSink = @Sendable (AgentMeshTaskEventKind, String) async -> Void
  public typealias Executor = @Sendable (
    AgentMeshTaskRequest,
    AgentMeshPeerRecord,
    Set<AgentToolCapability>,
    @escaping EventSink
  ) async throws -> String

  public static let shared = AgentMeshTaskCoordinator()

  private var executor: Executor?
  private var snapshots: [UUID: AgentMeshTaskSnapshot] = [:]
  private var events: [UUID: [AgentMeshTaskEvent]] = [:]
  private var tasks: [UUID: Task<Void, Never>] = [:]
  private var activeTaskID: UUID?
  private static let maximumRetainedTasks = 200

  public init() {}

  public func installExecutor(_ executor: @escaping Executor) {
    self.executor = executor
  }

  @discardableResult
  public func submit(
    _ request: AgentMeshTaskRequest,
    from peer: AgentMeshPeerRecord
  ) throws -> AgentMeshTaskSnapshot {
    guard peer.status == .trusted else { throw AgentMeshSecurityError.peerNotTrusted }

    if let existing = snapshots[request.id] {
      guard existing.peerID == peer.id else {
        throw AgentMeshTaskCoordinatorError.peerMismatch
      }
      return existing
    }

    let cleanPrompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanPrompt.isEmpty, cleanPrompt.count <= AgentMeshProtocol.maximumPromptCharacters else {
      throw AgentMeshTaskCoordinatorError.invalidPrompt
    }
    guard executor != nil else { throw AgentMeshTaskCoordinatorError.executorUnavailable }
    guard activeTaskID == nil else { throw AgentMeshTaskCoordinatorError.busy }

    pruneTerminalHistoryIfNeeded()

    let effectiveCapabilities: Set<AgentToolCapability>
    if request.requestedCapabilities.isEmpty {
      effectiveCapabilities = peer.allowedCapabilities
    } else {
      effectiveCapabilities = peer.allowedCapabilities.intersection(request.requestedCapabilities)
    }

    let snapshot = AgentMeshTaskSnapshot(
      id: request.id,
      correlationID: request.correlationID,
      peerID: peer.id,
      requestedCapabilities: request.requestedCapabilities,
      effectiveCapabilities: effectiveCapabilities
    )
    snapshots[request.id] = snapshot
    events[request.id] = []
    appendEvent(taskID: request.id, kind: .accepted, message: "Task accepted")
    activeTaskID = request.id

    let task = Task { [weak self] in
      guard let self else { return }
      await self.run(request, peer: peer, effectiveCapabilities: effectiveCapabilities)
    }
    tasks[request.id] = task
    return snapshot
  }

  public func snapshot(taskID: UUID, peerID: UUID) throws -> AgentMeshTaskSnapshot {
    guard let snapshot = snapshots[taskID] else {
      throw AgentMeshTaskCoordinatorError.taskNotFound
    }
    guard snapshot.peerID == peerID else { throw AgentMeshTaskCoordinatorError.peerMismatch }
    return snapshot
  }

  public func eventBatch(
    taskID: UUID,
    peerID: UUID,
    afterEventID: Int
  ) throws -> AgentMeshTaskEventBatch {
    let snapshot = try snapshot(taskID: taskID, peerID: peerID)
    let taskEvents = events[taskID] ?? []
    let selected = taskEvents.filter { $0.id > afterEventID }
    let nextID = taskEvents.last?.id ?? afterEventID
    let terminal = Self.isTerminal(snapshot.status)
    return AgentMeshTaskEventBatch(
      taskID: taskID,
      events: selected,
      nextEventID: nextID,
      terminal: terminal
    )
  }

  public func cancel(taskID: UUID, peerID: UUID) async throws -> AgentMeshTaskSnapshot {
    let current = try snapshot(taskID: taskID, peerID: peerID)
    guard !Self.isTerminal(current.status) else { return current }

    // Do not release activeTaskID here. The run() tail owns that transition,
    // so a second remote task cannot overlap an executor that is still winding
    // down after cancellation.
    if let task = tasks[taskID] {
      task.cancel()
      await task.value
    }
    return try snapshot(taskID: taskID, peerID: peerID)
  }

  public func cancelAll(peerID: UUID) async {
    let matching = snapshots.values
      .filter { $0.peerID == peerID && !Self.isTerminal($0.status) }
      .map(\.id)
    for id in matching {
      if let task = tasks[id] {
        task.cancel()
        await task.value
      }
    }
  }

  public func localSnapshots() -> [AgentMeshTaskSnapshot] {
    snapshots.values.sorted { $0.createdAt > $1.createdAt }
  }

  public func localEvents(taskID: UUID) -> [AgentMeshTaskEvent] {
    events[taskID] ?? []
  }

  private func run(
    _ request: AgentMeshTaskRequest,
    peer: AgentMeshPeerRecord,
    effectiveCapabilities: Set<AgentToolCapability>
  ) async {
    guard let executor else {
      await fail(request.id, error: AgentMeshTaskCoordinatorError.executorUnavailable)
      return
    }

    var snapshot = snapshots[request.id]
    snapshot?.status = .running
    snapshot?.startedAt = Date()
    if let snapshot { snapshots[request.id] = snapshot }
    appendEvent(taskID: request.id, kind: .started, message: "Task started")

    let sink: EventSink = { [weak self] kind, message in
      await self?.appendExternalEvent(taskID: request.id, kind: kind, message: message)
    }

    do {
      let result = try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask {
          try await executor(request, peer, effectiveCapabilities, sink)
        }
        group.addTask {
          try await Task.sleep(for: .seconds(request.timeoutSeconds))
          throw AgentMeshTaskCoordinatorError.timedOut
        }
        guard let value = try await group.next() else {
          throw AgentMeshTaskCoordinatorError.executorUnavailable
        }
        group.cancelAll()
        return value
      }
      try Task.checkCancellation()

      var completed = snapshots[request.id]
      completed?.status = .completed
      completed?.result = String(result.prefix(request.maximumResultCharacters))
      completed?.completedAt = Date()
      if let completed { snapshots[request.id] = completed }
      appendEvent(taskID: request.id, kind: .completed, message: "Task completed")
    } catch is CancellationError {
      if snapshots[request.id]?.status != .cancelled {
        var cancelled = snapshots[request.id]
        cancelled?.status = .cancelled
        cancelled?.completedAt = Date()
        if let cancelled { snapshots[request.id] = cancelled }
        appendEvent(taskID: request.id, kind: .cancelled, message: "Task cancelled")
      }
    } catch {
      await fail(request.id, error: error)
    }

    tasks.removeValue(forKey: request.id)
    if activeTaskID == request.id { activeTaskID = nil }
  }

  private func fail(_ taskID: UUID, error: Error) async {
    var failed = snapshots[taskID]
    failed?.status = .failed
    failed?.error = String(error.localizedDescription.prefix(AgentMeshProtocol.maximumEventCharacters))
    failed?.completedAt = Date()
    if let failed { snapshots[taskID] = failed }
    appendEvent(taskID: taskID, kind: .failed, message: error.localizedDescription)
    tasks.removeValue(forKey: taskID)
    if activeTaskID == taskID { activeTaskID = nil }
  }

  private func appendExternalEvent(
    taskID: UUID,
    kind: AgentMeshTaskEventKind,
    message: String
  ) {
    guard snapshots[taskID] != nil else { return }
    if kind == .approvalRequired {
      var snapshot = snapshots[taskID]
      snapshot?.status = .waitingForApproval
      if let snapshot { snapshots[taskID] = snapshot }
    } else if kind == .toolCompleted || kind == .toolDenied || kind == .delta || kind == .thinking {
      if snapshots[taskID]?.status == .waitingForApproval {
        var snapshot = snapshots[taskID]
        snapshot?.status = .running
        if let snapshot { snapshots[taskID] = snapshot }
      }
    }
    appendEvent(taskID: taskID, kind: kind, message: message)
  }

  private func appendEvent(
    taskID: UUID,
    kind: AgentMeshTaskEventKind,
    message: String
  ) {
    var taskEvents = events[taskID] ?? []
    let id = (taskEvents.last?.id ?? 0) + 1
    taskEvents.append(
      AgentMeshTaskEvent(
        id: id,
        taskID: taskID,
        kind: kind,
        message: message
      )
    )
    if taskEvents.count > 2_048 {
      taskEvents.removeFirst(taskEvents.count - 2_048)
    }
    events[taskID] = taskEvents
  }

  private func pruneTerminalHistoryIfNeeded() {
    guard snapshots.count >= Self.maximumRetainedTasks else { return }
    let removable = snapshots.values
      .filter { Self.isTerminal($0.status) && $0.id != activeTaskID }
      .sorted { $0.completedAt ?? $0.createdAt < $1.completedAt ?? $1.createdAt }
    let targetCount = max(1, snapshots.count - Self.maximumRetainedTasks + 1)
    for snapshot in removable.prefix(targetCount) {
      snapshots.removeValue(forKey: snapshot.id)
      events.removeValue(forKey: snapshot.id)
      tasks.removeValue(forKey: snapshot.id)
    }
  }

  private static func isTerminal(_ status: AgentMeshTaskStatus) -> Bool {
    switch status {
    case .completed, .failed, .cancelled:
      true
    case .queued, .running, .waitingForApproval:
      false
    }
  }
}
