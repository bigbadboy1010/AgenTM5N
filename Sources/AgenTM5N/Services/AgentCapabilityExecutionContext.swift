import Foundation

/// Task-local capability scope used while a persistent specialist executes.
///
/// Nil means the main agent/full inherited catalog. A non-nil set is an
/// explicit sandbox and is enforced both when provider tool definitions are
/// selected and again immediately before native execution.
public enum AgentCapabilityExecutionContext {
  @TaskLocal public static var allowedCapabilities: Set<AgentToolCapability>?
}
