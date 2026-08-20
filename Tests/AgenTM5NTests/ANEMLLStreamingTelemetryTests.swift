import Foundation
import XCTest
@testable import AgenTM5N

final class ANEMLLStreamingTelemetryTests: XCTestCase {
  func testStreamingTelemetryTracksFirstDeltaCountsAndCompletion() {
    let telemetry = ANEMLLStreamingTelemetry()
    let started = Date(timeIntervalSince1970: 1_000)
    let streamID = telemetry.begin(at: started)

    telemetry.recordDelta(
      streamID: streamID,
      characterCount: 12,
      at: started.addingTimeInterval(0.025)
    )
    telemetry.recordDelta(
      streamID: streamID,
      characterCount: 8,
      at: started.addingTimeInterval(0.040)
    )

    let metrics = ANEMLLRuntimeMetrics(
      modelLoadSeconds: 1.5,
      timeToFirstTokenMilliseconds: 21,
      prefillTokensPerSecond: 1_900,
      inferenceTokensPerSecond: 84,
      generatedTokens: 10,
      totalTokens: 30,
      stopReason: "eos",
      wallMilliseconds: 150
    )
    telemetry.complete(
      streamID: streamID,
      metrics: metrics,
      activeTurns: 2,
      at: started.addingTimeInterval(0.150)
    )

    let snapshot = telemetry.latest()
    XCTAssertEqual(snapshot?.state, .completed)
    XCTAssertEqual(snapshot?.chunkCount, 2)
    XCTAssertEqual(snapshot?.characterCount, 20)
    XCTAssertEqual(snapshot?.activeTurns, 2)
    XCTAssertEqual(snapshot?.firstDeltaLatencyMilliseconds ?? 0, 25, accuracy: 0.001)
    XCTAssertEqual(snapshot?.wallMilliseconds ?? 0, 150, accuracy: 0.001)
    XCTAssertEqual(snapshot?.metrics?.generatedTokens, 10)
  }

  func testStreamingTelemetryIgnoresStaleStreamUpdates() {
    let telemetry = ANEMLLStreamingTelemetry()
    let staleID = telemetry.begin()
    let activeID = telemetry.begin()

    telemetry.recordDelta(streamID: staleID, characterCount: 100)
    telemetry.recordDelta(streamID: activeID, characterCount: 5)

    XCTAssertEqual(telemetry.latest()?.streamID, activeID)
    XCTAssertEqual(telemetry.latest()?.chunkCount, 1)
    XCTAssertEqual(telemetry.latest()?.characterCount, 5)
  }

  func testStreamingTelemetryRecordsCancellationWithoutContent() {
    let telemetry = ANEMLLStreamingTelemetry()
    let streamID = telemetry.begin()
    telemetry.recordDelta(streamID: streamID, characterCount: 4)
    telemetry.cancel(streamID: streamID, activeTurns: 0)

    let snapshot = telemetry.latest()
    XCTAssertEqual(snapshot?.state, .cancelled)
    XCTAssertEqual(snapshot?.characterCount, 4)
    XCTAssertNil(snapshot?.metrics)
  }

  func testStreamingTelemetryClearRemovesSnapshot() {
    let telemetry = ANEMLLStreamingTelemetry()
    _ = telemetry.begin()
    XCTAssertNotNil(telemetry.latest())
    telemetry.clear()
    XCTAssertNil(telemetry.latest())
  }
}
