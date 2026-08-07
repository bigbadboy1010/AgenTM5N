import CoreGraphics
import CoreText
import Foundation

public enum GeneratedPDFWriter {
  public static func write(
    title: String,
    content: String,
    to destinationURL: URL
  ) throws {
    let attributed = makeAttributedString(title: title, content: content)
    guard attributed.length > 0,
      let consumer = CGDataConsumer(url: destinationURL as CFURL)
    else {
      throw GeneratedDocumentWriterError.pdfCreationFailed
    }

    var mediaBox = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
      throw GeneratedDocumentWriterError.pdfCreationFailed
    }

    let framesetter = CTFramesetterCreateWithAttributedString(
      attributed as CFAttributedString
    )
    let contentRect = CGRect(
      x: 54,
      y: 54,
      width: mediaBox.width - 108,
      height: mediaBox.height - 108
    )
    var location = 0

    while location < attributed.length {
      context.beginPDFPage(nil)
      let path = CGMutablePath()
      path.addRect(contentRect)
      let frame = CTFramesetterCreateFrame(
        framesetter,
        CFRange(location: location, length: 0),
        path,
        nil
      )
      CTFrameDraw(frame, context)
      let visible = CTFrameGetVisibleStringRange(frame)
      context.endPDFPage()
      guard visible.length > 0 else { break }
      location += visible.length
    }

    context.closePDF()
    guard FileManager.default.fileExists(atPath: destinationURL.path) else {
      throw GeneratedDocumentWriterError.pdfCreationFailed
    }
  }

  private static func makeAttributedString(
    title: String,
    content: String
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()
    append(
      title + "\n\n",
      fontName: "Helvetica-Bold",
      fontSize: 22,
      to: result
    )

    for line in content.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("### ") {
        append(String(trimmed.dropFirst(4)) + "\n", fontName: "Helvetica-Bold", fontSize: 13, to: result)
      } else if trimmed.hasPrefix("## ") {
        append(String(trimmed.dropFirst(3)) + "\n", fontName: "Helvetica-Bold", fontSize: 15, to: result)
      } else if trimmed.hasPrefix("# ") {
        append(String(trimmed.dropFirst(2)) + "\n", fontName: "Helvetica-Bold", fontSize: 17, to: result)
      } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
        append("• " + String(trimmed.dropFirst(2)) + "\n", fontName: "Helvetica", fontSize: 11, to: result)
      } else {
        append(line + "\n", fontName: "Helvetica", fontSize: 11, to: result)
      }
    }
    return result
  }

  private static func append(
    _ text: String,
    fontName: String,
    fontSize: CGFloat,
    to result: NSMutableAttributedString
  ) {
    let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    let color = CGColor(gray: 0.08, alpha: 1)
    result.append(
      NSAttributedString(
        string: text,
        attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): font,
          NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
      )
    )
  }
}
