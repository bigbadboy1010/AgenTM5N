#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments

guard arguments.count == 2 else {
  fputs("Usage: generate-app-icon.swift <output.png>\n", stderr)
  exit(2)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let canvasSize = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvasSize)

image.lockFocus()
defer { image.unlockFocus() }

NSGraphicsContext.current?.imageInterpolation = .high

let fullRect = NSRect(origin: .zero, size: canvasSize)
let backgroundRect = fullRect.insetBy(dx: 58, dy: 58)
let background = NSBezierPath(
  roundedRect: backgroundRect,
  xRadius: 230,
  yRadius: 230
)

let gradient = NSGradient(
  colors: [
    NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.16, alpha: 1),
    NSColor(calibratedRed: 0.16, green: 0.24, blue: 0.42, alpha: 1),
    NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.66, alpha: 1),
  ]
)!
gradient.draw(in: background, angle: -45)

let innerGlow = NSBezierPath(
  roundedRect: backgroundRect.insetBy(dx: 34, dy: 34),
  xRadius: 200,
  yRadius: 200
)
NSColor.white.withAlphaComponent(0.08).setStroke()
innerGlow.lineWidth = 6
innerGlow.stroke()

func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
  NSPoint(x: x, y: y)
}

func drawConnection(from start: NSPoint, to end: NSPoint, width: CGFloat = 18) {
  let path = NSBezierPath()
  path.move(to: start)
  path.line(to: end)
  path.lineWidth = width
  path.lineCapStyle = .round
  NSColor.white.withAlphaComponent(0.72).setStroke()
  path.stroke()
}

func drawNode(center: NSPoint, radius: CGFloat) {
  let shadow = NSBezierPath(
    ovalIn: NSRect(
      x: center.x - radius - 10,
      y: center.y - radius - 10,
      width: (radius + 10) * 2,
      height: (radius + 10) * 2
    )
  )
  NSColor.black.withAlphaComponent(0.16).setFill()
  shadow.fill()

  let circle = NSBezierPath(
    ovalIn: NSRect(
      x: center.x - radius,
      y: center.y - radius,
      width: radius * 2,
      height: radius * 2
    )
  )
  NSColor.white.withAlphaComponent(0.94).setFill()
  circle.fill()
}

let center = point(512, 520)
let upperLeft = point(300, 710)
let upperRight = point(724, 710)
let lowerLeft = point(286, 328)
let lowerRight = point(738, 328)
let top = point(512, 790)

for target in [upperLeft, upperRight, lowerLeft, lowerRight, top] {
  drawConnection(from: center, to: target)
}

drawConnection(from: upperLeft, to: top, width: 12)
drawConnection(from: upperRight, to: top, width: 12)
drawConnection(from: lowerLeft, to: lowerRight, width: 12)

for node in [upperLeft, upperRight, lowerLeft, lowerRight, top] {
  drawNode(center: node, radius: 31)
}

drawNode(center: center, radius: 92)

let letter = "A" as NSString
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 126, weight: .heavy),
  .foregroundColor: NSColor(calibratedRed: 0.11, green: 0.22, blue: 0.37, alpha: 1),
  .paragraphStyle: paragraph,
]
let letterRect = NSRect(x: 420, y: 446, width: 184, height: 160)
letter.draw(in: letterRect, withAttributes: attributes)

let accent = NSBezierPath()
accent.move(to: point(250, 204))
accent.curve(
  to: point(774, 204),
  controlPoint1: point(382, 146),
  controlPoint2: point(642, 146)
)
accent.lineWidth = 15
accent.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.34).setStroke()
accent.stroke()

guard let tiff = image.tiffRepresentation,
  let bitmap = NSBitmapImageRep(data: tiff),
  let png = bitmap.representation(using: .png, properties: [:])
else {
  fputs("Could not render AgenTM5N app icon.\n", stderr)
  exit(1)
}

try FileManager.default.createDirectory(
  at: outputURL.deletingLastPathComponent(),
  withIntermediateDirectories: true
)
try png.write(to: outputURL, options: [.atomic])
