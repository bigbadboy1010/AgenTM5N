import Foundation

public enum GenerationPhase: Equatable, Sendable {
  case idle
  case running(turnID: UUID)
  case cancelling(turnID: UUID)
  case cleaningUp(turnID: UUID)

  public var turnID: UUID? {
    switch self {
    case .idle:
      nil
    case .running(let turnID), .cancelling(let turnID), .cleaningUp(let turnID):
      turnID
    }
  }

  public var isActive: Bool {
    self != .idle
  }

  public var acceptsNewTurn: Bool {
    self == .idle
  }
}
