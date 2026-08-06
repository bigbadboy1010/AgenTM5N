import Foundation
import FoundationModels

public enum AppleFoundationModelsProviderError: LocalizedError {
  case unavailable(String)

  public var errorDescription: String? {
    switch self {
    case .unavailable(let reason):
      "Apple Foundation Models ist nicht verfügbar: \(reason)"
    }
  }
}

public actor AppleFoundationModelsProvider {
  private let model = SystemLanguageModel.default

  public init() {}

  public func availabilityDescription() -> String {
    switch model.availability {
    case .available:
      return "Verfügbar"
    case .unavailable(let reason):
      return "Nicht verfügbar: \(String(describing: reason))"
    }
  }

  public func complete(
    configuration: AppConfiguration,
    messages: [ChatMessage]
  ) async throws -> ProviderStreamEvent {
    switch model.availability {
    case .available:
      break
    case .unavailable(let reason):
      throw AppleFoundationModelsProviderError.unavailable(String(describing: reason))
    }

    let instructions = configuration.systemPrompt
    let session = LanguageModelSession(model: model) {
      instructions
    }
    let prompt = Self.makePrompt(messages: messages)
    let clock = ContinuousClock()
    let startedAt = clock.now
    let response = try await session.respond(to: prompt)
    let duration = startedAt.duration(to: clock.now)
    let durationNanoseconds = Self.nanoseconds(from: duration)

    return ProviderStreamEvent(
      contentDelta: response.content,
      thinkingDelta: "",
      isFinished: true,
      metrics: ChatMetrics(totalDurationNanoseconds: durationNanoseconds)
    )
  }

  private static func makePrompt(messages: [ChatMessage]) -> String {
    messages
      .filter { $0.role != .system }
      .map { message in
        let role =
          switch message.role {
          case .system: "SYSTEM"
          case .user: "USER"
          case .assistant: "ASSISTANT"
          }
        return "\(role):\n\(message.content)"
      }
      .joined(separator: "\n\n")
  }

  private static func nanoseconds(from duration: Duration) -> UInt64 {
    let components = duration.components
    let seconds = max(components.seconds, 0)
    let attoseconds = max(components.attoseconds, 0)
    let secondsPart = UInt64(seconds) * 1_000_000_000
    let attosecondsPart = UInt64(attoseconds / 1_000_000_000)
    return secondsPart + attosecondsPart
  }
}
