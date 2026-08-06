import Foundation

public enum OfficeDocumentExtractionError: LocalizedError {
  case unsupportedExtension(String)
  case sourceTooLarge(String, Int)
  case malformedXML(String)
  case noReadableContent(String)
  case tooManySections(Int)

  public var errorDescription: String? {
    switch self {
    case .unsupportedExtension(let value):
      return L10n.text(
        de: "Das Office-Format .\(value) wird nicht unterstützt.",
        en: "Office format .\(value) is unsupported.",
        fr: "Le format Office .\(value) n’est pas pris en charge."
      )
    case .sourceTooLarge(let name, let limit):
      return L10n.text(
        de: "Das Office-Dokument \(name) überschreitet das Quelllimit von \(limit) Bytes.",
        en: "Office document \(name) exceeds the \(limit)-byte source limit.",
        fr: "Le document Office \(name) dépasse la limite source de \(limit) octets."
      )
    case .malformedXML(let component):
      return L10n.text(
        de: "Der Office-Bestandteil \(component) enthält ungültiges XML.",
        en: "Office component \(component) contains malformed XML.",
        fr: "Le composant Office \(component) contient un XML non valide."
      )
    case .noReadableContent(let name):
      return L10n.text(
        de: "Im Office-Dokument \(name) wurde kein lesbarer Text gefunden.",
        en: "No readable text was found in Office document \(name).",
        fr: "Aucun texte lisible n’a été trouvé dans le document Office \(name)."
      )
    case .tooManySections(let limit):
      return L10n.text(
        de: "Das Office-Dokument überschreitet das Limit von \(limit) extrahierten Abschnitten.",
        en: "The Office document exceeds the limit of \(limit) extracted sections.",
        fr: "Le document Office dépasse la limite de \(limit) sections extraites."
      )
    }
  }
}

public enum OfficeOpenXMLExtractionService {
  public static let maximumSourceBytes = 25 * 1024 * 1024
  public static let maximumXMLBytes = 8 * 1024 * 1024
  public static let maximumSections = 500
  public static let maximumExtractedCharacters = 240_000
  public static let maximumWorksheets = 100
  public static let maximumSlides = 300
  public static let maximumRowsPerWorksheet = 20_000

