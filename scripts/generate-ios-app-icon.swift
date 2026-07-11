import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

struct IconSize {
    let filename: String
    let pixels: Int
}

let iconSizes: [IconSize] = [
    .init(filename: "Icon-20@1x.png", pixels: 20),
    .init(filename: "Icon-20@2x.png", pixels: 40),
    .init(filename: "Icon-20@3x.png", pixels: 60),
    .init(filename: "Icon-29@1x.png", pixels: 29),
    .init(filename: "Icon-29@2x.png", pixels: 58),
    .init(filename: "Icon-29@3x.png", pixels: 87),
    .init(filename: "Icon-40@1x.png", pixels: 40),
    .init(filename: "Icon-40@2x.png", pixels: 80),
    .init(filename: "Icon-40@3x.png", pixels: 120),
    .init(filename: "Icon-60@2x.png", pixels: 120),
    .init(filename: "Icon-60@3x.png", pixels: 180),
    .init(filename: "Icon-76@1x.png", pixels: 76),
    .init(filename: "Icon-76@2x.png", pixels: 152),
    .init(filename: "Icon-83.5@2x.png", pixels: 167),
    .init(filename: "Icon-1024.png", pixels: 1024)
]

for size in iconSizes {
    let image = makeIcon(size: size.pixels)
    let url = outputDirectory.appendingPathComponent(size.filename)
    try writePNG(image: image, to: url)
}

func makeIcon(size: Int) -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    let scale = CGFloat(size) / 1024.0
    let rect = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
    let center = CGPoint(x: rect.midX, y: rect.midY)

    let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(calibratedRed: 0.99, green: 0.985, blue: 0.965, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.88, green: 0.95, blue: 1.00, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.965, green: 0.945, blue: 1.00, alpha: 1).cgColor
        ] as CFArray,
        locations: [0, 0.54, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    drawSoftEllipse(
        context,
        rect: CGRect(x: 42 * scale, y: 570 * scale, width: 610 * scale, height: 380 * scale),
        color: NSColor(calibratedRed: 0.50, green: 0.84, blue: 1.00, alpha: 0.24).cgColor
    )
    drawSoftEllipse(
        context,
        rect: CGRect(x: 520 * scale, y: 80 * scale, width: 420 * scale, height: 500 * scale),
        color: NSColor(calibratedRed: 0.72, green: 0.61, blue: 1.00, alpha: 0.18).cgColor
    )

    let glassRect = rect.insetBy(dx: 166 * scale, dy: 166 * scale)
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -28 * scale),
        blur: 54 * scale,
        color: NSColor(calibratedRed: 0.32, green: 0.48, blue: 0.62, alpha: 0.18).cgColor
    )
    context.setFillColor(NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.58).cgColor)
    context.fillEllipse(in: glassRect)
    context.restoreGState()

    context.saveGState()
    context.addEllipse(in: glassRect)
    context.clip()
    let glassGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.96).cgColor,
            NSColor(calibratedRed: 0.79, green: 0.93, blue: 1.00, alpha: 0.30).cgColor,
            NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.56).cgColor
        ] as CFArray,
        locations: [0, 0.50, 1]
    )!
    context.drawLinearGradient(
        glassGradient,
        start: CGPoint(x: glassRect.minX, y: glassRect.maxY),
        end: CGPoint(x: glassRect.maxX, y: glassRect.minY),
        options: []
    )

    context.setFillColor(NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.34).cgColor)
    context.fillEllipse(in: CGRect(x: 238 * scale, y: 650 * scale, width: 332 * scale, height: 152 * scale))
    context.restoreGState()

    context.setLineWidth(max(1, 2.5 * scale))
    context.setStrokeColor(NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.82).cgColor)
    context.strokeEllipse(in: glassRect.insetBy(dx: 2 * scale, dy: 2 * scale))
    context.setStrokeColor(NSColor(calibratedRed: 0.52, green: 0.65, blue: 0.78, alpha: 0.20).cgColor)
    context.strokeEllipse(in: glassRect.insetBy(dx: 9 * scale, dy: 9 * scale))

    let ringRadius = 302 * scale
    let lineWidth = max(4, 74 * scale)
    let ringRect = CGRect(
        x: center.x - ringRadius,
        y: center.y - ringRadius,
        width: ringRadius * 2,
        height: ringRadius * 2
    )

    context.setLineCap(.round)
    context.setLineWidth(lineWidth)
    context.setStrokeColor(NSColor(calibratedRed: 0.58, green: 0.66, blue: 0.74, alpha: 0.22).cgColor)
    context.strokeEllipse(in: ringRect)

    strokeArc(
        context,
        rect: ringRect,
        start: 96,
        end: 382,
        color: NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.56).cgColor,
        width: lineWidth + 13 * scale
    )
    strokeGradientArc(
        context,
        rect: ringRect,
        start: 104,
        end: 352,
        width: lineWidth,
        colors: [
            NSColor(calibratedRed: 0.06, green: 0.55, blue: 0.96, alpha: 0.98).cgColor,
            NSColor(calibratedRed: 0.08, green: 0.82, blue: 0.64, alpha: 0.98).cgColor,
            NSColor(calibratedRed: 0.58, green: 0.44, blue: 1.00, alpha: 0.98).cgColor
        ]
    )
    strokeArc(
        context,
        rect: ringRect.insetBy(dx: 24 * scale, dy: 24 * scale),
        start: 116,
        end: 332,
        color: NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.28).cgColor,
        width: max(2, 14 * scale)
    )

    let innerGlassRect = rect.insetBy(dx: 322 * scale, dy: 322 * scale)
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10 * scale),
        blur: 24 * scale,
        color: NSColor(calibratedRed: 0.19, green: 0.42, blue: 0.58, alpha: 0.16).cgColor
    )
    context.setFillColor(NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.46).cgColor)
    context.fillEllipse(in: innerGlassRect)
    context.restoreGState()

    drawCenteredLetterC(context, rect: rect, scale: scale)

    return context.makeImage()!
}

