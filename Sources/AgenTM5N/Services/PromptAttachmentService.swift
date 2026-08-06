import AppKit
import Foundation
import PDFKit

public enum PromptAttachmentError: LocalizedError {
  case tooManyFiles(Int)
  case tooManyImages(Int)
  case fileTooLarge(String, Int)
  case imageTooLarge(String, Int)
  case totalContentTooLarge(Int)
  case totalImagePayloadTooLarge(Int)
  case unsupportedFile(String)
  case unreadableFile(String)
  case invalidImage(String)
  case imageEncodingFailed(String)
  case imageProviderUnsupported
  case modelDoesNotSupportVision(String)

  public var errorDescription: String? {
    switch self {
    case .tooManyFiles(let limit):
      return L10n.text(
        de: "Pro Prompt können höchstens \(limit) Dateien importiert werden.",
        en: "A prompt can import at most \(limit) files.",
        fr: "Une invite peut importer au maximum \(limit) fichiers."
      )
    case .tooManyImages(let limit):
      return L10n.text(
        de: "Pro Prompt können höchstens \(limit) Bilder angehängt werden.",
        en: "A prompt can contain at most \(limit) images.",
        fr: "Une invite peut contenir au maximum \(limit) images."
      )
    case .fileTooLarge(let name, let limit):
      return L10n.text(
        de: "Die Datei \(name) überschreitet das Limit von \(limit) Bytes.",
        en: "File \(name) exceeds the \(limit)-byte limit.",
        fr: "Le fichier \(name) dépasse la limite de \(limit) octets."
      )
    case .imageTooLarge(let name, let limit):
      return L10n.text(
        de: "Das Bild \(name) überschreitet das Quelllimit von \(limit) Bytes.",
        en: "Image \(name) exceeds the \(limit)-byte source limit.",
        fr: "L’image \(name) dépasse la limite source de \(limit) octets."
      )
    case .totalContentTooLarge(let limit):
      return L10n.text(
        de: "Der extrahierte Inhalt aller Textanhänge überschreitet das Gesamtlimit von \(limit) Zeichen.",
        en: "The extracted content of all text attachments exceeds the total limit of \(limit) characters.",
        fr: "Le contenu extrait de toutes les pièces jointes texte dépasse la limite totale de \(limit) caractères."
      )
    case .totalImagePayloadTooLarge(let limit):
      return L10n.text(
        de: "Die normalisierten Bildanhänge überschreiten zusammen das Limit von \(limit) Bytes.",
        en: "The normalized image attachments exceed the combined \(limit)-byte limit.",
        fr: "Les images normalisées dépassent ensemble la limite de \(limit) octets."
      )
    case .unsupportedFile(let name):
      return L10n.text(
        de: "Die Datei \(name) wird nicht unterstützt. Möglich sind Text, Quellcode, Konfiguration, Logs, CSV, JSON, XML, YAML, Markdown, PDF sowie gängige Bildformate.",
        en: "File \(name) is unsupported. Text, source code, configuration, logs, CSV, JSON, XML, YAML, Markdown, PDF, and common image formats are supported.",
        fr: "Le fichier \(name) n’est pas pris en charge. Les formats texte, code source, configuration, journaux, CSV, JSON, XML, YAML, Markdown, PDF et images courantes sont acceptés."
      )
    case .unreadableFile(let name):
      return L10n.text(
        de: "Die Datei \(name) konnte nicht gelesen werden.",
        en: "File \(name) could not be read.",
        fr: "Le fichier \(name) n’a pas pu être lu."
      )
    case .invalidImage(let name):
      return L10n.text(
        de: "Das Bild \(name) konnte von macOS nicht dekodiert werden.",
        en: "Image \(name) could not be decoded by macOS.",
        fr: "L’image \(name) n’a pas pu être décodée par macOS."
      )
    case .imageEncodingFailed(let name):
      return L10n.text(
        de: "Das Bild \(name) konnte nicht als kontrolliertes JPEG vorbereitet werden.",
        en: "Image \(name) could not be prepared as a controlled JPEG payload.",
        fr: "L’image \(name) n’a pas pu être préparée comme charge JPEG contrôlée."
      )
    case .imageProviderUnsupported:
      return L10n.text(
        de: "Bildanhänge werden in diesem Build über visionfähige Ollama-Modelle unterstützt. Der Apple-On-Device-Provider erhält keine Bilddaten.",
        en: "Image attachments are supported through vision-capable Ollama models in this build. The Apple on-device provider does not receive image data.",
        fr: "Dans cette version, les images sont prises en charge via des modèles Ollama compatibles vision. Le fournisseur Apple local ne reçoit pas de données d’image."
      )
    case .modelDoesNotSupportVision(let model):
      return L10n.text(
        de: "Das Ollama-Modell „\(model)“ meldet keine Vision-Fähigkeit. Wähle ein visionfähiges Modell, bevor du Bilder sendest.",
        en: "Ollama model “\(model)” does not report vision capability. Select a vision-capable model before sending images.",
        fr: "Le modèle Ollama « \(model) » ne déclare pas de capacité vision. Sélectionnez un modèle compatible avant d’envoyer des images."
      )
    }
  }
}

