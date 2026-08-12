import Foundation

public actor ToolStagnationGuard {
  public static let shared = ToolStagnationGuard()

  private struct Observation: Sendable {
    let signature: String
    var count: Int
    var lastSeenAt: Date
  }

  private var observation: Observation?
  private let resetInterval: TimeInterval = 120

  public init() {}

  public func blockReason(
    for call: ProviderToolCall,
    configuration: AgentOperatingLayerConfiguration = AgentOperatingLayerStore.load(),
    now: Date = Date()
  ) -> String? {
    guard configuration.stagnationGuardEnabled else {
      observation = nil
      return nil
    }

    let signature = Self.signature(for: call)
    guard var current = observation,
      current.signature == signature,
      now.timeIntervalSince(current.lastSeenAt) <= resetInterval
    else {
      observation = Observation(signature: signature, count: 1, lastSeenAt: now)
      return nil
    }

    current.count += 1
    current.lastSeenAt = now
    observation = current

    guard current.count > configuration.maxIdenticalToolRounds else {
      return nil
    }

    return """
      STAGNATION_GUARD_TRIGGERED: Der identische Tool-Aufruf `\(call.function.name)` wurde innerhalb von \(Int(resetInterval)) Sekunden bereits \(configuration.maxIdenticalToolRounds) Mal zugelassen. Dieser erneute Aufruf wurde nicht ausgeführt. Wiederhole ihn nicht unverändert. Bewerte die vorhandenen Ergebnisse, ändere die Strategie oder liefere die bestmögliche Antwort.
      """
  }

  public func reset() {
    observation = nil
  }

  private static func signature(for call: ProviderToolCall) -> String {
    let arguments = call.function.arguments.keys.sorted().map { key in
      "\(key)=\(call.function.arguments[key]?.compactDescription ?? "null")"
    }.joined(separator: "&")
    return "\(call.function.name)|\(arguments)"
  }
}
