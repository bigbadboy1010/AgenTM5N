import AppKit
import Foundation
import UniformTypeIdentifiers

public enum GeneratedDocumentAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "document_generate",
      description: "Generate a DOCX, PDF, XLSX, or PPTX document and immediately present the native macOS Save dialog so the user can download/save the generated file. DOCX/PDF content accepts plain text with simple Markdown headings and bullets. XLSX content accepts TSV or CSV. PPTX content uses slides separated by a line containing only ---, with the first line of each slide used as its title. Internal managed storage paths are never exposed to the model.",
      parameters: objectSchema(
        required: ["format", "title", "content"],
        properties: [
          "format": stringSchema("Required output format: docx, pdf, xlsx, or pptx."),
          "title": stringSchema("Document title."),
          "filename": stringSchema("Optional suggested download file name. The required format extension is enforced automatically."),
          "content": stringSchema("Document content. DOCX/PDF: text or simple Markdown. XLSX: TSV or CSV. PPTX: slides separated by a line containing only ---."),
        ]
      )
    ),
    ProviderToolDefinition(
      name: "document_list_generated",
      description: "List locally generated AgenTM5N documents with stable IDs, file names, formats, sizes, and creation dates. Never returns managed storage paths.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "document_delete_generated",
      description: "Delete one managed generated document by exact document ID, file name, or title.",
      parameters: objectSchema(
        required: ["document"],
        properties: [
          "document": stringSchema("Exact generated-document ID, file name, or title.")
        ]
      )
    ),
  ] + PersistentAgentTools.definitions

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for call: ProviderToolCall) -> ToolRisk {
    if PersistentAgentTools.handles(call) {
      return PersistentAgentTools.risk(for: call)
    }
    switch call.function.name {
    case "document_list_generated":
      return .read
    case "document_generate", "document_delete_generated":
      return .write
    default:
      return .read
    }
  }

  public static func summary(for call: ProviderToolCall) -> String {
    if PersistentAgentTools.handles(call) {
      return PersistentAgentTools.summary(for: call)
    }
    let values = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      let description = value.compactDescription
      let bounded = description.count > 180 ? "\(description.prefix(180))…" : description
      return "\(key): \(bounded)"
    }
    return values.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(values.joined(separator: ", "))"
  }

  public static func execute(
    call: ProviderToolCall,
    service: GeneratedDocumentService = .shared
  ) async -> ToolExecutionResult {
    if PersistentAgentTools.handles(call) {
      return await PersistentAgentTools.execute(call: call)
    }

    do {
      switch call.function.name {
      case "document_generate":
        return try await generate(call: call, service: service)
      case "document_list_generated":
        return try await list(service: service)
      case "document_delete_generated":
        return try await delete(call: call, service: service)
      default:
        return ToolExecutionResult(
          success: false,
          output: "Unsupported generated-document tool: \(call.function.name)"
        )
      }
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private struct Descriptor: Encodable {
    let id: String
    let title: String
    let fileName: String
    let format: String
    let mediaType: String
    let byteCount: Int
    let createdAt: Date
  }

  private struct GenerateDescriptor: Encodable {
    let document: Descriptor
    let delivery: String
  }

  private struct DeleteDescriptor: Encodable {
    let deleted: Bool
    let id: String
    let fileName: String
  }

  private static func generate(
    call: ProviderToolCall,
    service: GeneratedDocumentService
  ) async throws -> ToolExecutionResult {
    let formatText = try requiredString("format", in: call).lowercased()
    guard let format = GeneratedDocumentFormat(rawValue: formatText) else {
      throw GeneratedDocumentError.unsupportedFormat(formatText)
    }
    let request = GeneratedDocumentRequest(
      format: format,
      title: try requiredString("title", in: call),
      fileName: optionalString("filename", in: call),
      content: try requiredString("content", in: call)
    )
    let summary = try await service.generate(request: request)

    let destination = await exportDestination(for: summary)
    let delivery: String
    if let destination {
      try await service.export(id: summary.id, to: destination)
      delivery = "saved"
    } else {
      delivery = "save-dialog-cancelled"
    }

    return encoded(
      GenerateDescriptor(
        document: descriptor(summary),
        delivery: delivery
      )
    )
  }

  private static func list(
    service: GeneratedDocumentService
  ) async throws -> ToolExecutionResult {
    let documents = try await service.list()
    return encoded(documents.map(descriptor))
  }

  private static func delete(
    call: ProviderToolCall,
    service: GeneratedDocumentService
  ) async throws -> ToolExecutionResult {
    let query = try requiredString("document", in: call)
    let summary = try await service.resolve(query)
    try await service.delete(id: summary.id)
    return encoded(
      DeleteDescriptor(
        deleted: true,
        id: summary.id.uuidString,
        fileName: summary.fileName
      )
    )
  }

  @MainActor
  private static func exportDestination(
    for summary: GeneratedDocumentSummary
  ) -> URL? {
    let panel = NSSavePanel()
    panel.title = L10n.text(
      de: "Generiertes Dokument speichern",
      en: "Save Generated Document",
      fr: "Enregistrer le document généré"
    )
    panel.prompt = L10n.text(de: "Speichern", en: "Save", fr: "Enregistrer")
    panel.nameFieldStringValue = summary.fileName
    panel.canCreateDirectories = true
    if let type = UTType(filenameExtension: summary.format.fileExtension) {
      panel.allowedContentTypes = [type]
    }
    return panel.runModal() == .OK ? panel.url : nil
  }

  private static func descriptor(_ summary: GeneratedDocumentSummary) -> Descriptor {
    Descriptor(
      id: summary.id.uuidString,
      title: summary.title,
      fileName: summary.fileName,
      format: summary.format.rawValue,
      mediaType: summary.format.mediaType,
      byteCount: summary.byteCount,
      createdAt: summary.createdAt
    )
  }

  private static func requiredString(
    _ name: String,
    in call: ProviderToolCall
  ) throws -> String {
    guard let value = optionalString(name, in: call) else {
      throw AgentRuntimeError.missingArgument(tool: call.function.name, name: name)
    }
    return value
  }

  private static func optionalString(
    _ name: String,
    in call: ProviderToolCall
  ) -> String? {
    guard let value = call.function.arguments[name]?.stringValue else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func encoded<T: Encodable>(_ value: T) -> ToolExecutionResult {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(value)
      return ToolExecutionResult(
        success: true,
        output: String(decoding: data, as: UTF8.self)
      )
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private static func objectSchema(
    required: [String] = [],
    properties: [String: JSONValue]
  ) -> JSONValue {
    var schema: [String: JSONValue] = [
      "type": .string("object"),
      "properties": .object(properties),
      "additionalProperties": .bool(false),
    ]
    if !required.isEmpty {
      schema["required"] = .array(required.map(JSONValue.string))
    }
    return .object(schema)
  }

  private static func stringSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("string"),
      "description": .string(description),
    ])
  }
}