  public static func extract(
    url: URL,
    sourceSHA256: String
  ) throws -> DocumentExtractionResult {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true else {
      throw PromptAttachmentError.unreadableFile(url.lastPathComponent)
    }
    let sourceBytes = values.fileSize ?? 0
    guard sourceBytes <= maximumSourceBytes else {
      throw OfficeDocumentExtractionError.sourceTooLarge(
        url.lastPathComponent,
        maximumSourceBytes
      )
    }

    let reader = try SafeZipArchiveReader(url: url)
    _ = try reader.entries()

    let result: DocumentExtractionResult
    switch url.pathExtension.lowercased() {
    case "docx":
      result = try extractWord(
        reader: reader,
        fileName: url.lastPathComponent,
        sourceSHA256: sourceSHA256
      )
    case "xlsx":
      result = try extractExcel(
        reader: reader,
        fileName: url.lastPathComponent,
        sourceSHA256: sourceSHA256
      )
    case "pptx":
      result = try extractPowerPoint(
        reader: reader,
        fileName: url.lastPathComponent,
        sourceSHA256: sourceSHA256
      )
    default:
      throw OfficeDocumentExtractionError.unsupportedExtension(
        url.pathExtension.lowercased()
      )
    }

    guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw OfficeDocumentExtractionError.noReadableContent(url.lastPathComponent)
    }
    return result
  }

  private static func extractWord(
    reader: SafeZipArchiveReader,
    fileName: String,
    sourceSHA256: String
  ) throws -> DocumentExtractionResult {
    let mainPath = "word/document.xml"
    let mainData = try reader.data(
      for: mainPath,
      maximumBytes: maximumXMLBytes
    )
    var blocks = try parseParagraphs(mainData, component: mainPath)

    let supplementalEntries = try reader.entries()
      .filter {
        $0.hasPrefix("word/header")
          || $0.hasPrefix("word/footer")
          || $0 == "word/footnotes.xml"
          || $0 == "word/endnotes.xml"
          || $0 == "word/comments.xml"
      }
      .filter { $0.hasSuffix(".xml") }
      .sorted()

    for entry in supplementalEntries {
      let data = try reader.data(for: entry, maximumBytes: maximumXMLBytes)
      let label = supplementalLabel(for: entry)
      let extracted = try parseParagraphs(data, component: entry)
      if !extracted.isEmpty {
        blocks.append("[\(label)]")
        blocks.append(contentsOf: extracted)
      }
    }

    let sections = try groupedSections(
      blocks: blocks,
      locatorPrefix: "Abschnitt",
      titlePrefix: "Word",
      maximumCharactersPerSection: 12_000
    )
    let text = render(sections: sections, fileName: fileName)
    let metadata = PromptAttachmentMetadata(
      documentKind: .docx,
      extractionMethod: .officeOpenXML,
      sectionCount: sections.count,
      sourceSHA256: sourceSHA256
    )
    return DocumentExtractionResult(
      text: bounded(text),
      sections: boundedSections(sections),
      metadata: metadata
    )
  }

  private static func extractExcel(
    reader: SafeZipArchiveReader,
    fileName: String,
    sourceSHA256: String
  ) throws -> DocumentExtractionResult {
    let sharedStrings: [String]
    if let data = try reader.optionalData(
      for: "xl/sharedStrings.xml",
      maximumBytes: maximumXMLBytes
    ) {
      sharedStrings = try parseSharedStrings(
        data,
        component: "xl/sharedStrings.xml"
      )
    } else {
      sharedStrings = []
    }

    let workbookData = try reader.data(
      for: "xl/workbook.xml",
      maximumBytes: maximumXMLBytes
    )
    let sheets = try parseWorkbook(
      workbookData,
      component: "xl/workbook.xml"
    )
    guard sheets.count <= maximumWorksheets else {
      throw OfficeDocumentExtractionError.tooManySections(maximumWorksheets)
    }

    let relationshipsData = try reader.data(
      for: "xl/_rels/workbook.xml.rels",
      maximumBytes: maximumXMLBytes
    )
    let relationships = try parseRelationships(
      relationshipsData,
      component: "xl/_rels/workbook.xml.rels"
    )

    var sections: [PromptAttachmentSection] = []
    for sheet in sheets {
      guard let target = relationships[sheet.relationshipID] else { continue }
      let entry = try normalizedOOXMLTarget(base: "xl", target: target)
      guard entry.hasPrefix("xl/worksheets/") else { continue }
      guard let data = try reader.optionalData(
        for: entry,
        maximumBytes: maximumXMLBytes
      ) else {
        continue
      }

      let rows = try parseWorksheet(
        data,
        sharedStrings: sharedStrings,
        component: entry
      )
      sections.append(contentsOf: worksheetSections(
        sheetName: sheet.name,
        rows: rows
      ))
      if sections.count > maximumSections {
        throw OfficeDocumentExtractionError.tooManySections(maximumSections)
      }
    }

    let text = render(sections: sections, fileName: fileName)
    let metadata = PromptAttachmentMetadata(
      documentKind: .xlsx,
      extractionMethod: .officeOpenXML,
      sectionCount: sections.count,
      sheetCount: sheets.count,
      sourceSHA256: sourceSHA256
    )
    return DocumentExtractionResult(
      text: bounded(text),
      sections: boundedSections(sections),
      metadata: metadata
    )
  }

  private static func extractPowerPoint(
    reader: SafeZipArchiveReader,
    fileName: String,
    sourceSHA256: String
  ) throws -> DocumentExtractionResult {
    let slideEntries = try reader.entries()
      .compactMap { entry -> (number: Int, path: String)? in
        guard entry.hasPrefix("ppt/slides/slide"),
          entry.hasSuffix(".xml"),
          !entry.contains("/_rels/")
        else {
          return nil
        }
        let file = URL(fileURLWithPath: entry).deletingPathExtension().lastPathComponent
        guard let number = Int(file.dropFirst("slide".count)) else {
          return nil
        }
        return (number, entry)
      }
      .sorted { $0.number < $1.number }

    guard slideEntries.count <= maximumSlides else {
      throw OfficeDocumentExtractionError.tooManySections(maximumSlides)
    }

    var sections: [PromptAttachmentSection] = []
    for slide in slideEntries {
      let slideData = try reader.data(
        for: slide.path,
        maximumBytes: maximumXMLBytes
      )
      var paragraphs = try parseParagraphs(
        slideData,
        component: slide.path
      )

      let notesPath = "ppt/notesSlides/notesSlide\(slide.number).xml"
      if let notesData = try reader.optionalData(
        for: notesPath,
        maximumBytes: maximumXMLBytes
      ) {
        let notes = try parseParagraphs(notesData, component: notesPath)
        if !notes.isEmpty {
          paragraphs.append("[Sprechernotizen]")
          paragraphs.append(contentsOf: notes)
        }
      }

      let text = paragraphs
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
      guard !text.isEmpty else { continue }
      let title = paragraphs.first.flatMap { value in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(180))
      }
      sections.append(
        PromptAttachmentSection(
          locator: "Folie \(slide.number)",
          title: title,
          text: String(text.prefix(20_000))
        )
      )
    }

    let text = render(sections: sections, fileName: fileName)
    let metadata = PromptAttachmentMetadata(
      documentKind: .pptx,
      extractionMethod: .officeOpenXML,
      sectionCount: sections.count,
      slideCount: slideEntries.count,
      sourceSHA256: sourceSHA256
    )
    return DocumentExtractionResult(
      text: bounded(text),
      sections: boundedSections(sections),
      metadata: metadata
    )
  }

  private static func parseParagraphs(
    _ data: Data,
    component: String
  ) throws -> [String] {
    let delegate = ParagraphXMLParserDelegate()
    try parseXML(data, delegate: delegate, component: component)
    return delegate.paragraphs
  }

  private static func parseSharedStrings(
    _ data: Data,
    component: String
  ) throws -> [String] {
    let delegate = SharedStringsXMLParserDelegate()
    try parseXML(data, delegate: delegate, component: component)
    return delegate.values
  }

  private static func parseWorkbook(
    _ data: Data,
    component: String
  ) throws -> [WorkbookSheet] {
    let delegate = WorkbookXMLParserDelegate()
    try parseXML(data, delegate: delegate, component: component)
    return delegate.sheets
  }

  private static func parseRelationships(
    _ data: Data,
    component: String
  ) throws -> [String: String] {
    let delegate = RelationshipsXMLParserDelegate()
    try parseXML(data, delegate: delegate, component: component)
    return delegate.relationships
  }

  private static func parseWorksheet(
    _ data: Data,
    sharedStrings: [String],
    component: String
  ) throws -> [WorksheetRow] {
    let delegate = WorksheetXMLParserDelegate(
      sharedStrings: sharedStrings,
      maximumRows: maximumRowsPerWorksheet
    )
    try parseXML(data, delegate: delegate, component: component)
    return delegate.rows
  }

  private static func parseXML(
    _ data: Data,
    delegate: XMLParserDelegate,
    component: String
  ) throws {
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = false
    parser.shouldReportNamespacePrefixes = false
    parser.shouldResolveExternalEntities = false
    guard parser.parse() else {
      throw OfficeDocumentExtractionError.malformedXML(component)
    }
  }

  private static func groupedSections(
    blocks: [String],
    locatorPrefix: String,
    titlePrefix: String,
    maximumCharactersPerSection: Int
  ) throws -> [PromptAttachmentSection] {
    var sections: [PromptAttachmentSection] = []
    var current: [String] = []
    var currentCount = 0

    func flush() {
      guard !current.isEmpty else { return }
      let number = sections.count + 1
      let joined = current.joined(separator: "\n")
      let title = current.first.map { String($0.prefix(180)) }
      sections.append(
        PromptAttachmentSection(
          locator: "\(locatorPrefix) \(number)",
          title: title ?? "\(titlePrefix) \(number)",
          text: joined
        )
      )
      current.removeAll(keepingCapacity: true)
      currentCount = 0
    }

    for block in blocks {
      let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      if !current.isEmpty,
        currentCount + trimmed.count + 1 > maximumCharactersPerSection
      {
        flush()
      }
      current.append(trimmed)
      currentCount += trimmed.count + 1
      if sections.count > maximumSections {
        throw OfficeDocumentExtractionError.tooManySections(maximumSections)
      }
    }
    flush()
    return sections
  }

  private static func worksheetSections(
    sheetName: String,
    rows: [WorksheetRow]
  ) -> [PromptAttachmentSection] {
    var result: [PromptAttachmentSection] = []
    var current: [WorksheetRow] = []
    var currentCount = 0

    func flush() {
      guard let first = current.first, let last = current.last else { return }
      let body = current.map { "Zeile \($0.number): \($0.text)" }
        .joined(separator: "\n")
      result.append(
        PromptAttachmentSection(
          locator: "Blatt \(sheetName), Zeilen \(first.number)–\(last.number)",
          title: sheetName,
          text: body
        )
      )
      current.removeAll(keepingCapacity: true)
      currentCount = 0
    }

    for row in rows {
      if !current.isEmpty,
        (current.count >= 100 || currentCount + row.text.count > 12_000)
      {
        flush()
      }
      current.append(row)
      currentCount += row.text.count + 1
    }
    flush()
    return result
  }

  private static func render(
    sections: [PromptAttachmentSection],
    fileName: String
  ) -> String {
    sections.map { section in
      let title = section.title.map { " — \($0)" } ?? ""
      return """
        [Datei: \(fileName), \(section.locator)\(title)]
        \(section.text)
        """
    }
    .joined(separator: "\n\n")
  }

  private static func bounded(_ text: String) -> String {
    guard text.count > maximumExtractedCharacters else { return text }
    return String(text.prefix(maximumExtractedCharacters))
      + "\n… [AgenTM5N: Dokumentinhalt gekürzt]"
  }

  private static func boundedSections(
    _ sections: [PromptAttachmentSection]
  ) -> [PromptAttachmentSection] {
    var total = 0
    var result: [PromptAttachmentSection] = []
    for section in sections {
      let remaining = maximumExtractedCharacters - total
      guard remaining > 0 else { break }
      let text = section.text.count > remaining
        ? String(section.text.prefix(remaining))
        : section.text
      result.append(
        PromptAttachmentSection(
          id: section.id,
          locator: section.locator,
          title: section.title,
          text: text
        )
      )
      total += text.count
    }
    return result
  }

  private static func supplementalLabel(for entry: String) -> String {
    if entry.contains("header") { return "Kopfzeile" }
    if entry.contains("footer") { return "Fußzeile" }
    if entry.contains("footnotes") { return "Fußnoten" }
    if entry.contains("endnotes") { return "Endnoten" }
    if entry.contains("comments") { return "Kommentare" }
    return entry
  }

  private static func normalizedOOXMLTarget(
    base: String,
    target: String
  ) throws -> String {
    let normalizedTarget = target.replacingOccurrences(of: "\\", with: "/")
    guard !normalizedTarget.hasPrefix("/"),
      !normalizedTarget.split(separator: "/").contains("..")
    else {
      throw SafeZipArchiveError.unsafeEntry(target)
    }
    return "\(base)/\(normalizedTarget)"
  }
}

