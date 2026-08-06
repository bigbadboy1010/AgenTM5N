import AppKit
import Foundation
import PDFKit

public enum PromptAttachmentError: LocalizedError {
  case tooManyFiles(Int)
  case fileTooLarge(String, Int)
  case totalContentTooLarge(Int)
  case unsupportedFile(String)
  case unreadableFile(String)

  public var errorDescription: String? {
    switch self {
    case .tooManyFiles(let limit):
      return L10n.text(
        de: "Pro Prompt können höchstens \(limit) Dateien importiert werden.",
        en: "A prompt can import at most \(limit) files.",
        fr: "Une invite peut importer au maximum \(limit) fichiers."
      )
    case .fileTooLarge(let name, let limit):
      return L10n.text(
        de: "Die Datei \(name) überschreitet das Limit von \(limit) Bytes.",
        en: "File \(name) exceeds the \(limit)-byte limit.",
        fr: "Le fichier \(name) dépasse la limite de \(limit) octets."
      )
    case .totalContentTooLarge(let limit):
      return L10n.text(
        de: "Der extrahierte Inhalt aller Anhänge überschreitet das Gesamtlimit von \(limit) Zeichen.",
        en: "The extracted content of all attachments exceeds the total limit of \(limit) characters.",
        fr: "Le contenu extrait de toutes les pièces jointes dépasse la limite totale de \(limit) caractères."
      )
    case .unsupportedFile(let name):
      return L10n.text(
        de: "Die Datei \(name) kann in diesem Build nicht als Prompt-Inhalt gelesen werden. Unterstützt werden Text-, Quellcode-, Konfigurations-, Log-, CSV-, JSON-, XML-, YAML-, Markdown- und PDF-Dateien.",
        en: "File \(name) cannot be read as prompt content in this build. Text, source, configuration, log, CSV, JSON, XML, YAML, Markdown, and PDF files are supported.",
        fr: "Le fichier \(name) ne peut pas être lu comme contenu d’invite dans cette version. Les fichiers texte, source, configuration, journal, CSV, JSON, XML, YAML, Markdown et PDF sont pris en charge."
      )
    case .unreadableFile(let name):
      return L10n.text(
        de: "Die Datei \(name) konnte nicht gelesen werden.",
        en: "File \(name) could not be read.",
        fr: "Le fichier \(name) n’a pas pu être lu."
      )
    }
  }
}

@MainActor
public enum PromptAttachmentService {
  public static let maximumFiles = 8
  public static let maximumFileBytes = 2 * 1024 * 1024
  public static let maximumExtractedCharactersPerFile = 48_000
  public static let maximumTotalExtractedCharacters = 120_000

  private static let textExtensions: Set<String> = [
    "txt", "md", "markdown", "swift", "m", "mm", "h", "c", "cc", "cpp",
    "py", "js", "ts", "tsx", "jsx", "java", "kt", "kts", "go", "rs",
    "sh", "bash", "zsh", "fish", "ps1", "sql", "html", "htm", "css",
    "scss", "json", "jsonl", "yaml", "yml", "xml", "plist", "toml",
    "ini", "conf", "config", "env", "properties", "csv", "tsv", "log",
    "dockerfile", ".gitignore", "gitignore"
  ]

