import Foundation

public enum AgentDelegationContext {
  @TaskLocal public static var depth: Int = 0
  public static let maximumDepth = 2
}
