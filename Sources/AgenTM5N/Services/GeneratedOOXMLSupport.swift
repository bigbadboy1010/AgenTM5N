import Foundation

public enum GeneratedOOXMLSupport {
  public static func writePackage(
    entries: [String: String],
    to destinationURL: URL
  ) throws {
    guard FileManager.default.isExecutableFile(atPath: "/usr/bin/zip") else {
      throw GeneratedDocumentWriterError.archiveToolUnavailable
    }

    let manager = FileManager.default
    let staging = manager.temporaryDirectory.appendingPathComponent(
      "AgenTM5N-Document-\(UUID().uuidString)",
      isDirectory: true
    )
    try manager.createDirectory(
      at: staging,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    defer { try? manager.removeItem(at: staging) }

    for (relativePath, text) in entries {
      let target = staging.appendingPathComponent(relativePath)
      try manager.createDirectory(
        at: target.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try Data(text.utf8).write(to: target, options: [.atomic])
    }

    if manager.fileExists(atPath: destinationURL.path) {
      try manager.removeItem(at: destinationURL)
    }

    let topLevel = Set(entries.keys.compactMap { path -> String? in
      path.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init)
    }).sorted()

    let process = Process()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = staging
    process.arguments = ["-X", "-q", "-r", destinationURL.path] + topLevel
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()

    let errorData = try errorPipe.fileHandleForReading.readToEnd() ?? Data()
    guard process.terminationStatus == 0 else {
      let detail = String(data: errorData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw GeneratedDocumentWriterError.archiveCreationFailed(
        detail.flatMap { $0.isEmpty ? nil : $0 } ?? "Exit \(process.terminationStatus)"
      )
    }
  }

  public static func rootRelationships(officeTarget: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="\(officeTarget)"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
      <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
    </Relationships>
    """
  }

  public static func coreProperties(title: String) -> String {
    let now = iso8601Now()
    return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <dc:title>\(escapeXML(title))</dc:title>
      <dc:creator>AgenTM5N</dc:creator>
      <cp:lastModifiedBy>AgenTM5N</cp:lastModifiedBy>
      <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>
      <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>
    </cp:coreProperties>
    """
  }

  public static func appProperties(documentType: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
      <Application>AgenTM5N</Application>
      <AppVersion>0.9</AppVersion>
      <HyperlinksChanged>false</HyperlinksChanged>
      <LinksUpToDate>false</LinksUpToDate>
      <SharedDoc>false</SharedDoc>
      <Template>\(escapeXML(documentType))</Template>
    </Properties>
    """
  }

  public static func escapeXML(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }

  private static func iso8601Now() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: Date())
  }
}
