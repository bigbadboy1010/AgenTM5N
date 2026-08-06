import AppKit
import Foundation
import PDFKit

public enum PromptAttachmentError: LocalizedError {
  case tooManyFiles(Int)
  case fileTooLarge(String, Int)
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
  private static let maximumFiles = 8
  private static let maximumFileBytes = 2 * 1024 * 1024
  private static let maximumExtractedCharacters = 180_000
  private static let textExtensions: Set<String> = [
    "txt", "md", "markdown", "swift", "m", "mm", "h", "c", "cc", "cpp",
    "py", "js", "ts", "tsx", "jsx", "java", "kt", "kts", "go", "rs",
    "sh", "bash", "zsh", "fish", "ps1", "sql", "html", "htm", "css",
    "scss", "json", "jsonl", "yaml", "yml", "xml", "plist", "toml",
    "ini", "conf", "config", "env", "properties", "csv", "tsv", "log",
    "dockerfile", "gitignore"
  ]

  public static func selectPromptFiles() throws -> String? {
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
    guard panel.urls.count <= maximumFiles else {
      throw PromptAttachmentError.tooManyFiles(maximumFiles)
    }

    var sections: [String] = []
    for url in panel.urls {
      let accessed = url.startAccessingSecurityScopedResource()
      defer {
        if accessed { url.stopAccessingSecurityScopedResource() }
      }
      sections.append(try promptSection(for: url))
    }

    return sections.joined(separator: "\n\n")
  }

  private static func promptSection(for url: URL) throws -> String {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else {
      throw PromptAttachmentError.unsupportedFile(url.lastPathComponent)
    }
    let byteCount = values.fileSize ?? 0
    guard byteCount <= maximumFileBytes else {
      throw PromptAttachmentError.fileTooLarge(url.lastPathComponent, maximumFileBytes)
    }

    let extensionName = url.pathExtension.lowercased()
    let text: String
    if extensionName == "pdf" {
      guard let document = PDFDocument(url: url) else {
        throw PromptAttachmentError.unreadableFile(url.lastPathComponent)
      }
      text = (0..<document.pageCount)
        .compactMap { document.page(at: $0)?.string }
        .joined(separator: "\n\n")
    } else if textExtensions.contains(extensionName)
      || textExtensions.contains(url.lastPathComponent.lowercased())
    {
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      guard let decoded = String(data: data, encoding: .utf8) else {
        throw PromptAttachmentError.unreadableFile(url.lastPathComponent)
      }
      text = decoded
    } else {
      throw PromptAttachmentError.unsupportedFile(url.lastPathComponent)
    }

    let limited = text.count > maximumExtractedCharacters
      ? String(text.prefix(maximumExtractedCharacters)) + "\n… [gekürzt]"
      : text
    return """
      <agentm5n_attachment name="\(escapedAttribute(url.lastPathComponent))" bytes="\(byteCount)">
      \(limited)
      </agentm5n_attachment>
      """
  }

  private static func escapedAttribute(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }
}
