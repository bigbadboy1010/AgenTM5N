import Foundation

public struct CoreMLExecutionTelemetrySnapshot: Equatable, Sendable {
  public let compiledPath: String
  public let mode: CoreMLComputeMode
  public let source: CoreMLExecutionRouteSource
  public let adaptiveRoutingApplied: Bool
  public let reason: String
  public let predictionMilliseconds: Double
  public let recordedAt: Date

  public init(
    compiledPath: String,
    mode: CoreMLComputeMode,
    source: CoreMLExecutionRouteSource,
    adaptiveRoutingApplied: Bool,
    reason: String,
    predictionMilliseconds: Double,
    recordedAt: Date = Date()
  ) {
    self.compiledPath = compiledPath
    self.mode = mode
    self.source = source
    self.adaptiveRoutingApplied = adaptiveRoutingApplied
    self.reason = reason
    self.predictionMilliseconds = predictionMilliseconds
    self.recordedAt = recordedAt
  }
}

/// Small thread-safe in-process monitor used by the Neural Engine UI and tools
/// to show which compute path actually executed the latest prediction.
public final class CoreMLAdaptiveExecutionTelemetry: @unchecked Sendable {
  public static let shared = CoreMLAdaptiveExecutionTelemetry()

  private let lock = NSLock()
  private var snapshots: [String: CoreMLExecutionTelemetrySnapshot] = [:]

  public init() {}

  public func record(_ snapshot: CoreMLExecutionTelemetrySnapshot) {
    lock.lock()
    snapshots[snapshot.compiledPath] = snapshot
    lock.unlock()
  }

  public func snapshot(compiledURL: URL) -> CoreMLExecutionTelemetrySnapshot? {
    let key = compiledURL.standardizedFileURL.path
    lock.lock()
    defer { lock.unlock() }
    return snapshots[key]
  }

  public func clear() {
    lock.lock()
    snapshots.removeAll(keepingCapacity: false)
    lock.unlock()
  }
}
