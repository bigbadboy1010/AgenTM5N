import AppKit
import Foundation
import PDFKit
import Vision

public enum LocalOCRError: LocalizedError {
  case imageUnavailable(Int)
  case recognitionFailed(String)
  case noTextRecognized

  public var errorDescription: String? {
    switch self {
    case .imageUnavailable(let page):
      return L10n.text(
        de: "PDF-Seite \(page) konnte nicht für OCR gerendert werden.",
        en: "PDF page \(page) could not be rendered for OCR.",
        fr: "La page PDF \(page) n’a pas pu être rendue pour l’OCR."
      )
    case .recognitionFailed(let detail):
      return L10n.text(
        de: "Die lokale Texterkennung ist fehlgeschlagen: \(detail)",
        en: "Local text recognition failed: \(detail)",
        fr: "La reconnaissance locale du texte a échoué : \(detail)"
      )
    case .noTextRecognized:
      return L10n.text(
        de: "In den gescannten Seiten wurde kein Text erkannt.",
        en: "No text was recognized in the scanned pages.",
        fr: "Aucun texte n’a été reconnu dans les pages numérisées."
      )
    }
  }
}

public struct PDFOCRResult: Sendable {
  public let text: String
  public let sections: [PromptAttachmentSection]
  public let processedPageCount: Int

  public init(
    text: String,
    sections: [PromptAttachmentSection],
    processedPageCount: Int
  ) {
    self.text = text
    self.sections = sections
    self.processedPageCount = processedPageCount
  }
}

public enum LocalOCRService {
  public static let maximumPDFPages = 40
  public static let maximumCharacters = 180_000
  public static let renderingDimension: CGFloat = 2_200

  public static func recognizeText(in image: CGImage) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.automaticallyDetectsLanguage = true
    request.minimumTextHeight = 0.008

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
      try handler.perform([request])
    } catch {
      throw LocalOCRError.recognitionFailed(error.localizedDescription)
    }

    let lines = (request.results ?? []).compactMap { observation in
      observation.topCandidates(1).first?.string
    }
    return lines.joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func recognizePDF(
    _ document: PDFDocument,
    fileName: String
  ) throws -> PDFOCRResult {
    let pageLimit = min(document.pageCount, maximumPDFPages)
    var sections: [PromptAttachmentSection] = []
    var totalCharacters = 0

    for index in 0..<pageLimit {
      guard let page = document.page(at: index) else { continue }
      let thumbnail = page.thumbnail(
        of: NSSize(
          width: renderingDimension,
          height: renderingDimension
        ),
        for: .mediaBox
      )
      guard let image = thumbnail.cgImage(
        forProposedRect: nil,
        context: nil,
        hints: nil
      ) else {
        throw LocalOCRError.imageUnavailable(index + 1)
      }

      let recognized = try recognizeText(in: image)
      guard !recognized.isEmpty else { continue }
      let remaining = maximumCharacters - totalCharacters
      guard remaining > 0 else { break }
      let pageText = recognized.count > remaining
        ? String(recognized.prefix(remaining))
        : recognized
      sections.append(
        PromptAttachmentSection(
          locator: "Seite \(index + 1)",
          title: "OCR",
          text: pageText
        )
      )
      totalCharacters += pageText.count
    }

    guard !sections.isEmpty else {
      throw LocalOCRError.noTextRecognized
    }

    let text = sections.map { section in
      """
      [Datei: \(fileName), \(section.locator), OCR]
      \(section.text)
      """
    }
    .joined(separator: "\n\n")

    return PDFOCRResult(
      text: text,
      sections: sections,
      processedPageCount: pageLimit
    )
  }
}
