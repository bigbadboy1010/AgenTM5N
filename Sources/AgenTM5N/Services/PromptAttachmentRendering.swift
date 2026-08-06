import Foundation

@MainActor
public extension PromptAttachmentService {
  static func visiblePrompt(from storedContent: String) -> String {
    guard let expression = attachmentExpression else { return storedContent }
    let range = NSRange(storedContent.startIndex..<storedContent.endIndex, in: storedContent)
    let stripped = expression.stringByReplacingMatches(
      in: storedContent,
      range: range,
      withTemplate: ""
    )
    return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func attachmentNames(from storedContent: String) -> [String] {
    guard let expression = attachmentExpression else { return [] }
    let range = NSRange(storedContent.startIndex..<storedContent.endIndex, in: storedContent)
    return expression.matches(in: storedContent, range: range).compactMap { match in
      guard match.numberOfRanges > 1,
        let nameRange = Range(match.range(at: 1), in: storedContent)
      else {
        return nil
      }
      return unescapedAttribute(String(storedContent[nameRange]))
    }
  }

  private static var attachmentExpression: NSRegularExpression? {
    try? NSRegularExpression(
      pattern: #"<agentm5n_attachment\b[^>]*name="([^"]*)"[^>]*>[\s\S]*?</agentm5n_attachment>"#,
      options: []
    )
  }

  private static func unescapedAttribute(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&amp;", with: "&")
  }
}