func strokeArc(_ context: CGContext, rect: CGRect, start: CGFloat, end: CGFloat, color: CGColor, width: CGFloat? = nil) {
    if let width {
        context.setLineWidth(width)
    }
    context.setStrokeColor(color)
    context.addArc(
        center: CGPoint(x: rect.midX, y: rect.midY),
        radius: rect.width / 2,
        startAngle: start * .pi / 180,
        endAngle: end * .pi / 180,
        clockwise: false
    )
    context.strokePath()
}

func strokeGradientArc(_ context: CGContext, rect: CGRect, start: CGFloat, end: CGFloat, width: CGFloat, colors: [CGColor]) {
    let steps = 90
    context.setLineWidth(width)
    context.setLineCap(.round)

    for index in 0..<steps {
        let first = CGFloat(index) / CGFloat(steps)
        let second = CGFloat(index + 1) / CGFloat(steps)
        let segmentStart = start + (end - start) * first
        let segmentEnd = start + (end - start) * second
        context.setStrokeColor(interpolatedColor(colors: colors, position: first))
        context.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: segmentStart * .pi / 180,
            endAngle: segmentEnd * .pi / 180,
            clockwise: false
        )
        context.strokePath()
    }
}

func interpolatedColor(colors: [CGColor], position: CGFloat) -> CGColor {
    guard colors.count > 1 else { return colors[0] }
    let clamped = min(max(position, 0), 1)
    let scaled = clamped * CGFloat(colors.count - 1)
    let lowerIndex = min(Int(floor(scaled)), colors.count - 2)
    let local = scaled - CGFloat(lowerIndex)
    let lower = colors[lowerIndex].components ?? [0, 0, 0, 1]
    let upper = colors[lowerIndex + 1].components ?? [0, 0, 0, 1]

    let red = lower[0] + (upper[0] - lower[0]) * local
    let green = lower[1] + (upper[1] - lower[1]) * local
    let blue = lower[2] + (upper[2] - lower[2]) * local
    let alpha = lower[3] + (upper[3] - lower[3]) * local
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha).cgColor
}

func drawSoftEllipse(_ context: CGContext, rect: CGRect, color: CGColor) {
    context.saveGState()
    context.setShadow(offset: .zero, blur: rect.width * 0.12, color: color)
    context.setFillColor(color)
    context.fillEllipse(in: rect)
    context.restoreGState()
}

func drawCenteredLetterC(_ context: CGContext, rect: CGRect, scale: CGFloat) {
    let fontSize = 314 * scale
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.13, green: 0.20, blue: 0.28, alpha: 0.92),
        .paragraphStyle: paragraph
    ]

    let letter = NSAttributedString(string: "C", attributes: attributes)
    let letterRect = CGRect(
        x: rect.minX,
        y: rect.midY - 182 * scale,
        width: rect.width,
        height: 380 * scale
    )

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    context.setShadow(
        offset: CGSize(width: 0, height: -3 * scale),
        blur: 16 * scale,
        color: NSColor(calibratedRed: 0.16, green: 0.38, blue: 0.56, alpha: 0.18).cgColor
    )
    letter.draw(in: letterRect)
    NSGraphicsContext.restoreGraphicsState()
}

func writePNG(image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    if CGImageDestinationFinalize(destination) == false {
        throw CocoaError(.fileWriteUnknown)
    }
}
