import Foundation
import SwiftUI

public struct ToolTelemetryEntry: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public let startedAt: Date
  public let endedAt: Date
  public let toolName: String
  public let capability: String
  public let provider: String
  public let risk: ToolRisk
  public let success: Bool
  public let durationMilliseconds: Double
  public let outputBytes: Int
  public let cacheHit: Bool

  public init(
    id: UUID = UUID(),
    startedAt: Date,
    endedAt: Date,
    toolName: String,
    capability: String,
    provider: String,
    risk: ToolRisk,
    success: Bool,
    durationMilliseconds: Double,
    outputBytes: Int,
    cacheHit: Bool
  ) {
    self.id = id
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.toolName = toolName
    self.capability = capability
    self.provider = provider
    self.risk = risk
    self.success = success
    self.durationMilliseconds = durationMilliseconds
    self.outputBytes = outputBytes
    self.cacheHit = cacheHit
  }
}

public struct ToolTelemetrySummary: Equatable, Sendable {
  public let total: Int
  public let succeeded: Int
  public let failed: Int
  public let cacheHits: Int
  public let averageMilliseconds: Double
}

@MainActor
public final class ToolTelemetryStore: ObservableObject {
  public static let shared = ToolTelemetryStore()
  public static let maximumEntries = 1_000

  @Published public private(set) var entries: [ToolTelemetryEntry] = []
  private let fileURL: URL

  public init(fileURL: URL? = nil) {
    self.fileURL = fileURL
      ?? AppPaths.applicationSupportDirectory.appendingPathComponent("tool-telemetry.json")
    load()
  }

  public var summary: ToolTelemetrySummary {
    let succeeded = entries.filter(\.success).count
    let failed = entries.count - succeeded
    let hits = entries.filter(\.cacheHit).count
    let average = entries.isEmpty
      ? 0
      : entries.map(\.durationMilliseconds).reduce(0, +) / Double(entries.count)
    return ToolTelemetrySummary(
      total: entries.count,
      succeeded: succeeded,
      failed: failed,
      cacheHits: hits,
      averageMilliseconds: average
    )
  }

  public func record(_ entry: ToolTelemetryEntry) {
    entries.insert(entry, at: 0)
    if entries.count > Self.maximumEntries {
      entries.removeLast(entries.count - Self.maximumEntries)
    }
    save()
  }

  public func clear() {
    entries = []
    try? FileManager.default.removeItem(at: fileURL)
  }

  private func load() {
    do {
      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        entries = []
        return
      }
      let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      entries = Array(
        try decoder.decode([ToolTelemetryEntry].self, from: data)
          .prefix(Self.maximumEntries)
      )
    } catch {
      entries = []
      AppLogger.app.error(
        "Tool telemetry load failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func save() {
    do {
      try AppPaths.ensureDirectories()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      try encoder.encode(entries).write(to: fileURL, options: [.atomic])
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: fileURL.path
      )
    } catch {
      AppLogger.app.error(
        "Tool telemetry save failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}