private struct WorkbookSheet: Sendable {
  let name: String
  let relationshipID: String
}

private struct WorksheetRow: Sendable {
  let number: Int
  let text: String
}

private func localName(_ elementName: String) -> String {
  elementName.split(separator: ":").last.map(String.init) ?? elementName
}

private func attribute(
  _ attributes: [String: String],
  local target: String
) -> String? {
  attributes.first { localName($0.key) == target }?.value
}

private final class ParagraphXMLParserDelegate: NSObject, XMLParserDelegate {
  private(set) var paragraphs: [String] = []
  private var currentParagraph = ""
  private var capturesText = false

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    switch localName(elementName) {
    case "t":
      capturesText = true
    case "tab":
      currentParagraph.append("\t")
    case "br", "cr":
      currentParagraph.append("\n")
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if capturesText {
      currentParagraph.append(string)
    }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    switch localName(elementName) {
    case "t":
      capturesText = false
    case "p":
      let trimmed = currentParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        paragraphs.append(trimmed)
      }
      currentParagraph = ""
    case "tc":
      if !currentParagraph.hasSuffix("\t") {
        currentParagraph.append("\t")
      }
    default:
      break
    }
  }
}

private final class SharedStringsXMLParserDelegate: NSObject, XMLParserDelegate {
  private(set) var values: [String] = []
  private var current = ""
  private var capturesText = false
  private var insideItem = false

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    switch localName(elementName) {
    case "si":
      insideItem = true
      current = ""
    case "t":
      if insideItem { capturesText = true }
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if capturesText { current.append(string) }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    switch localName(elementName) {
    case "t":
      capturesText = false
    case "si":
      values.append(current)
      current = ""
      insideItem = false
    default:
      break
    }
  }
}

