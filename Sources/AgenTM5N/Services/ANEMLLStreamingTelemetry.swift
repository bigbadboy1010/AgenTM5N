import Foundation

public enum ANEMLLStreamingState: String, Codable, Equatable, Sendable {
  case streaming
  case completed
  case cancelled
  case failed
}

public struct ANEMLLStreamingTelemetrySnapshot: Equatable, Sendable {
  public let streamID: UUID
  public let startedAt: Date
  public let firstDeltaAt: Date?
  public let finishedAt: Date?
  public let chunkCount: Int
  public let characterCount: Int
  public let state: ANEMLLStreamingState
  public let activeTurns: Int
  public let metrics: ANEMLLRuntimeMetrics?

  public init(
    streamID: UUID,
    startedAt: Date,
    firstDeltaAt: Date?,
    finishedAt: Date?,
    chunkCount: Int,
    characterCount: Int,
    state: ANEMLLStreamingState,
    activeTurns: Int,
    metrics: ANEMLLRuntimeMetrics?
  ) {
    self.streamID = streamID
    self.startedAt = startedAt
    self.firstDeltaAt = firstDeltaAt
    self.finishedAt = finishedAt
    self.chunkCount = max(0, chunkCount)
    self.characterCount = max(0, characterCount)
    self.state = state
    self.activeTurns = max(0, activeTurns)
    self.metrics = metrics
  }

  public var firstDeltaLatencyMilliseconds: Double? {
    guard let firstDeltaAt else { return nil }
    return max(0, firstDeltaAt.timeIntervalSince(startedAt) * 1_000)
  }

  public var wallMilliseconds: Double? {
    guard let finishedAt else { return nil }
    return max(0, finishedAt.timeIntervalSince(startedAt) * 1_000)
  }
}

/// Thread-safe, bounded-to-one-snapshot telemetry for the active/latest Qwen3
/// stream. It deliberately stores no prompt, generated text, attachment data,
/// tool arguments or secret material.
public final class ANEMLLStreamingTelemetry: @unchecked Sendable {
  public static let shared = ANEMLLStreamingTelemetry()

  private let lock = NSLock()
  private var snapshot: ANEMLLStreamingTelemetrySnapshot?

  public init() {}

  @discardableResult
  public func begin(at date: Date = Date()) -> UUID {
    let id = UUID()
    let fresh = ANEMLLStreamingTelemetrySnapshot(
      streamID: id,
      startedAt: date,
      firstDeltaAt: nil,
      finishedAt: nil,
      chunkCount: 0,
      characterCount: 0,
      state: .streaming,
      activeTurns: 0,
      metrics: nil
    )
    lock.lock()
    snapshot = fresh
    lock.unlock()
    return id
  }

  public func recordDelta(
    streamID: UUID,
    characterCount: Int,
    at date: Date = Date()
  ) {
    guard characterCount > 0 else { return }
    lock.lock()
    defer { lock.unlock() }
    guard let current = snapshot,
      current.streamID == streamID,
      current.state == .streaming
    else {
      return
    }
    snapshot = ANEMLLStreamingTelemetrySnapshot(
      streamID: current.streamID,
      startedAt: current.startedAt,
      firstDeltaAt: current.firstDeltaAt ?? date,
      finishedAt: nil,
      chunkCount: current.chunkCount + 1,
      characterCount: current.characterCount + characterCount,
      state: .streaming,
      activeTurns: current.activeTurns,
      metrics: current.metrics
    )
  }

  public func complete(
    streamID: UUID,
    metrics: ANEMLLRuntimeMetrics,
    activeTurns: Int,
    at date: Date = Date()
  ) {
    finish(
      streamID: streamID,
      state: .completed,
      metrics: metrics,
      activeTurns: activeTurns,
      at: date
    )
  }

  public func cancel(
    streamID: UUID,
    activeTurns: Int = 0,
    at date: Date = Date()
  ) {
    finish(
      streamID: streamID,
      state: .cancelled,
      metrics: nil,
      activeTurns: activeTurns,
      at: date
    )
  }

  public func fail(
    streamID: UUID,
    activeTurns: Int = 0,
    at date: Date = Date()
  ) {
    finish(
      streamID: streamID,
      state: .failed,
      metrics: nil,
      activeTurns: activeTurns,
      at: date
    )
  }

  public func latest() -> ANEMLLStreamingTelemetrySnapshot? {
    lock.lock()
    defer { lock.unlock() }
    return snapshot
  }

  public func clear() {
    lock.lock()
    snapshot = nil
    lock.unlock()
  }

  private func finish(
    streamID: UUID,
    state: ANEMLLStreamingState,
    metrics: ANEMLLRuntimeMetrics?,
    activeTurns: Int,
    at date: Date
  ) {
    lock.lock()
    defer { lock.unlock() }
    guard let current = snapshot,
      current.streamID == streamID,
      current.state == .streaming
    else {
      return
    }
    snapshot = ANEMLLStreamingTelemetrySnapshot(
      streamID: current.streamID,
      startedAt: current.startedAt,
      firstDeltaAt: current.firstDeltaAt,
      finishedAt: date,
      chunkCount: current.chunkCount,
      characterCount: current.characterCount,
      state: state,
      activeTurns: activeTurns,
      metrics: metrics
    )
  }
}
