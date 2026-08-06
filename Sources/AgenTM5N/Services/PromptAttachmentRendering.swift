import Foundation

public extension PromptAttachmentService {
  nonisolated static func visiblePrompt(from storedContent: String) -> String {
    var stripped = storedContent
    if let expression = textAttachmentExpression {
      let range = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
      stripped = expression.stringByReplacingMatches(
        in: stripped,
        range: range,
        withTemplate: ""
      )
    }
    if let expression = imageAttachmentExpression {
      let range = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
      stripped = expression.stringByReplacingMatches(
        in: stripped,
        range: range,
        withTemplate: ""
      )
    }
    return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  nonisolated static func attachmentNames(from storedContent: String) -> [String] {
    textAttachmentNames(from: storedContent)
      + imageReferences(from: storedContent).map(\.name)
  }

  nonisolated static func textAttachmentNames(from storedContent: String) -> [String] {
    guard let expression = textAttachmentExpression else { return [] }
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

  nonisolated static func imageReferences(
    from storedContent: String
  ) -> [PromptImageReference] {
    guard let expression = imageAttachmentExpression else { return [] }
    let range = NSRange(storedContent.startIndex..<storedContent.endIndex, in: storedContent)
    return expression.matches(in: storedContent, range: range).compactMap { match in
      guard match.numberOfRanges == 8,
        let idRange = Range(match.range(at: 1), in: storedContent),
        let nameRange = Range(match.range(at: 2), in: storedContent),
        let mediaTypeRange = Range(match.range(at: 3), in: storedContent),
        let byteCountRange = Range(match.range(at: 4), in: storedContent),
        let pathRange = Range(match.range(at: 5), in: storedContent),
        let widthRange = Range(match.range(at: 6), in: storedContent),
        let heightRange = Range(match.range(at: 7), in: storedContent),
        let id = UUID(uuidString: String(storedContent[idRange])),
        let byteCount = Int(String(storedContent[byteCountRange])),
        let pixelWidth = Int(String(storedContent[widthRange])),
        let pixelHeight = Int(String(storedContent[heightRange]))
      else {
        return nil
      }

      return PromptImageReference(
        id: id,
        name: unescapedAttribute(String(storedContent[nameRange])),
        mediaType: unescapedAttribute(String(storedContent[mediaTypeRange])),
        byteCount: byteCount,
        relativePath: unescapedAttribute(String(storedContent[pathRange])),
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight
      )
    }
  }

  nonisolated static func hasImageAttachments(in storedContent: String) -> Bool {
    guard let expression = imageAttachmentExpression else { return false }
    let range = NSRange(storedContent.startIndex..<storedContent.endIndex, in: storedContent)
    return expression.firstMatch(in: storedContent, range: range) != nil
  }

  nonisolated private static var textAttachmentExpression: NSRegularExpression? {
    try? NSRegularExpression(
      pattern: #"<agentm5n_attachment\b[^>]*name="([^"]*)"[^>]*>[\s\S]*?</agentm5n_attachment>"#,
      options: []
    )
  }

  nonisolated private static var imageAttachmentExpression: NSRegularExpression? {
    try? NSRegularExpression(
      pattern: #"<agentm5n_image_attachment\s+id="([^"]+)"\s+name="([^"]*)"\s+media_type="([^"]+)"\s+bytes="([0-9]+)"\s+path="([^"]+)"\s+width="([0-9]+)"\s+height="([0-9]+)"\s*/>"#,
      options: []
    )
  }

  nonisolated private static func unescapedAttribute(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&amp;", with: "&")
  }
}
