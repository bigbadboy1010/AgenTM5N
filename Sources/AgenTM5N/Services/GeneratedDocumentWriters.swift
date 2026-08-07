import Foundation

public enum GeneratedDocumentWriterError: LocalizedError {
  case archiveToolUnavailable
  case archiveCreationFailed(String)
  case pdfCreationFailed
  case invalidSpreadsheet
  case tooManySpreadsheetCells(Int)
  case tooManySlides(Int)

  public var errorDescription: String? {
    switch self {
    case .archiveToolUnavailable:
      return L10n.text(de: "Das macOS-Werkzeug /usr/bin/zip ist nicht verfügbar.", en: "The macOS /usr/bin/zip tool is unavailable.", fr: "L’outil macOS /usr/bin/zip n’est pas disponible.")
    case .archiveCreationFailed(let detail):
      return L10n.text(de: "Das Office-Dokument konnte nicht verpackt werden: \(detail)", en: "The Office document could not be packaged: \(detail)", fr: "Le document Office n’a pas pu être empaqueté : \(detail)")
    case .pdfCreationFailed:
      return L10n.text(de: "Das PDF konnte nicht erzeugt werden.", en: "The PDF could not be generated.", fr: "Le PDF n’a pas pu être généré.")
    case .invalidSpreadsheet:
      return L10n.text(de: "Die Tabellendaten enthalten keine verwertbaren Zeilen.", en: "The spreadsheet data does not contain usable rows.", fr: "Les données du tableur ne contiennent aucune ligne exploitable.")
    case .tooManySpreadsheetCells(let maximum):
      return L10n.text(de: "Die Tabelle überschreitet das Limit von \(maximum) Zellen.", en: "The spreadsheet exceeds the limit of \(maximum) cells.", fr: "Le tableur dépasse la limite de \(maximum) cellules.")
    case .tooManySlides(let maximum):
      return L10n.text(de: "Die Präsentation überschreitet das Limit von \(maximum) Folien.", en: "The presentation exceeds the limit of \(maximum) slides.", fr: "La présentation dépasse la limite de \(maximum) diapositives.")
    }
  }
}

public enum GeneratedDocumentWriters {
  public static func write(
    request: GeneratedDocumentRequest,
    to destinationURL: URL
  ) throws {
    switch request.format {
    case .pdf:
      try GeneratedPDFWriter.write(title: request.title, content: request.content, to: destinationURL)
    case .docx:
      try GeneratedDOCXWriter.write(title: request.title, content: request.content, to: destinationURL)
    case .xlsx:
      try GeneratedXLSXWriter.write(title: request.title, content: request.content, to: destinationURL)
    case .pptx:
      try GeneratedPPTXWriter.write(title: request.title, content: request.content, to: destinationURL)
    }
  }
}
