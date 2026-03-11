import AppKit
import Foundation

let arguments = CommandLine.arguments
let outputURL: URL
if arguments.count > 1 {
    outputURL = URL(fileURLWithPath: arguments[1])
} else {
    outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("AppBundle")
        .appendingPathComponent("PaperMaster-1024.png")
}

extension NSColor {
    static let pmNightTop = NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.22, alpha: 1)
    static let pmNightBottom = NSColor(calibratedRed: 0.05, green: 0.09, blue: 0.14, alpha: 1)
    static let pmInk = NSColor(calibratedRed: 0.15, green: 0.18, blue: 0.20, alpha: 1)
    static let pmBrass = NSColor(calibratedRed: 0.80, green: 0.66, blue: 0.40, alpha: 1)
    static let pmBrassBright = NSColor(calibratedRed: 0.92, green: 0.81, blue: 0.57, alpha: 1)
    static let pmPaper = NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.88, alpha: 1)
    static let pmPaperShade = NSColor(calibratedRed: 0.90, green: 0.85, blue: 0.77, alpha: 1)
    static let pmSlate = NSColor(calibratedRed: 0.42, green: 0.46, blue: 0.49, alpha: 1)
    static let pmRed = NSColor(calibratedRed: 0.63, green: 0.20, blue: 0.20, alpha: 1)
    static let pmGreen = NSColor(calibratedRed: 0.27, green: 0.41, blue: 0.33, alpha: 1)
}

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func ellipse(center: NSPoint, radiusX: CGFloat, radiusY: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(
        x: center.x - radiusX,
        y: center.y - radiusY,
        width: radiusX * 2,
        height: radiusY * 2
    ))
}

func fill(_ path: NSBezierPath, color: NSColor, alpha: CGFloat = 1) {
    color.withAlphaComponent(alpha).setFill()
    path.fill()
}

func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat, alpha: CGFloat = 1) {
    color.withAlphaComponent(alpha).setStroke()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

func fillGradient(_ path: NSBezierPath, colors: [NSColor], angle: CGFloat) {
    NSGradient(colors: colors)?.draw(in: path, angle: angle)
}

func fillWithShadow(_ path: NSBezierPath, color: NSColor, shadowColor: NSColor, blur: CGFloat, offset: CGSize) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = shadowColor
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    fill(path, color: color)
    NSGraphicsContext.restoreGraphicsState()
}

func strokeLine(from: NSPoint, to: NSPoint, color: NSColor, width: CGFloat, alpha: CGFloat = 1) {
    let path = NSBezierPath()
    path.move(to: from)
    path.line(to: to)
    stroke(path, color: color, width: width, alpha: alpha)
}

func transformed(_ path: NSBezierPath, around center: NSPoint, degrees: CGFloat) -> NSBezierPath {
    let copy = path.copy() as! NSBezierPath
    var transform = AffineTransform()
    transform.translate(x: center.x, y: center.y)
    transform.rotate(byDegrees: degrees)
    transform.translate(x: -center.x, y: -center.y)
    copy.transform(using: transform)
    return copy
}

func drawLeaf(center: NSPoint, width: CGFloat, height: CGFloat, angle: CGFloat, color: NSColor) {
    let rect = NSRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    let leaf = NSBezierPath()
    leaf.move(to: NSPoint(x: rect.midX, y: rect.maxY))
    leaf.curve(
        to: NSPoint(x: rect.midX, y: rect.minY),
        controlPoint1: NSPoint(x: rect.maxX, y: rect.maxY - height * 0.28),
        controlPoint2: NSPoint(x: rect.maxX, y: rect.minY + height * 0.28)
    )
    leaf.curve(
        to: NSPoint(x: rect.midX, y: rect.maxY),
        controlPoint1: NSPoint(x: rect.minX, y: rect.minY + height * 0.28),
        controlPoint2: NSPoint(x: rect.minX, y: rect.maxY - height * 0.28)
    )
    let rotated = transformed(leaf, around: center, degrees: angle)
    fill(rotated, color: color)
}

