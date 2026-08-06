import Foundation

public enum ConversationAttachmentToolError: LocalizedError {
  case missingArgument(tool: String, name: String)
  case attachmentNotFound(String)
  case ambiguousAttachment(String, [String])
  case sectionNotFound(String)
  case emptyQuery

  public var errorDescription: String? {
    switch self {
    case .missingArgument(let tool, let name):
      return L10n.text(
        de: "Werkzeug \(tool) benötigt das Argument \(name).",
        en: "Tool \(tool) requires argument \(name).",
        fr: "L’outil \(tool) nécessite l’argument \(name)."
      )
    case .attachmentNotFound(let query):
      return L10n.text(
        de: "In der aktuellen Unterhaltung wurde kein Anhang gefunden, der zu „\(query)“ passt.",
        en: "No attachment matching “\(query)” was found in the current conversation.",
        fr: "Aucune pièce jointe correspondant à « \(query) » n’a été trouvée dans la conversation actuelle."
      )
    case .ambiguousAttachment(let query, let matches):
      return L10n.text(
        de: "Der Anhang „\(query)“ ist nicht eindeutig: \(matches.joined(separator: ", ")). Verwende die Anhangs-ID.",
        en: "Attachment “\(query)” is ambiguous: \(matches.joined(separator: ", ")). Use the attachment ID.",
        fr: "La pièce jointe « \(query) » est ambiguë : \(matches.joined(separator: ", ")). Utilisez son identifiant."
      )
    case .sectionNotFound(let section):
      return L10n.text(
        de: "Der Quellenabschnitt „\(section)“ wurde im Anhang nicht gefunden.",
        en: "Source section “\(section)” was not found in the attachment.",
        fr: "La section source « \(section) » est introuvable dans la pièce jointe."
      )
    case .emptyQuery:
      return L10n.text(
        de: "Die Suchabfrage darf nicht leer sein.",
        en: "The search query must not be empty.",
        fr: "La requête de recherche ne doit pas être vide."
      )
    }
  }
}

