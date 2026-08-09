import Foundation

/// Fail-closed replacement policy for persistent Toolsmith records.
///
/// `SelfBuiltToolLibrary.createOrReplace` predates enable/disable support and
/// historically re-enabled an existing record as a side effect of replacement.
/// AgenTM5N now blocks replacement of a disabled tool at the central execution
/// boundary. The user must explicitly enable it first, making the state change
/// visible and separately approvable.
public enum SelfBuiltToolReplacementPolicy {
  public static func denial(
    for call: ProviderToolCall,
    library: SelfBuiltToolLibrary = .shared
  ) -> ToolExecutionResult? {
    guard call.function.name == "toolsmith_create",
      let requestedName = call.function.arguments["name"]?.stringValue,
      let normalized = try? SelfBuiltToolAgentTools.normalizedToolName(requestedName),
      let existing = try? library.resolve(normalized),
      !existing.isEnabled
    else {
      return nil
    }

    return ToolExecutionResult(
      success: false,
      output: "TOOL_DISABLED: \(existing.name) ist deaktiviert und wird durch Ersetzen nicht automatisch reaktiviert. Aktiviere das Tool zuerst ausdrücklich mit toolsmith_set_enabled und führe danach toolsmith_create erneut aus."
    )
  }
}