func drawLaurel(side: CGFloat) {
    let branch = NSBezierPath()
    branch.move(to: NSPoint(x: 512 + side * 248, y: 312))
    branch.curve(
        to: NSPoint(x: 512 + side * 172, y: 700),
        controlPoint1: NSPoint(x: 512 + side * 270, y: 416),
        controlPoint2: NSPoint(x: 512 + side * 244, y: 610)
    )
    stroke(branch, color: .pmBrass, width: 12, alpha: 0.95)

    let leaves: [(CGFloat, CGFloat, CGFloat)] = [
        (232, 368, -38),
        (216, 428, -22),
        (200, 492, -10),
        (190, 556, 4),
        (188, 620, 18),
        (196, 678, 34)
    ]

    for leaf in leaves {
        let x = 512 + side * leaf.0
        drawLeaf(
            center: NSPoint(x: x, y: leaf.1),
            width: 34,
            height: 72,
            angle: side > 0 ? leaf.2 : -leaf.2,
            color: .pmBrassBright
        )
    }
}

func drawPage(rect: NSRect, angle: CGFloat, accentColor: NSColor) {
    let center = NSPoint(x: rect.midX, y: rect.midY)
    let page = transformed(roundedRect(rect, radius: 20), around: center, degrees: angle)
    fillWithShadow(
        page,
        color: .pmPaper,
        shadowColor: NSColor.black.withAlphaComponent(0.24),
        blur: 24,
        offset: CGSize(width: 0, height: -10)
    )
    stroke(page, color: .pmPaperShade, width: 5)

    let margin = transformed(
        NSBezierPath(rect: NSRect(x: rect.minX + 34, y: rect.minY + 36, width: 4, height: rect.height - 72)),
        around: center,
        degrees: angle
    )
    fill(margin, color: accentColor, alpha: 0.72)

    let lines = [rect.maxY - 64, rect.maxY - 98, rect.maxY - 132, rect.maxY - 166, rect.maxY - 200]
    for (index, y) in lines.enumerated() {
        let length = rect.width - (index == 3 ? 98 : 74)
        let line = NSBezierPath()
        line.move(to: NSPoint(x: rect.minX + 56, y: y))
        line.line(to: NSPoint(x: rect.minX + length, y: y))
        let rotated = transformed(line, around: center, degrees: angle)
        stroke(rotated, color: .pmSlate, width: 4.5, alpha: index == 4 ? 0.50 : 0.68)
    }

    let underline = NSBezierPath()
    underline.move(to: NSPoint(x: rect.minX + 56, y: rect.minY + 74))
    underline.line(to: NSPoint(x: rect.maxX - 92, y: rect.minY + 74))
    let rotatedUnderline = transformed(underline, around: center, degrees: angle)
    stroke(rotatedUnderline, color: accentColor, width: 5, alpha: 0.76)
}

func drawGlasses() {
    let leftLens = ellipse(center: NSPoint(x: 448, y: 642), radiusX: 60, radiusY: 50)
    let rightLens = ellipse(center: NSPoint(x: 576, y: 642), radiusX: 60, radiusY: 50)
    fill(leftLens, color: .pmNightTop, alpha: 0.10)
    fill(rightLens, color: .pmNightTop, alpha: 0.10)
    stroke(leftLens, color: .pmInk, width: 12)
    stroke(rightLens, color: .pmInk, width: 12)

    let bridge = NSBezierPath()
    bridge.move(to: NSPoint(x: 508, y: 644))
    bridge.line(to: NSPoint(x: 516, y: 644))
    stroke(bridge, color: .pmInk, width: 10)

    let leftArm = NSBezierPath()
    leftArm.move(to: NSPoint(x: 392, y: 646))
    leftArm.curve(to: NSPoint(x: 336, y: 618), controlPoint1: NSPoint(x: 368, y: 646), controlPoint2: NSPoint(x: 348, y: 632))
    stroke(leftArm, color: .pmInk, width: 8, alpha: 0.9)

    let rightArm = NSBezierPath()
    rightArm.move(to: NSPoint(x: 632, y: 646))
    rightArm.curve(to: NSPoint(x: 688, y: 618), controlPoint1: NSPoint(x: 656, y: 646), controlPoint2: NSPoint(x: 676, y: 632))
    stroke(rightArm, color: .pmInk, width: 8, alpha: 0.9)
}

