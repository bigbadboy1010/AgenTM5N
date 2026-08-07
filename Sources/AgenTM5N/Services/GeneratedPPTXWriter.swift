import Foundation

public enum GeneratedPPTXWriter {
  public static let maximumSlides = 40

  public static func write(
    title: String,
    content: String,
    to destinationURL: URL
  ) throws {
    let slides = parseSlides(title: title, content: content)
    guard slides.count <= maximumSlides else {
      throw GeneratedDocumentWriterError.tooManySlides(maximumSlides)
    }

    var entries: [String: String] = [
      "_rels/.rels": GeneratedOOXMLSupport.rootRelationships(
        officeTarget: "ppt/presentation.xml"
      ),
      "docProps/core.xml": GeneratedOOXMLSupport.coreProperties(title: title),
      "docProps/app.xml": GeneratedOOXMLSupport.appProperties(
        documentType: "Microsoft PowerPoint"
      ),
      "ppt/presentation.xml": presentationXML(slideCount: slides.count),
      "ppt/_rels/presentation.xml.rels": presentationRelationships(
        slideCount: slides.count
      ),
      "ppt/slideMasters/slideMaster1.xml": slideMasterXML,
      "ppt/slideMasters/_rels/slideMaster1.xml.rels": slideMasterRelationships,
      "ppt/slideLayouts/slideLayout1.xml": slideLayoutXML,
      "ppt/slideLayouts/_rels/slideLayout1.xml.rels": slideLayoutRelationships,
      "ppt/theme/theme1.xml": themeXML,
    ]

    for (offset, slide) in slides.enumerated() {
      let index = offset + 1
      entries["ppt/slides/slide\(index).xml"] = slideXML(slide: slide, index: index)
      entries["ppt/slides/_rels/slide\(index).xml.rels"] = slideRelationships
    }
    entries["[Content_Types].xml"] = contentTypes(slideCount: slides.count)
    try GeneratedOOXMLSupport.writePackage(entries: entries, to: destinationURL)
  }

