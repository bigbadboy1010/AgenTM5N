import Foundation

public enum GeneratedXLSXWriter {
  public static let maximumCells = 20_000

  public static func write(
    title: String,
    content: String,
    to destinationURL: URL
  ) throws {
    let rows = parseTabularContent(content)
    guard !rows.isEmpty else { throw GeneratedDocumentWriterError.invalidSpreadsheet }
    let maxColumns = rows.map(\.count).max() ?? 0
    guard rows.count * maxColumns <= maximumCells else {
      throw GeneratedDocumentWriterError.tooManySpreadsheetCells(maximumCells)
    }

    let entries: [String: String] = [
      "[Content_Types].xml": contentTypes,
      "_rels/.rels": GeneratedOOXMLSupport.rootRelationships(
        officeTarget: "xl/workbook.xml"
      ),
      "docProps/core.xml": GeneratedOOXMLSupport.coreProperties(title: title),
      "docProps/app.xml": GeneratedOOXMLSupport.appProperties(
        documentType: "Microsoft Excel"
      ),
      "xl/workbook.xml": workbookXML,
      "xl/_rels/workbook.xml.rels": workbookRelationships,
      "xl/worksheets/sheet1.xml": sheetXML(rows: rows),
      "xl/styles.xml": stylesXML,
    ]
    try GeneratedOOXMLSupport.writePackage(entries: entries, to: destinationURL)
  }

  private static func parseTabularContent(_ content: String) -> [[String]] {
    let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
    if normalized.contains("\t") {
      return normalized
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in
          line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        }
        .filter { row in
          row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
    }
    return parseCSV(normalized)
  }

  private static func parseCSV(_ content: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var insideQuotes = false
    var index = content.startIndex

    while index < content.endIndex {
      let character = content[index]
      if character == "\"" {
        let next = content.index(after: index)
        if insideQuotes, next < content.endIndex, content[next] == "\"" {
          field.append("\"")
          index = content.index(after: next)
          continue
        }
        insideQuotes.toggle()
      } else if character == ",", !insideQuotes {
        row.append(field)
        field = ""
      } else if character == "\n", !insideQuotes {
        row.append(field)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
          rows.append(row)
        }
        row = []
        field = ""
      } else if character != "\r" {
        field.append(character)
      }
      index = content.index(after: index)
    }

    row.append(field)
    if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
      rows.append(row)
    }
    return rows
  }

  private static func sheetXML(rows: [[String]]) -> String {
    let maxColumns = rows.map(\.count).max() ?? 1
    var widths = Array(repeating: 10, count: maxColumns)
    for row in rows {
      for (column, value) in row.enumerated() where column < widths.count {
        widths[column] = min(40, max(widths[column], value.count + 2))
      }
    }

    let columns = widths.enumerated().map { index, width in
      "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
    }.joined()

    let rowXML = rows.enumerated().map { rowIndex, row in
      let cells = row.enumerated().map { columnIndex, value in
        let reference = "\(columnName(columnIndex + 1))\(rowIndex + 1)"
        let style = rowIndex == 0 ? " s=\"1\"" : ""
        return "<c r=\"\(reference)\" t=\"inlineStr\"\(style)><is><t xml:space=\"preserve\">\(GeneratedOOXMLSupport.escapeXML(value))</t></is></c>"
      }.joined()
      return "<row r=\"\(rowIndex + 1)\">\(cells)</row>"
    }.joined()

    return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
      <cols>\(columns)</cols>
      <sheetData>\(rowXML)</sheetData>
    </worksheet>
    """
  }

  private static func columnName(_ column: Int) -> String {
    var value = max(1, column)
    var result = ""
    while value > 0 {
      value -= 1
      let scalar = UnicodeScalar(65 + (value % 26))!
      result = String(Character(scalar)) + result
      value /= 26
    }
    return result
  }

  private static let contentTypes = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
    <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
  </Types>
  """

  private static let workbookXML = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
    <sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets>
  </workbook>
  """

  private static let workbookRelationships = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  </Relationships>
  """

  private static let stylesXML = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <fonts count="2">
      <font><sz val="11"/><name val="Arial"/></font>
      <font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Arial"/></font>
    </fonts>
    <fills count="3">
      <fill><patternFill patternType="none"/></fill>
      <fill><patternFill patternType="gray125"/></fill>
      <fill><patternFill patternType="solid"><fgColor rgb="FF374151"/><bgColor indexed="64"/></patternFill></fill>
    </fills>
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="2">
      <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
      <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
    </cellXfs>
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
  </styleSheet>
  """
}