func drawBadge() {
    let badge = ellipse(center: NSPoint(x: 512, y: 242), radiusX: 74, radiusY: 74)
    fillGradient(badge, colors: [.pmBrassBright, .pmBrass], angle: -90)
    stroke(badge, color: .pmPaper, width: 6, alpha: 0.55)

    let star = NSBezierPath()
    let points = [
        NSPoint(x: 512, y: 286),
        NSPoint(x: 526, y: 255),
        NSPoint(x: 560, y: 252),
        NSPoint(x: 534, y: 232),
        NSPoint(x: 542, y: 198),
        NSPoint(x: 512, y: 216),
        NSPoint(x: 482, y: 198),
        NSPoint(x: 490, y: 232),
        NSPoint(x: 464, y: 252),
        NSPoint(x: 498, y: 255)
    ]
    star.move(to: points[0])
    for point in points.dropFirst() {
        star.line(to: point)
    }
    star.close()
    fill(star, color: .pmPaper)

    let ribbons = NSBezierPath()
    ribbons.move(to: NSPoint(x: 482, y: 186))
    ribbons.line(to: NSPoint(x: 496, y: 122))
    ribbons.line(to: NSPoint(x: 512, y: 154))
    ribbons.line(to: NSPoint(x: 528, y: 122))
    ribbons.line(to: NSPoint(x: 542, y: 186))
    ribbons.close()
    fill(ribbons, color: .pmRed, alpha: 0.88)
}

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let canvas = NSRect(origin: .zero, size: size)
let background = roundedRect(canvas.insetBy(dx: 44, dy: 44), radius: 228)
fillGradient(background, colors: [.pmNightTop, .pmNightBottom], angle: -90)

let frame = roundedRect(canvas.insetBy(dx: 72, dy: 72), radius: 194)
stroke(frame, color: .pmBrass, width: 3, alpha: 0.30)

let halo = ellipse(center: NSPoint(x: 512, y: 520), radiusX: 292, radiusY: 292)
fill(halo, color: .pmBrass, alpha: 0.15)
let innerHalo = ellipse(center: NSPoint(x: 512, y: 520), radiusX: 248, radiusY: 248)
fill(innerHalo, color: .pmPaper, alpha: 0.95)
stroke(innerHalo, color: .pmBrass, width: 10, alpha: 0.85)

drawLaurel(side: -1)
drawLaurel(side: 1)

let leftPage = NSRect(x: 308, y: 448, width: 212, height: 266)
let rightPage = NSRect(x: 504, y: 448, width: 212, height: 266)
drawPage(rect: leftPage, angle: 7, accentColor: .pmRed)
drawPage(rect: rightPage, angle: -7, accentColor: .pmBrass)

let spine = NSBezierPath()
spine.move(to: NSPoint(x: 512, y: 430))
spine.curve(to: NSPoint(x: 512, y: 698), controlPoint1: NSPoint(x: 494, y: 512), controlPoint2: NSPoint(x: 498, y: 616))
stroke(spine, color: .pmBrass, width: 7, alpha: 0.88)

let desk = roundedRect(NSRect(x: 304, y: 406, width: 416, height: 24), radius: 12)
fill(desk, color: .pmGreen)
stroke(desk, color: .pmBrass, width: 2, alpha: 0.34)

drawGlasses()
drawBadge()

let redPencil = NSBezierPath()
redPencil.move(to: NSPoint(x: 654, y: 744))
redPencil.line(to: NSPoint(x: 760, y: 844))
redPencil.line(to: NSPoint(x: 736, y: 868))
redPencil.line(to: NSPoint(x: 630, y: 768))
redPencil.close()
fill(redPencil, color: .pmRed, alpha: 0.92)

let pencilTip = NSBezierPath()
pencilTip.move(to: NSPoint(x: 760, y: 844))
pencilTip.line(to: NSPoint(x: 786, y: 852))
pencilTip.line(to: NSPoint(x: 744, y: 894))
pencilTip.line(to: NSPoint(x: 736, y: 868))
pencilTip.close()
fill(pencilTip, color: .pmPaperShade)

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to create PNG data")
}

try pngData.write(to: outputURL)
