import Foundation
import FoundationModels

/// Focused Apple on-device document generation tool.
///
/// The tool deliberately ends the Foundation Models turn after the native
/// AgenTM5N document action has completed. On macOS 27 the provider combines
/// this with `ToolCallingMode.required`, guaranteeing that a document request
/// reaches the native tool instead of falling back to a generic chat refusal.
public enum AppleRequiredDocumentTools {
  public static let completionPrefix = "AGENTM5N_DOCUMENT_TOOL_COMPLETED:"
  public static let completionSuffix = ":END_AGENTM5N_DOCUMENT_TOOL"

  public static func makeTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [AppleRequiredDocumentGenerateTool(bridge: bridge)]
  }

  public static func completionOutput(from error: any Error) -> String? {
    var current: NSError? = error as NSError
    var remainingDepth = 6

    while let value = current, remainingDepth > 0 {
      if let output = decodeCompletion(in: value.localizedDescription) {
        return output
      }
      if let output = decodeCompletion(in: String(reflecting: value)) {
        return output
      }
      current = value.userInfo[NSUnderlyingErrorKey] as? NSError
      remainingDepth -= 1
    }

    return decodeCompletion(in: String(reflecting: error))
  }

  private static func decodeCompletion(in text: String) -> String? {
    guard let start = text.range(of: completionPrefix) else { return nil }
    let remainder = text[start.upperBound...]
    guard let end = remainder.range(of: completionSuffix) else { return nil }
    let payload = String(remainder[..<end.lowerBound])
    guard let data = Data(base64Encoded: payload) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

private struct AppleRequiredDocumentGenerateTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "document_generate"
  let description = "Create the actual requested DOCX, PDF, XLSX, or PPTX file through AgenTM5N. This is a real native file-generation capability, not a text-only simulation. Use it whenever the user asks to create, generate, export, save, or provide one of these document formats."

  @Generable
  struct Arguments {
    @Guide(description: "Required output format: docx, pdf, xlsx, or pptx")
    var format: String

    @Guide(description: "Document title requested by the user")
    var title: String

    @Guide(description: "Suggested filename without changing the requested file type; empty only when the user did not provide one")
    var filename: String

    @Guide(description: "Complete document content. Preserve all requested headings, paragraphs, bullets, rows, columns, or slides instead of merely describing them")
    var content: String
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "format": .string(arguments.format),
      "title": .string(arguments.title),
      "content": .string(arguments.content),
    ]
    if !arguments.filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      values["filename"] = .string(arguments.filename)
    }

    let output = await bridge.execute(
      ProviderToolCall(function: .init(name: name, arguments: values))
    )

    throw AppleRequiredDocumentTurnFinished(output: output)
  }
}

private struct AppleRequiredDocumentTurnFinished: LocalizedError {
  let output: String

  var errorDescription: String? {
    let payload = Data(output.utf8).base64EncodedString()
    return AppleRequiredDocumentTools.completionPrefix
      + payload
      + AppleRequiredDocumentTools.completionSuffix
  }
}
