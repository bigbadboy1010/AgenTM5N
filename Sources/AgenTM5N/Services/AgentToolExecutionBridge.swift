import Foundation

public actor AgentToolExecutionBridge {
  public typealias Executor = @Sendable (ProviderToolCall) async -> String

  public static let shared = AgentToolExecutionBridge()

  private var sessionID: UUID?
  private var executor: Executor?

  public init() {}

  public func install(
    sessionID: UUID,
    executor: @escaping Executor
  ) {
    self.sessionID = sessionID
    self.executor = executor
  }

  public func clear(sessionID: UUID) {
    guard self.sessionID == sessionID else { return }
    self.sessionID = nil
    executor = nil
  }

  public func execute(_ call: ProviderToolCall) async -> String {
    guard let executor else {
      return "TOOL_ERROR: AgenTM5N provider-neutral tool router is not active."
    }
    return await executor(call)
  }
}