@MainActor
public enum PromptAttachmentService {
  public static let maximumFiles = 8
  public static let maximumImages = 4
  public static let maximumFileBytes = 2 * 1024 * 1024
  public static let maximumImageSourceBytes = 12 * 1024 * 1024
  public static let maximumImagePayloadBytes = 6 * 1024 * 1024
  public static let maximumTotalImagePayloadBytes = 20 * 1024 * 1024
  public static let maximumExtractedCharactersPerFile = 48_000
  public static let maximumTotalExtractedCharacters = 120_000
  public static let maximumImageDimension = 2_048

  private static let textExtensions: Set<String> = [
    "txt", "md", "markdown", "swift", "m", "mm", "h", "c", "cc", "cpp",
    "py", "js", "ts", "tsx", "jsx", "java", "kt", "kts", "go", "rs",
    "sh", "bash", "zsh", "fish", "ps1", "sql", "html", "htm", "css",
    "scss", "json", "jsonl", "yaml", "yml", "xml", "plist", "toml",
    "ini", "conf", "config", "env", "properties", "csv", "tsv", "log",
    "dockerfile", ".gitignore", "gitignore"
  ]

  private static let imageExtensions: Set<String> = [
    "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp"
  ]

  public static func selectPromptFiles(
    existingCount: Int = 0,
    existingCharacterCount: Int = 0,
    existingImageCount: Int = 0,
    existingImageBytes: Int = 0
  ) throws -> [PromptAttachment]? {
    let panel = NSOpenPanel()
    panel.title = L10n.text(
      de: "Dateien oder Bilder zum Prompt hinzufügen",
      en: "Add Files or Images to Prompt",
      fr: "Ajouter des fichiers ou des images à l’invite"
    )
    panel.prompt = L10n.text(de: "Hinzufügen", en: "Add", fr: "Ajouter")
    panel.message = L10n.text(
      de: "Text, Code, Konfiguration, Logs, CSV, JSON, YAML, XML, Markdown, PDF oder Bilder auswählen.",
      en: "Select text, code, configuration, logs, CSV, JSON, YAML, XML, Markdown, PDF, or images.",
      fr: "Sélectionnez du texte, du code, des configurations, journaux, CSV, JSON, YAML, XML, Markdown, PDF ou des images."
    )
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.resolvesAliases = true

    guard panel.runModal() == .OK else { return nil }
    return try importPromptFiles(
      panel.urls,
      existingCount: existingCount,
      existingCharacterCount: existingCharacterCount,
      existingImageCount: existingImageCount,
      existingImageBytes: existingImageBytes
    )
  }

  public static func importPromptFiles(
    _ urls: [URL],
    existingCount: Int = 0,
    existingCharacterCount: Int = 0,
    existingImageCount: Int = 0,
    existingImageBytes: Int = 0
  ) throws -> [PromptAttachment] {
    guard existingCount + urls.count <= maximumFiles else {
      throw PromptAttachmentError.tooManyFiles(maximumFiles)
    }

    var attachments: [PromptAttachment] = []
    var totalCharacterCount = existingCharacterCount
    var totalImageCount = existingImageCount
    var totalImageBytes = existingImageBytes

    for url in urls {
      let accessed = url.startAccessingSecurityScopedResource()
      defer {
        if accessed { url.stopAccessingSecurityScopedResource() }
      }

      let attachment = try attachment(for: url)
      switch attachment.kind {
      case .text:
        totalCharacterCount += attachment.extractedText.count
        guard totalCharacterCount <= maximumTotalExtractedCharacters else {
          throw PromptAttachmentError.totalContentTooLarge(
            maximumTotalExtractedCharacters
          )
        }
      case .image:
        totalImageCount += 1
        guard totalImageCount <= maximumImages else {
          throw PromptAttachmentError.tooManyImages(maximumImages)
        }
        totalImageBytes += attachment.byteCount
        guard totalImageBytes <= maximumTotalImagePayloadBytes else {
          throw PromptAttachmentError.totalImagePayloadTooLarge(
            maximumTotalImagePayloadBytes
          )
        }
      }
      attachments.append(attachment)
    }

    return attachments
  }

