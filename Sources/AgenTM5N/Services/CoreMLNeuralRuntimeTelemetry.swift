import Foundation

public struct CoreMLNeuralRuntimeEvent: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let workload: CoreMLNeuralWorkloadKind
  public let compiledPath: String
  public let mode: CoreMLComputeMode
  public let source: CoreMLExecutionRouteSource
  public let itemCount: Int
  public let expectedPredictions: Int?
  public let durationMilliseconds: Double
  public let fallbackUsed: Bool
  public let reason: String
  public let recordedAt: Date

  public init(
    id: UUID = UUID(),
    workload: CoreMLNeuralWorkloadKind,
    compiledPath: String,
    mode: CoreMLComputeMode,
    source: CoreMLExecutionRouteSource,
    itemCount: Int,
    expectedPredictions: Int?,
    durationMilliseconds: Double,
    fallbackUsed: Bool,
    reason: String,
    recordedAt: Date = Date()
  ) {
    self.id = id
    self.workload = workload
    self.compiledPath = compiledPath
    self.mode = mode
    self.source = source
    self.itemCount = max(1, itemCount)
    self.expectedPredictions = expectedPredictions
    self.durationMilliseconds = max(0, durationMilliseconds)
    self.fallbackUsed = fallbackUsed
    self.reason = reason
    self.recordedAt = recordedAt
  }
}

/// Thread-safe in-process telemetry for real Build-35 workload execution.
/// This deliberately records routing and end-to-end workload latency, not NPU
/// utilization. The bounded history is intended for diagnostics, not profiling
/// persistence or user-content storage.
public final class CoreMLNeuralRuntimeTelemetry: @unchecked Sendable {
  public static let shared = CoreMLNeuralRuntimeTelemetry()

  private let lock = NSLock()
  private var events: [CoreMLNeuralRuntimeEvent] = []
  private let maximumEvents = 100

  public init() {}

  public func record(_ event: CoreMLNeuralRuntimeEvent) {
    lock.lock()
    events.append(event)
    if events.count > maximumEvents {
      events.removeFirst(events.count - maximumEvents)
    }
    lock.unlock()
  }

  public func recent(limit: Int = 20) -> [CoreMLNeuralRuntimeEvent] {
    let bounded = max(1, min(limit, maximumEvents))
    lock.lock()
    defer { lock.unlock() }
    return Array(events.suffix(bounded).reversed())
  }

  public func latest(
    compiledURL: URL,
    workload: CoreMLNeuralWorkloadKind? = nil
  ) -> CoreMLNeuralRuntimeEvent? {
    let path = compiledURL.standardizedFileURL.path
    lock.lock()
    defer { lock.unlock() }
    return events.reversed().first { event in
      event.compiledPath == path
        && (workload == nil || event.workload == workload)
    }
  }

  public func clear() {
    lock.lock()
    events.removeAll(keepingCapacity: false)
    lock.unlock()
  }
}
