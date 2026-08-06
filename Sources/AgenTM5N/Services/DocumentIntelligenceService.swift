import Foundation
import PDFKit

public enum DocumentIntelligenceService {
  public static let supportedExtensions: Set<String> = [
    "pdf", "docx", "xlsx", "pptx"
  ]
  public static let maximumDocumentSourceBytes = 25 * 1024 * 1024
  public static let maximumExtractedCharacters = 240_000

  public static func extract(url: URL) throws -> DocumentExtractionResult {
    let extensionName = url.pathExtension.lowercased()
    guard supportedExtensions.contains(extensionName) else {
      throw OfficeDocumentExtractionError.unsupportedExtension(extensionName)
    }

    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else {
      throw PromptAttachmentError.unreadableFile(url.lastPathComponent)
    }
    let sourceBytes = values.fileSize ?? 0
    guard sourceBytes <= maximumDocumentSourceBytes else {
      throw OfficeDocumentExtractionError.sourceTooLarge(
        url.lastPathComponent,
        maximumDocumentSourceBytes
      )
    }

    let sha256 = try DocumentExtractionCache.sha256(for: url)
    if let cached = try DocumentExtractionCache.load(sha256: sha256) {
      return cached
    }

    let extracted: DocumentExtractionResult
    switch extensionName {
    case "pdf":
      extracted = try extractPDF(url: url, sourceSHA256: sha256)
    case "docx", "xlsx", "pptx":
      extracted = try OfficeOpenXMLExtractionService.extract(
        url: url,
        sourceSHA256: sha256
      )
    default:
      throw OfficeDocumentExtractionError.unsupportedExtension(extensionName)
    }

    try DocumentExtractionCache.save(extracted, sha256: sha256)
    return extracted.withCacheHit(false)
  }

  private static func extractPDF(
    url: URL,
    sourceSHA256: String
  ) throws -> DocumentExtractionResult {
    guard let document = PDFDocument(url: url) else {
      throw PromptAttachmentError.unreadableFile(url.lastPathComponent)
    }

    var directSections: [PromptAttachmentSection] = []
    var directCharacterCount = 0
    for index in 0..<document.pageCount {
      guard let raw = document.page(at: index)?.string else { continue }
      let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      let remaining = maximumExtractedCharacters - directCharacterCount
      guard remaining > 0 else { break }
      let boundedText = text.count > remaining
        ? String(text.prefix(remaining))
        : text
      directSections.append(
        PromptAttachmentSection(
          locator: "Seite \(index + 1)",
          title: nil,
          text: boundedText
        )
      )
      directCharacterCount += boundedText.count
    }

    let minimumUsefulCharacters = max(160, document.pageCount * 24)
    if directCharacterCount >= minimumUsefulCharacters {
      let text = renderPDFSections(
        directSections,
        fileName: url.lastPathComponent,
        ocr: false
      )
      return DocumentExtractionResult(
        text: text,
        sections: directSections,
        metadata: PromptAttachmentMetadata(
          documentKind: .pdf,
          extractionMethod: .pdfText,
          sectionCount: directSections.count,
          pageCount: document.pageCount,
          ocrUsed: false,
          sourceSHA256: sourceSHA256
        )
      )
    }

    let ocr = try LocalOCRService.recognizePDF(
      document,
      fileName: url.lastPathComponent
    )
    return DocumentExtractionResult(
      text: ocr.text,
      sections: ocr.sections,
      metadata: PromptAttachmentMetadata(
        documentKind: .pdf,
        extractionMethod: .visionOCR,
        sectionCount: ocr.sections.count,
        pageCount: document.pageCount,
        ocrUsed: true,
        sourceSHA256: sourceSHA256
      )
    )
  }

  private static func renderPDFSections(
    _ sections: [PromptAttachmentSection],
    fileName: String,
    ocr: Bool
  ) -> String {
    sections.map { section in
      let suffix = ocr ? ", OCR" : ""
      return """
        [Datei: \(fileName), \(section.locator)\(suffix)]
        \(section.text)
        """
    }
    .joined(separator: "\n\n")
  }
}