  public static func prepareProviderContent(
    prompt: String,
    attachments: [PromptAttachment]
  ) throws -> String {
    guard !attachments.isEmpty else { return prompt }

    var persistedReferences: [PromptImageReference] = []
    do {
      let sections = try attachments.map { attachment -> String in
        switch attachment.kind {
        case .text:
          return """
            <agentm5n_attachment name="\(escapedAttribute(attachment.name))" media_type="\(escapedAttribute(attachment.mediaType))" bytes="\(attachment.byteCount)" truncated="\(attachment.wasTruncated)">
            \(attachment.extractedText)
            </agentm5n_attachment>
            """

        case .image:
          let reference = try PromptImageAttachmentStorage.persist(attachment)
          persistedReferences.append(reference)
          return imageMarker(for: reference)
        }
      }

      let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmedPrompt.isEmpty {
        return sections.joined(separator: "\n\n")
      }
      return prompt + "\n\n" + sections.joined(separator: "\n\n")
    } catch {
      for reference in persistedReferences {
        PromptImageAttachmentStorage.remove(reference)
      }
      throw error
    }
  }

  private static func attachment(for url: URL) throws -> PromptAttachment {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else {
      throw PromptAttachmentError.unsupportedFile(url.lastPathComponent)
    }

    let byteCount = values.fileSize ?? 0
    let extensionName = url.pathExtension.lowercased()
    if imageExtensions.contains(extensionName) {
      guard byteCount <= maximumImageSourceBytes else {
        throw PromptAttachmentError.imageTooLarge(
          url.lastPathComponent,
          maximumImageSourceBytes
        )
      }
      return try imageAttachment(for: url)
    }

    guard byteCount <= maximumFileBytes else {
      throw PromptAttachmentError.fileTooLarge(
        url.lastPathComponent,
        maximumFileBytes
      )
    }

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
      kind: .text,
      extractedText: extractedText,
      wasTruncated: wasTruncated
    )
  }

  private static func imageAttachment(for url: URL) throws -> PromptAttachment {
    let sourceData = try Data(contentsOf: url, options: [.mappedIfSafe])
    guard let sourceImage = NSImage(data: sourceData),
      let cgImage = sourceImage.cgImage(
        forProposedRect: nil,
        context: nil,
        hints: nil
      )
    else {
      throw PromptAttachmentError.invalidImage(url.lastPathComponent)
    }

    let sourceWidth = cgImage.width
    let sourceHeight = cgImage.height
    guard sourceWidth > 0, sourceHeight > 0 else {
      throw PromptAttachmentError.invalidImage(url.lastPathComponent)
    }

    let largestDimension = max(sourceWidth, sourceHeight)
    let scale = min(
      1.0,
      Double(maximumImageDimension) / Double(largestDimension)
    )
    let targetWidth = max(1, Int((Double(sourceWidth) * scale).rounded()))
    let targetHeight = max(1, Int((Double(sourceHeight) * scale).rounded()))

    guard let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: targetWidth,
      pixelsHigh: targetHeight,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: false,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
      throw PromptAttachmentError.imageEncodingFailed(url.lastPathComponent)
    }

    bitmap.size = NSSize(width: targetWidth, height: targetHeight)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight).fill()
    let normalizedImage = NSImage(
      cgImage: cgImage,
      size: NSSize(width: targetWidth, height: targetHeight)
    )
    normalizedImage.draw(
      in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
      from: .zero,
      operation: .sourceOver,
      fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let jpegData = bitmap.representation(
      using: .jpeg,
      properties: [.compressionFactor: 0.86]
    ), !jpegData.isEmpty else {
      throw PromptAttachmentError.imageEncodingFailed(url.lastPathComponent)
    }
    guard jpegData.count <= maximumImagePayloadBytes else {
      throw PromptAttachmentError.fileTooLarge(
        url.lastPathComponent,
        maximumImagePayloadBytes
      )
    }

    return PromptAttachment(
      name: url.lastPathComponent,
      byteCount: jpegData.count,
      mediaType: "image/jpeg",
      kind: .image,
      imageData: jpegData,
      pixelWidth: targetWidth,
      pixelHeight: targetHeight
    )
  }

  private static func imageMarker(
    for reference: PromptImageReference
  ) -> String {
    """
    <agentm5n_image_attachment id="\(reference.id.uuidString.lowercased())" name="\(escapedAttribute(reference.name))" media_type="\(escapedAttribute(reference.mediaType))" bytes="\(reference.byteCount)" path="\(escapedAttribute(reference.relativePath))" width="\(reference.pixelWidth)" height="\(reference.pixelHeight)" />
    """
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

  static func escapedAttribute(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }
}