  private static func parseSlides(
    title: String,
    content: String
  ) -> [GeneratedPresentationSlide] {
    let lines = content
      .replacingOccurrences(of: "\r\n", with: "\n")
      .components(separatedBy: "\n")
    var sections: [[String]] = [[]]
    for line in lines {
      if line.trimmingCharacters(in: .whitespaces) == "---" {
        sections.append([])
      } else {
        sections[sections.count - 1].append(line)
      }
    }

    let parsed = sections.compactMap { section -> GeneratedPresentationSlide? in
      let trimmed = section.drop {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      guard let first = trimmed.first else { return nil }
      var slideTitle = first.trimmingCharacters(in: .whitespaces)
      while slideTitle.hasPrefix("#") {
        slideTitle.removeFirst()
        slideTitle = slideTitle.trimmingCharacters(in: .whitespaces)
      }
      let body = trimmed.dropFirst()
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return GeneratedPresentationSlide(
        title: slideTitle.isEmpty ? title : slideTitle,
        body: body
      )
    }
    return parsed.isEmpty
      ? [GeneratedPresentationSlide(title: title, body: content)]
      : parsed
  }

  private static func contentTypes(slideCount: Int) -> String {
    let slideOverrides = (1...max(1, slideCount)).prefix(slideCount).map { index in
      "<Override PartName=\"/ppt/slides/slide\(index).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
    }.joined()
    return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
      <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
      <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
      <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
      \(slideOverrides)
      <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
      <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
    </Types>
    """
  }

  private static func presentationXML(slideCount: Int) -> String {
    let slideIDs = (1...max(1, slideCount)).prefix(slideCount).enumerated().map {
      offset, index in
      "<p:sldId id=\"\(256 + offset)\" r:id=\"rId\(index + 1)\"/>"
    }.joined()
    return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
      <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>
      <p:sldIdLst>\(slideIDs)</p:sldIdLst>
      <p:sldSz cx="12192000" cy="6858000" type="screen16x9"/>
      <p:notesSz cx="6858000" cy="9144000"/>
      <p:defaultTextStyle><a:defPPr/><a:lvl1pPr marL="0" algn="l" defTabSz="914400"><a:defRPr lang="de-DE"/></a:lvl1pPr></p:defaultTextStyle>
    </p:presentation>
    """
  }

  private static func presentationRelationships(slideCount: Int) -> String {
    var relationships = [
      "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"
    ]
    for index in 1...max(1, slideCount) where index <= slideCount {
      relationships.append(
        "<Relationship Id=\"rId\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(index).xml\"/>"
      )
    }
    return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      \(relationships.joined(separator: "\n"))
    </Relationships>
    """
  }

  private static func slideXML(
    slide: GeneratedPresentationSlide,
    index: Int
  ) -> String {
    let titleShape = textShape(
      id: 2,
      name: "Title \(index)",
      x: 914_400,
      y: 548_640,
      width: 10_363_200,
      height: 1_005_840,
      paragraphs: [slide.title],
      fontSize: 28,
      bold: true
    )
    let bodyLines = slide.body.components(separatedBy: .newlines)
    let bodyShape = textShape(
      id: 3,
      name: "Body \(index)",
      x: 914_400,
      y: 1_828_800,
      width: 10_363_200,
      height: 4_206_240,
      paragraphs: bodyLines.isEmpty ? [""] : bodyLines,
      fontSize: 18,
      bold: false
    )
    return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
      <p:cSld><p:spTree>
        \(groupShape)
        \(titleShape)
        \(bodyShape)
      </p:spTree></p:cSld>
      <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
    </p:sld>
    """
  }

  private static func textShape(
    id: Int,
    name: String,
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    paragraphs: [String],
    fontSize: Int,
    bold: Bool
  ) -> String {
    let textParagraphs = paragraphs.map { rawLine -> String in
      let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
      let bullet = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
      let text = bullet ? String(trimmed.dropFirst(2)) : rawLine
      let paragraphProperties = bullet
        ? "<a:pPr marL=\"457200\" indent=\"-228600\"><a:buChar char=\"•\"/></a:pPr>"
        : "<a:pPr/>"
      return """
      <a:p>\(paragraphProperties)<a:r><a:rPr lang="de-DE" sz="\(fontSize * 100)"\(bold ? " b=\"1\"" : "")/><a:t>\(GeneratedOOXMLSupport.escapeXML(text))</a:t></a:r><a:endParaRPr lang="de-DE" sz="\(fontSize * 100)"/></a:p>
      """
    }.joined()

    return """
    <p:sp>
      <p:nvSpPr><p:cNvPr id="\(id)" name="\(GeneratedOOXMLSupport.escapeXML(name))"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
      <p:spPr><a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(width)" cy="\(height)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr>
      <p:txBody><a:bodyPr wrap="square" rtlCol="0"><a:spAutoFit/></a:bodyPr><a:lstStyle/>\(textParagraphs)</p:txBody>
    </p:sp>
    """
  }

  private static let groupShape = """
  <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
  <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
  """

  private static let slideRelationships = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
  </Relationships>
  """

  private static let slideMasterXML = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
    <p:cSld name="AgenTM5N Master"><p:spTree>\(groupShape)</p:spTree></p:cSld>
    <p:clrMap accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" bg1="lt1" bg2="lt2" folHlink="folHlink" hlink="hlink" tx1="dk1" tx2="dk2"/>
    <p:sldLayoutIdLst><p:sldLayoutId id="1" r:id="rId1"/></p:sldLayoutIdLst>
    <p:txStyles>
      <p:titleStyle><a:lvl1pPr algn="l"><a:defRPr sz="2800" b="1"/></a:lvl1pPr></p:titleStyle>
      <p:bodyStyle><a:lvl1pPr marL="342900" indent="-342900"><a:defRPr sz="1800"/></a:lvl1pPr></p:bodyStyle>
      <p:otherStyle><a:defPPr><a:defRPr sz="1800"/></a:defPPr></p:otherStyle>
    </p:txStyles>
  </p:sldMaster>
  """

  private static let slideMasterRelationships = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
  </Relationships>
  """

  private static let slideLayoutXML = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1">
    <p:cSld name="Blank"><p:spTree>\(groupShape)</p:spTree></p:cSld>
    <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
  </p:sldLayout>
  """

  private static let slideLayoutRelationships = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
  </Relationships>
  """

  private static let themeXML = """
  <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
  <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="AgenTM5N Theme">
    <a:themeElements>
      <a:clrScheme name="AgenTM5N">
        <a:dk1><a:srgbClr val="111827"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>
        <a:dk2><a:srgbClr val="374151"/></a:dk2><a:lt2><a:srgbClr val="F3F4F6"/></a:lt2>
        <a:accent1><a:srgbClr val="2563EB"/></a:accent1><a:accent2><a:srgbClr val="0891B2"/></a:accent2>
        <a:accent3><a:srgbClr val="16A34A"/></a:accent3><a:accent4><a:srgbClr val="CA8A04"/></a:accent4>
        <a:accent5><a:srgbClr val="DC2626"/></a:accent5><a:accent6><a:srgbClr val="7C3AED"/></a:accent6>
        <a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink>
      </a:clrScheme>
      <a:fontScheme name="AgenTM5N">
        <a:majorFont><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>
        <a:minorFont><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>
      </a:fontScheme>
      <a:fmtScheme name="AgenTM5N">
        <a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>
        <a:lnStyleLst><a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln></a:lnStyleLst>
        <a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>
        <a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst>
      </a:fmtScheme>
    </a:themeElements>
    <a:objectDefaults/><a:extraClrSchemeLst/>
  </a:theme>
  """
}