private final class WorkbookXMLParserDelegate: NSObject, XMLParserDelegate {
  private(set) var sheets: [WorkbookSheet] = []

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    guard localName(elementName) == "sheet",
      let name = attribute(attributeDict, local: "name"),
      let relationshipID = attribute(attributeDict, local: "id")
    else {
      return
    }
    sheets.append(WorkbookSheet(name: name, relationshipID: relationshipID))
  }
}

private final class RelationshipsXMLParserDelegate: NSObject, XMLParserDelegate {
  private(set) var relationships: [String: String] = [:]

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    guard localName(elementName) == "Relationship",
      let identifier = attribute(attributeDict, local: "Id"),
      let target = attribute(attributeDict, local: "Target")
    else {
      return
    }
    relationships[identifier] = target
  }
}

private final class WorksheetXMLParserDelegate: NSObject, XMLParserDelegate {
  private let sharedStrings: [String]
  private let maximumRows: Int
  private(set) var rows: [WorksheetRow] = []

  private var currentRowNumber = 0
  private var currentCells: [String] = []
  private var currentCellReference = ""
  private var currentCellType = ""
  private var currentValue = ""
  private var currentFormula = ""
  private var capturesValue = false
  private var capturesFormula = false
  private var capturesInlineText = false

  init(sharedStrings: [String], maximumRows: Int) {
    self.sharedStrings = sharedStrings
    self.maximumRows = maximumRows
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    switch localName(elementName) {
    case "row":
      currentRowNumber = Int(attribute(attributeDict, local: "r") ?? "")
        ?? (rows.last?.number ?? 0) + 1
      currentCells = []
    case "c":
      currentCellReference = attribute(attributeDict, local: "r") ?? ""
      currentCellType = attribute(attributeDict, local: "t") ?? ""
      currentValue = ""
      currentFormula = ""
    case "v":
      capturesValue = true
    case "f":
      capturesFormula = true
    case "t":
      if currentCellType == "inlineStr" { capturesInlineText = true }
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if capturesValue || capturesInlineText {
      currentValue.append(string)
    }
    if capturesFormula {
      currentFormula.append(string)
    }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    switch localName(elementName) {
    case "v":
      capturesValue = false
    case "f":
      capturesFormula = false
    case "t":
      capturesInlineText = false
    case "c":
      let value = resolvedCellValue()
      if !value.isEmpty {
        let prefix = currentCellReference.isEmpty ? "" : "\(currentCellReference)="
        currentCells.append(prefix + value)
      }
    case "row":
      if !currentCells.isEmpty, rows.count < maximumRows {
        rows.append(
          WorksheetRow(
            number: currentRowNumber,
            text: currentCells.joined(separator: " | ")
          )
        )
      }
    default:
      break
    }
  }

  private func resolvedCellValue() -> String {
    let raw: String
    switch currentCellType {
    case "s":
      if let index = Int(currentValue), sharedStrings.indices.contains(index) {
        raw = sharedStrings[index]
      } else {
        raw = currentValue
      }
    case "b":
      raw = currentValue == "1" ? "TRUE" : "FALSE"
    default:
      raw = currentValue
    }

    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let formula = currentFormula.trimmingCharacters(in: .whitespacesAndNewlines)
    if !formula.isEmpty {
      return trimmed.isEmpty ? "=\(formula)" : "=\(formula) → \(trimmed)"
    }
    return trimmed
  }
}