  public static func selectPromptFiles(
    existingCount: Int = 0,
    existingCharacterCount: Int = 0
  ) throws -> [PromptAttachment]? {
    let panel = NSOpenPanel()
    panel.title = L10n.text(
      de: "Dateien zum Prompt hinzufügen",
      en: "Add Files to Prompt",
      fr: "Ajouter des fichiers à l’invite"
    )
    panel.prompt = L10n.text(de: "Hinzufügen", en: "Add", fr: "Ajouter")
    panel.message = L10n.text(
      de: "Text-, Code-, Konfigurations-, Log-, CSV-, JSON-, YAML-, XML-, Markdown- oder PDF-Dateien auswählen.",
      en: "Select text, code, configuration, log, CSV, JSON, YAML, XML, Markdown, or PDF files.",
      fr: "Sélectionnez des fichiers texte, code, configuration, journal, CSV, JSON, YAML, XML, Markdown ou PDF."
    )
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.resolvesAliases = true

    guard panel.runModal() == .OK else { return nil }
    guard existingCount + panel.urls.count <= maximumFiles else {
      throw PromptAttachmentError.tooManyFiles(maximumFiles)
    }

    var attachments: [PromptAttachment] = []
    var totalCharacterCount = existingCharacterCount
    for url in panel.urls {
      let accessed = url.startAccessingSecurityScopedResource()
      defer {
        if accessed { url.stopAccessingSecurityScopedResource() }
      }
      let attachment = try attachment(for: url)
      totalCharacterCount += attachment.extractedText.count
      guard totalCharacterCount <= maximumTotalExtractedCharacters else {
        throw PromptAttachmentError.totalContentTooLarge(
          maximumTotalExtractedCharacters
        )
      }
      attachments.append(attachment)
    }

    return attachments
  }

  public static func providerContent(
    prompt: String,
    attachments: [PromptAttachment]
  ) -> String {
    guard !attachments.isEmpty else { return prompt }
    let sections = attachments.map { attachment in
      """
      <agentm5n_attachment name="\(escapedAttribute(attachment.name))" media_type="\(escapedAttribute(attachment.mediaType))" bytes="\(attachment.byteCount)" truncated="\(attachment.wasTruncated)">
      \(attachment.extractedText)
      </agentm5n_attachment>
      """
    }
    if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return sections.joined(separator: "\n\n")
    }
    return prompt + "\n\n" + sections.joined(separator: "\n\n")
  }

  private static func attachment(for url: URL) throws -> PromptAttachment {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else {
      throw PromptAttachmentError.unsupportedFile(url.lastPathComponent)
    }
    let byteCount = values.fileSize ?? 0
    guard byteCount <= maximumFileBytes else {
      throw PromptAttachmentError.fileTooLarge(url.lastPathComponent, maximumFileBytes)
    }

    let extensionName = url.pathExtension.lowercased()
    let rawText: String
    let mediaType: String
    if extensionName == "pdf" {
      guard let document = PDFDocument(url: url) else {
        throw PromptAttachmentError.unreadableFile(url.lastPathComponent)
      }
      rawText = (0..<document.pageCount)
        .compactMap { document.page(at: $0)?.string }
        .joined(separator: "\n\n")
      mediaType = "application/pdf"
    } else if textExtensions.contains(extensionName)
      || textExtensions.contains(url.lastPathComponent.lowercased())
    {
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      guard let decoded = String(data: data, encoding: .utf8) else {
        throw PromptAttachmentError.unreadableFile(url.lastPathComponent)
      }
      rawText = decoded
      mediaType = inferredTextMediaType(extensionName)
    } else {
      throw PromptAttachmentError.unsupportedFile(url.lastPathComponent)
    }

    let wasTruncated = rawText.count > maximumExtractedCharactersPerFile
    let extractedText = wasTruncated
      ? String(rawText.prefix(maximumExtractedCharactersPerFile))
        + "\n… [AgenTM5N: Inhalt gekürzt]"
      : rawText

    return PromptAttachment(
      name: url.lastPathComponent,
      byteCount: byteCount,
      mediaType: mediaType,
      extractedText: extractedText,
      wasTruncated: wasTruncated
    )
  }

  private static func inferredTextMediaType(_ extensionName: String) -> String {
    switch extensionName {
    case "json", "jsonl": "application/json"
    case "xml", "plist": "application/xml"
    case "yaml", "yml": "application/yaml"
    case "csv": "text/csv"
    case "tsv": "text/tab-separated-values"
    case "md", "markdown": "text/markdown"
    default: "text/plain"
    }
  }

  private static func escapedAttribute(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }
}
