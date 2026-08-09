import Foundation
import FoundationModels

/// Focused Apple on-device clipboard reader used when the user explicitly asks
/// AgenTM5N to inspect the current macOS clipboard.
///
/// The provider combines this single tool with ToolCallingMode.required so the
/// system model cannot replace the native read with a generic privacy refusal.
public enum AppleRequiredClipboardTools {
  public static func makeReadTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [AppleRequiredClipboardReadTool(bridge: bridge)]
  }
}

private struct AppleRequiredClipboardReadTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "clipboard_read"
  let description = "Read the actual current plain-text contents of the macOS clipboard through AgenTM5N. The user explicitly requested this native clipboard read. Do not simulate or refuse it."

  @Generable
  struct Arguments {
    @Guide(description: "Use current clipboard")
    var query: String
  }

  func call(arguments: Arguments) async throws -> String {
    await bridge.execute(
      ProviderToolCall(
        function: .init(name: name, arguments: [:])
      )
    )
  }
}
