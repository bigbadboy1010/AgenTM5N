import Foundation

public enum GeneratedDOCXWriter {
  public static func write(
    title: String,
    content: String,
    to destinationURL: URL
  ) throws {
    let entries: [String: String] = [
      "[Content_Types].xml": contentTypes,
      "_rels/.rels": GeneratedOOXMLSupport.rootRelationships(
        officeTarget: "word/document.xml"
      ),
      "docProps/core.xml": GeneratedOOXMLSupport.coreProperties(title: title),
      "docProps/app.xml": GeneratedOOXMLSupport.appProperties(
        documentType: "Microsoft Office Word"
      ),
      "word/document.xml": documentXML(title: title, content: content),
      "word/styles.xml": stylesXML,
      "word/_rels/document.xml.rels": emptyRelationships,
    ]
    try GeneratedOOXMLSupport.writePackage(entries: entries, to: destinationURL)
  }

  private static func documentXML(title: String, content: String) -> String {
    var paragraphs = [paragraph(text: title, style: "Title")]
    for line in content.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("### ") {
        paragraphs.append(paragraph(text: String(trimmed.dropFirst(4)), style: "Heading2"))
      } else if trimmed.hasPrefix("## ") {
        paragraphs.append(paragraph(text: String(trimmed.dropFirst(3)), style: "Heading2"))
      } else if trimmed.hasPrefix("# ") {
        paragraphs.append(paragraph(text: String(trimmed.dropFirst(2)), style: "Heading1"))
      } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
        paragraphs.append(paragraph(text: "• " + String(trimmed.dropFirst(2)), style: "Normal"))
      } else {
        paragraphs.append(paragraph(text: line, style: "Normal"))
      }
    }

    return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body>
        \(paragraphs.joined(separator: "\n"))
        <w:sectPr>
          <w:pgSz w:w="11906" w:h="16838"/>
          <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/>
        </w:sectPr>
      </w:body>
    </w:document>
    """
  }

  private static func paragraph(text: String, style: String) -> String {
    """
    <w:p>
      <w:pPr><w:pStyle w:val="\(style)"/></w:pPr>
      <w:r><w:t xml:space="preserve">\(GeneratedOOXMLSupport.escapeXML(text))</w:t></w:r>
    </w:p>
    """
  }

  private static let contentTypes = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
    <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
    <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
  </Types>
  """

  private static let emptyRelationships = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
  """

  private static let stylesXML = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
      <w:name w:val="Normal"/>
      <w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="22"/></w:rPr>
    </w:style>
    <w:style w:type="paragraph" w:styleId="Title">
      <w:name w:val="Title"/><w:basedOn w:val="Normal"/>
      <w:pPr><w:spacing w:after="240"/></w:pPr>
      <w:rPr><w:b/><w:sz w:val="40"/><w:color w:val="1F2937"/></w:rPr>
    </w:style>
    <w:style w:type="paragraph" w:styleId="Heading1">
      <w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>
      <w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/></w:pPr>
      <w:rPr><w:b/><w:sz w:val="30"/><w:color w:val="1F2937"/></w:rPr>
    </w:style>
    <w:style w:type="paragraph" w:styleId="Heading2">
      <w:name w:val="heading 2"/><w:basedOn w:val="Normal"/>
      <w:pPr><w:keepNext/><w:spacing w:before="180" w:after="80"/></w:pPr>
      <w:rPr><w:b/><w:sz w:val="26"/><w:color w:val="374151"/></w:rPr>
    </w:style>
  </w:styles>
  """
}
