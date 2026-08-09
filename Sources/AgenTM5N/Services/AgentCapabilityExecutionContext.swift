import Foundation

/// Task-local capability scope used while a persistent specialist executes.
///
/// Nil means the main agent/full inherited catalog. A non-nil set is an
/// explicit sandbox and is enforced both when provider tool definitions are
/// selected and again immediately before native execution.
public enum AgentCapabilityExecutionContext {
  @TaskLocal public static var allowedCapabilities: Set<AgentToolCapability>?

  /// Computes the capability scope for a delegated child without allowing a
  /// child profile to expand an already restricted parent specialist.
  public static func delegatedScope(
    parent: Set<AgentToolCapability>?,
    profile: Set<AgentToolCapability>?
  ) -> Set<AgentToolCapability>? {
    switch (parent, profile) {
    case (nil, nil):
      return nil
    case (let parent?, nil):
      return parent
    case (nil, let profile?):
      return profile
    case (let parent?, let profile?):
      return parent.intersection(profile)
    }
  }
}
