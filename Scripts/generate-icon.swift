import AppKit
import Foundation

let arguments = CommandLine.arguments
let outputURL: URL
if arguments.count > 1 {
    outputURL = URL(fileURLWithPath: arguments[1])
} else {
    outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("AppBundle")
        .appendingPathComponent("HenryPaper-1024.png")
}

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let rect = NSRect(origin: .zero, size: size)
let backgroundPath = NSBezierPath(roundedRect: rect.insetBy(dx: 40, dy: 40), xRadius: 230, yRadius: 230)
NSColor(calibratedRed: 0.94, green: 0.54, blue: 0.20, alpha: 1).setFill()
backgroundPath.fill()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.99, green: 0.69, blue: 0.33, alpha: 1),
    NSColor(calibratedRed: 0.89, green: 0.40, blue: 0.18, alpha: 1)
])!
gradient.draw(in: backgroundPath, angle: -45)

let glowPath = NSBezierPath(ovalIn: NSRect(x: 150, y: 540, width: 520, height: 360))
NSGraphicsContext.current?.saveGraphicsState()
let glow = NSShadow()
glow.shadowBlurRadius = 70
glow.shadowOffset = CGSize(width: 0, height: 0)
glow.shadowColor = NSColor.white.withAlphaComponent(0.28)
glow.set()
NSColor.white.withAlphaComponent(0.18).setFill()
glowPath.fill()
NSGraphicsContext.current?.restoreGraphicsState()

let paperRect = NSRect(x: 250, y: 180, width: 470, height: 620)
var transform = AffineTransform()
transform.translate(x: paperRect.midX, y: paperRect.midY)
transform.rotate(byDegrees: -8)
transform.translate(x: -paperRect.midX, y: -paperRect.midY)
let paperPath = NSBezierPath(roundedRect: paperRect, xRadius: 48, yRadius: 48)
paperPath.transform(using: transform)

NSGraphicsContext.current?.saveGraphicsState()
let paperShadow = NSShadow()
paperShadow.shadowBlurRadius = 35
paperShadow.shadowOffset = CGSize(width: 0, height: -14)
paperShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
paperShadow.set()
NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.93, alpha: 1).setFill()
paperPath.fill()
NSGraphicsContext.current?.restoreGraphicsState()

NSColor(calibratedRed: 0.84, green: 0.66, blue: 0.46, alpha: 0.24).setStroke()
paperPath.lineWidth = 3
paperPath.stroke()

let foldPath = NSBezierPath()
foldPath.move(to: NSPoint(x: 642, y: 746))
foldPath.line(to: NSPoint(x: 712, y: 716))
foldPath.line(to: NSPoint(x: 690, y: 642))
foldPath.close()
foldPath.transform(using: transform)
NSColor(calibratedRed: 0.95, green: 0.87, blue: 0.76, alpha: 1).setFill()
foldPath.fill()

func drawLine(_ rect: NSRect, color: NSColor, radius: CGFloat = 14) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.transform(using: transform)
    color.setFill()
    path.fill()
}

drawLine(NSRect(x: 320, y: 635, width: 310, height: 30), color: NSColor(calibratedRed: 0.12, green: 0.33, blue: 0.37, alpha: 1), radius: 15)
drawLine(NSRect(x: 320, y: 580, width: 210, height: 22), color: NSColor(calibratedRed: 0.33, green: 0.57, blue: 0.56, alpha: 1), radius: 11)
drawLine(NSRect(x: 320, y: 495, width: 330, height: 18), color: NSColor(calibratedRed: 0.83, green: 0.77, blue: 0.67, alpha: 1), radius: 9)
drawLine(NSRect(x: 320, y: 450, width: 300, height: 18), color: NSColor(calibratedRed: 0.83, green: 0.77, blue: 0.67, alpha: 1), radius: 9)
drawLine(NSRect(x: 320, y: 405, width: 250, height: 18), color: NSColor(calibratedRed: 0.83, green: 0.77, blue: 0.67, alpha: 1), radius: 9)

let badgeRect = NSRect(x: 555, y: 185, width: 220, height: 220)
let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 62, yRadius: 62)
NSGraphicsContext.current?.saveGraphicsState()
let badgeShadow = NSShadow()
badgeShadow.shadowBlurRadius = 24
badgeShadow.shadowOffset = CGSize(width: 0, height: -10)
badgeShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
badgeShadow.set()
let badgeGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.17, green: 0.71, blue: 0.67, alpha: 1),
    NSColor(calibratedRed: 0.08, green: 0.47, blue: 0.54, alpha: 1)
])!
badgeGradient.draw(in: badgePath, angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()

let headerRect = NSRect(x: 555, y: 325, width: 220, height: 48)
let headerPath = NSBezierPath(roundedRect: headerRect, xRadius: 28, yRadius: 28)
NSColor.white.withAlphaComponent(0.23).setFill()
headerPath.fill()

let ringLeft = NSBezierPath(ovalIn: NSRect(x: 602, y: 340, width: 18, height: 24))
let ringRight = NSBezierPath(ovalIn: NSRect(x: 710, y: 340, width: 18, height: 24))
NSColor.white.setFill()
ringLeft.fill()
ringRight.fill()

let checkPath = NSBezierPath()
checkPath.move(to: NSPoint(x: 615, y: 275))
checkPath.line(to: NSPoint(x: 655, y: 238))
checkPath.line(to: NSPoint(x: 720, y: 308))
NSColor.white.setStroke()
checkPath.lineWidth = 26
checkPath.lineCapStyle = .round
checkPath.lineJoinStyle = .round
checkPath.stroke()

let accentDot = NSBezierPath(ovalIn: NSRect(x: 175, y: 165, width: 70, height: 70))
NSColor(calibratedRed: 0.95, green: 0.90, blue: 0.79, alpha: 0.55).setFill()
accentDot.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to create PNG data\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try pngData.write(to: outputURL)
print(outputURL.path)