public enum ConversationAttachmentAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "attachment_list",
      description: "List files and images attached by the user in the current conversation. Returns stable attachment IDs and bounded metadata only; no binary data or internal paths.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "attachment_describe",
      description: "Describe one attachment from the current conversation by exact name or attachment ID, including type, size, extracted character count and available source locators.",
      parameters: objectSchema(
        required: ["attachment"],
        properties: [
          "attachment": stringSchema("Exact attachment name or attachment ID returned by attachment_list.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "attachment_search",
      description: "Search extracted text and OCR text in attachments from the current conversation. Returns ranked bounded excerpts with attachment IDs and source locators.",
      parameters: objectSchema(
        required: ["query"],
        properties: [
          "query": stringSchema("Literal or natural-language search terms."),
          "attachment": stringSchema("Optional exact attachment name or ID to restrict the search."),
          "limit": integerSchema("Optional result count from 1 to 20.", minimum: 1, maximum: 20)
        ]
      )
    ),
    ProviderToolDefinition(
      name: "attachment_read_section",
      description: "Read a bounded source section from one text, PDF, Word, Excel, PowerPoint or OCR attachment in the current conversation. Use attachment_describe first to discover locators.",
      parameters: objectSchema(
        required: ["attachment"],
        properties: [
          "attachment": stringSchema("Exact attachment name or attachment ID."),
          "section": stringSchema("Optional locator fragment such as 'Seite 3', 'Folie 7' or 'Blatt Azure, Zeilen 12-19'. Without it, returns the first bounded section."),
          "maximum_characters": integerSchema("Optional output limit from 500 to 12000 characters.", minimum: 500, maximum: 12_000)
        ]
      )
    )
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for _: ProviderToolCall) -> ToolRisk {
    .read
  }

  public static func summary(for call: ProviderToolCall) -> String {
    let values = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      let description = value.compactDescription
      return description.count > 180
        ? "\(key): \(description.prefix(180))…"
        : "\(key): \(description)"
    }
    return values.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(values.joined(separator: ", "))"
  }

  public static func execute(
    call: ProviderToolCall,
    messages: [ChatMessage]
  ) -> ToolExecutionResult {
    do {
      let catalog = parse(messages: messages)
      switch call.function.name {
      case "attachment_list":
        return encoded(catalog.map(AttachmentListDescriptor.init))
      case "attachment_describe":
        let query = try requiredString("attachment", in: call)
        let record = try resolve(query, in: catalog)
        return encoded(AttachmentDescriptionDescriptor(record))
      case "attachment_search":
        return try search(call: call, catalog: catalog)
      case "attachment_read_section":
        return try readSection(call: call, catalog: catalog)
      default:
        return ToolExecutionResult(
          success: false,
          output: "Unsupported attachment tool: \(call.function.name)"
        )
      }
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private struct Record: Sendable {
    let id: String
    let name: String
    let mediaType: String
    let byteCount: Int
    let kind: String
    let truncated: Bool
    let content: String
    let locators: [String]
    let pixelWidth: Int?
    let pixelHeight: Int?
  }

  private struct AttachmentListDescriptor: Encodable {
    let id: String
    let name: String
    let kind: String
    let mediaType: String
    let byteCount: Int
    let extractedCharacters: Int
    let sourceSectionCount: Int
    let truncated: Bool
    let dimensions: String?

    init(_ record: Record) {
      id = record.id
      name = record.name
      kind = record.kind
      mediaType = record.mediaType
      byteCount = record.byteCount
      extractedCharacters = record.content.count
      sourceSectionCount = record.locators.count
      truncated = record.truncated
      if let width = record.pixelWidth, let height = record.pixelHeight {
        dimensions = "\(width) × \(height)"
      } else {
        dimensions = nil
      }
    }
  }

  private struct AttachmentDescriptionDescriptor: Encodable {
    let id: String
    let name: String
    let kind: String
    let mediaType: String
    let byteCount: Int
    let extractedCharacters: Int
    let truncated: Bool
    let dimensions: String?
    let sourceLocators: [String]

    init(_ record: Record) {
      id = record.id
      name = record.name
      kind = record.kind
      mediaType = record.mediaType
      byteCount = record.byteCount
      extractedCharacters = record.content.count
      truncated = record.truncated
      if let width = record.pixelWidth, let height = record.pixelHeight {
        dimensions = "\(width) × \(height)"
      } else {
        dimensions = nil
      }
      sourceLocators = Array(record.locators.prefix(120))
    }
  }

  private struct AttachmentSearchDescriptor: Encodable {
    let attachmentID: String
    let name: String
    let locator: String?
    let score: Int
    let excerpt: String
  }

  private struct AttachmentSectionDescriptor: Encodable {
    let attachmentID: String
    let name: String
    let locator: String?
    let content: String
    let truncated: Bool
  }

  private static func parse(messages: [ChatMessage]) -> [Record] {
    var records: [Record] = []
    for message in messages where message.role == .user {
      let textRecords = parseTextAttachments(
        content: message.content,
        messageID: message.id
      )
      records.append(contentsOf: textRecords)

      for reference in PromptAttachmentService.imageReferences(from: message.content) {
        let id = "\(message.id.uuidString.lowercased()):image:\(reference.id.uuidString.lowercased())"
        if records.contains(where: { $0.id == id }) { continue }
        records.append(
          Record(
            id: id,
            name: reference.name,
            mediaType: reference.mediaType,
            byteCount: reference.byteCount,
            kind: "image",
            truncated: false,
            content: "",
            locators: [],
            pixelWidth: reference.pixelWidth,
            pixelHeight: reference.pixelHeight
          )
        )
      }
    }
    return records
  }

  private static func parseTextAttachments(
    content: String,
    messageID: UUID
  ) -> [Record] {
    guard let expression = try? NSRegularExpression(
      pattern: #"<agentm5n_attachment\s+name=\"([^\"]*)\"\s+media_type=\"([^\"]*)\"\s+bytes=\"([0-9]+)\"\s+truncated=\"(true|false)\">([\s\S]*?)</agentm5n_attachment>"#,
      options: []
    ) else {
      return []
    }

    let range = NSRange(content.startIndex..<content.endIndex, in: content)
    return expression.matches(in: content, range: range).enumerated().compactMap {
      index, match in
      guard match.numberOfRanges == 6,
        let nameRange = Range(match.range(at: 1), in: content),
        let mediaRange = Range(match.range(at: 2), in: content),
        let bytesRange = Range(match.range(at: 3), in: content),
        let truncatedRange = Range(match.range(at: 4), in: content),
        let bodyRange = Range(match.range(at: 5), in: content),
        let byteCount = Int(content[bytesRange])
      else {
        return nil
      }

      let body = String(content[bodyRange]).trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      return Record(
        id: "\(messageID.uuidString.lowercased()):text:\(index + 1)",
        name: unescape(String(content[nameRange])),
        mediaType: unescape(String(content[mediaRange])),
        byteCount: byteCount,
        kind: "document",
        truncated: String(content[truncatedRange]) == "true",
        content: body,
        locators: sourceLocators(in: body),
        pixelWidth: nil,
        pixelHeight: nil
      )
    }
  }

  private static func sourceLocators(in text: String) -> [String] {
    guard let expression = try? NSRegularExpression(
      pattern: #"(?m)^\[Datei:\s*([^\]]+)\]$"#,
      options: []
    ) else {
      return []
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return expression.matches(in: text, range: range).compactMap { match in
      guard match.numberOfRanges > 1,
        let locatorRange = Range(match.range(at: 1), in: text)
      else {
        return nil
      }
      return String(text[locatorRange])
    }
  }

  private static func search(
    call: ProviderToolCall,
    catalog: [Record]
  ) throws -> ToolExecutionResult {
    let query = try requiredString("query", in: call)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { throw ConversationAttachmentToolError.emptyQuery }
    let attachmentQuery = optionalString("attachment", in: call)
    let selected: [Record]
    if let attachmentQuery {
      selected = [try resolve(attachmentQuery, in: catalog)]
    } else {
      selected = catalog.filter { !$0.content.isEmpty }
    }
    let limit = max(1, min(optionalInt("limit", in: call) ?? 8, 20))
    let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)

    let matches = selected.compactMap { record -> AttachmentSearchDescriptor? in
      let lower = record.content.lowercased()
      let positions = terms.compactMap { lower.range(of: $0)?.lowerBound }
      guard !positions.isEmpty else { return nil }
      let score = terms.reduce(0) { partial, term in
        partial + lower.components(separatedBy: term).count - 1
      }
      let first = positions.min() ?? lower.startIndex
      let offset = lower.distance(from: lower.startIndex, to: first)
      let startOffset = max(0, offset - 260)
      let start = record.content.index(record.content.startIndex, offsetBy: startOffset)
      let end = record.content.index(
        start,
        offsetBy: min(900, record.content.distance(from: start, to: record.content.endIndex))
      )
      let excerpt = String(record.content[start..<end])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return AttachmentSearchDescriptor(
        attachmentID: record.id,
        name: record.name,
        locator: nearestLocator(before: offset, in: record.content),
        score: score,
        excerpt: excerpt
      )
    }
    .sorted { lhs, rhs in
      if lhs.score == rhs.score { return lhs.name < rhs.name }
      return lhs.score > rhs.score
    }

    return encoded(Array(matches.prefix(limit)))
  }

  private static func readSection(
    call: ProviderToolCall,
    catalog: [Record]
  ) throws -> ToolExecutionResult {
    let query = try requiredString("attachment", in: call)
    let record = try resolve(query, in: catalog)
    let sectionQuery = optionalString("section", in: call)
    let maximum = max(
      500,
      min(optionalInt("maximum_characters", in: call) ?? 6_000, 12_000)
    )
    guard !record.content.isEmpty else {
      return encoded(
        AttachmentSectionDescriptor(
          attachmentID: record.id,
          name: record.name,
          locator: nil,
          content: "No extracted text is available for this image attachment.",
          truncated: false
        )
      )
    }

    let selected: String
    let locator: String?
    if let sectionQuery {
      guard let range = record.content.range(
        of: sectionQuery,
        options: [.caseInsensitive, .diacriticInsensitive]
      ) else {
        throw ConversationAttachmentToolError.sectionNotFound(sectionQuery)
      }
      let start = record.content[..<range.lowerBound].lastIndex(of: "[")
        ?? record.content.startIndex
      let remainder = record.content[range.upperBound...]
      let next = remainder.range(of: "\n[Datei:")?.lowerBound
        ?? record.content.endIndex
      selected = String(record.content[start..<next])
      locator = sectionQuery
    } else {
      selected = record.content
      locator = record.locators.first
    }

    let bounded = selected.count > maximum
      ? String(selected.prefix(maximum)) + "\n…"
      : selected
    return encoded(
      AttachmentSectionDescriptor(
        attachmentID: record.id,
        name: record.name,
        locator: locator,
        content: bounded,
        truncated: selected.count > maximum
      )
    )
  }

  private static func resolve(_ query: String, in catalog: [Record]) throws -> Record {
    if let exactID = catalog.first(where: { $0.id == query }) {
      return exactID
    }
    let exactNames = catalog.filter {
      $0.name.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
    if exactNames.count == 1, let match = exactNames.first { return match }
    if exactNames.count > 1 {
      throw ConversationAttachmentToolError.ambiguousAttachment(
        query,
        exactNames.map { "\($0.name) [\($0.id)]" }
      )
    }
    throw ConversationAttachmentToolError.attachmentNotFound(query)
  }

  private static func nearestLocator(before offset: Int, in text: String) -> String? {
    let boundedOffset = min(max(offset, 0), text.count)
    let index = text.index(text.startIndex, offsetBy: boundedOffset)
    let prefix = String(text[..<index])
    return sourceLocators(in: prefix).last
  }

  private static func encoded<T: Encodable>(_ value: T) -> ToolExecutionResult {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(value)
      return ToolExecutionResult(
        success: true,
        output: String(decoding: data, as: UTF8.self)
      )
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private static func requiredString(
    _ name: String,
    in call: ProviderToolCall
  ) throws -> String {
    guard let value = optionalString(name, in: call), !value.isEmpty else {
      throw ConversationAttachmentToolError.missingArgument(
        tool: call.function.name,
        name: name
      )
    }
    return value
  }

  private static func optionalString(
    _ name: String,
    in call: ProviderToolCall
  ) -> String? {
    guard let value = call.function.arguments[name], case .string(let text) = value else {
      return nil
    }
    return text
  }

  private static func optionalInt(
    _ name: String,
    in call: ProviderToolCall
  ) -> Int? {
    guard let value = call.function.arguments[name], case .number(let number) = value else {
      return nil
    }
    return number.isFinite ? Int(number) : nil
  }

  private static func unescape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&amp;", with: "&")
  }

  private static func objectSchema(
    required: [String] = [],
    properties: [String: JSONValue]
  ) -> JSONValue {
    var schema: [String: JSONValue] = [
      "type": .string("object"),
      "properties": .object(properties),
      "additionalProperties": .bool(false)
    ]
    if !required.isEmpty {
      schema["required"] = .array(required.map(JSONValue.string))
    }
    return .object(schema)
  }

  private static func stringSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("string"),
      "description": .string(description)
    ])
  }

  private static func integerSchema(
    _ description: String,
    minimum: Int,
    maximum: Int
  ) -> JSONValue {
    .object([
      "type": .string("integer"),
      "description": .string(description),
      "minimum": .number(Double(minimum)),
      "maximum": .number(Double(maximum))
    ])
  }
}
