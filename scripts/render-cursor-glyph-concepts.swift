#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct RGB {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat

    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }

    func mixed(with other: RGB, amount: CGFloat) -> RGB {
        let t = min(1, max(0, amount))
        return RGB(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t
        )
    }

    func brightened(_ amount: CGFloat) -> RGB {
        mixed(with: RGB(0xFFFFFF), amount: amount)
    }

    private init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
    }

    var cgColor: CGColor {
        CGColor(red: r, green: g, blue: b, alpha: 1)
    }
}

private enum Concept: String, CaseIterable {
    case facetOrbit = "cursor-concept-a-facet-orbit"
    case prismTilt = "cursor-concept-b-prism-tilt"
    case aperturePulse = "cursor-concept-c-aperture-pulse"
}

private let logicalSize = 32
private let previewScale = 6
private let previewSize = logicalSize * previewScale
private let frameCount = 32
private let frameDelay = 0.055

private let background = RGB(0x050505)
private let border = RGB(0x343432)
private let facetPalette = [
    RGB(0xBCBCB8),
    RGB(0xF3F3F0),
    RGB(0x4C4C49),
    RGB(0x858581),
]

private func makeContext(width: Int, height: Int) -> CGContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setShouldAntialias(false)
    context.setAllowsAntialiasing(false)
    context.interpolationQuality = .none
    return context
}

private func fillPolygon(_ points: [CGPoint], color: RGB, in context: CGContext) {
    guard let first = points.first else { return }
    context.beginPath()
    context.move(to: first)
    for point in points.dropFirst() {
        context.addLine(to: point)
    }
    context.closePath()
    context.setFillColor(color.cgColor)
    context.fillPath()
}

private func tilePath(inset: CGFloat) -> [CGPoint] {
    let low = inset
    let high = CGFloat(logicalSize) - inset
    return [
        CGPoint(x: low + 5, y: low),
        CGPoint(x: high - 5, y: low),
        CGPoint(x: high - 2, y: low + 1),
        CGPoint(x: high, y: low + 4),
        CGPoint(x: high, y: high - 4),
        CGPoint(x: high - 2, y: high - 1),
        CGPoint(x: high - 5, y: high),
        CGPoint(x: low + 5, y: high),
        CGPoint(x: low + 2, y: high - 1),
        CGPoint(x: low, y: high - 4),
        CGPoint(x: low, y: low + 4),
        CGPoint(x: low + 2, y: low + 1),
    ]
}

private func drawTile(in context: CGContext) {
    fillPolygon(tilePath(inset: 2), color: border, in: context)
    fillPolygon(tilePath(inset: 3), color: background, in: context)
}

private enum Facet: Int, CaseIterable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft
}

private func drawCrystal(
    colors: [RGB],
    scaleX: CGFloat = 1,
    separation: Int = 0,
    in context: CGContext
) {
    precondition(colors.count == 4)
    let centerX = 16
    let centerY = 16

    for relativeY in -8...8 {
        let halfWidth = min(8, 9 - abs(relativeY))
        for relativeX in (-halfWidth)...halfWidth {
            let facet: Facet
            if relativeY <= 0 {
                facet = relativeX <= 0 ? .topLeft : .topRight
            } else {
                facet = relativeX > 0 ? .bottomRight : .bottomLeft
            }

            let horizontalDirection = facet == .topLeft || facet == .bottomLeft ? -1 : 1
            let verticalDirection = facet == .topLeft || facet == .topRight ? -1 : 1
            let x =
                centerX
                + Int(round(CGFloat(relativeX) * scaleX))
                + horizontalDirection * separation
            let y = centerY - relativeY - verticalDirection * separation
            context.setFillColor(colors[facet.rawValue].cgColor)
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
}

private func orbitColors(progress: CGFloat) -> [RGB] {
    let shifted = progress * 4
    let step = Int(floor(shifted))
    let blend = shifted - CGFloat(step)
    return Facet.allCases.map { facet in
        let current = (facet.rawValue - step + 16) % 4
        let next = (current - 1 + 4) % 4
        return facetPalette[current].mixed(with: facetPalette[next], amount: blend)
    }
}

private func renderLogicalFrame(concept: Concept, frame: Int) -> CGImage {
    let context = makeContext(width: logicalSize, height: logicalSize)
    context.setFillColor(RGB(0x111111).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: logicalSize, height: logicalSize))
    drawTile(in: context)

    let progress = CGFloat(frame) / CGFloat(frameCount)

    switch concept {
    case .facetOrbit:
        drawCrystal(
            colors: orbitColors(progress: progress),
            in: context
        )

    case .prismTilt:
        let tilt = (sin(progress * 2 * .pi) + 1) / 2
        let scaleX = 0.76 + 0.24 * tilt
        let highlight = (1 - scaleX) * 0.45
        let colors = facetPalette.enumerated().map { index, color in
            (index == 1 || index == 2) ? color.brightened(highlight) : color
        }
        drawCrystal(
            colors: colors,
            scaleX: scaleX,
            in: context
        )

    case .aperturePulse:
        let openness = (sin(progress * 2 * .pi - .pi / 2) + 1) / 2
        let separation = openness > 0.46 ? 1 : 0
        let colors = [
            facetPalette[0].brightened(openness * 0.08),
            facetPalette[1],
            facetPalette[2].brightened(openness * 0.05),
            facetPalette[3].brightened(openness * 0.08),
        ]
        drawCrystal(
            colors: colors,
            separation: separation,
            in: context
        )
    }

    return context.makeImage()!
}

private func scaled(_ image: CGImage, scale: Int) -> CGImage {
    let width = image.width * scale
    let height = image.height * scale
    let context = makeContext(width: width, height: height)
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func combined(_ images: [CGImage]) -> CGImage {
    let context = makeContext(width: previewSize * images.count, height: previewSize)
    context.setFillColor(RGB(0x111111).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: previewSize * images.count, height: previewSize))
    for (index, image) in images.enumerated() {
        context.draw(
            image,
            in: CGRect(x: index * previewSize, y: 0, width: previewSize, height: previewSize)
        )
    }
    return context.makeImage()!
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw NSError(domain: "CursorConceptRenderer", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "CursorConceptRenderer", code: 2)
    }
}

private func writeGIF(_ frames: [CGImage], to url: URL) throws {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        )
    else {
        throw NSError(domain: "CursorConceptRenderer", code: 3)
    }

    CGImageDestinationSetProperties(
        destination,
        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
    )
    let properties =
        [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime: frameDelay,
            ]
        ] as CFDictionary
    for frame in frames {
        CGImageDestinationAddImage(destination, frame, properties)
    }
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "CursorConceptRenderer", code: 4)
    }
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: render-cursor-glyph-concepts.swift <output-directory>\n", stderr)
    exit(64)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

private var previewFramesByConcept: [Concept: [CGImage]] = [:]
for concept in Concept.allCases {
    let logicalFrames = (0..<frameCount).map { renderLogicalFrame(concept: concept, frame: $0) }
    let previewFrames = logicalFrames.map { scaled($0, scale: previewScale) }
    previewFramesByConcept[concept] = previewFrames

    try writeGIF(
        previewFrames,
        to: outputDirectory.appendingPathComponent("\(concept.rawValue).gif")
    )
    try writePNG(
        logicalFrames[0],
        to: outputDirectory.appendingPathComponent("\(concept.rawValue)-actual-32px.png")
    )
    let motionSheet = combined([0, 5, 10, 16, 21, 26].map { previewFrames[$0] })
    try writePNG(
        motionSheet,
        to: outputDirectory.appendingPathComponent("\(concept.rawValue)-motion-sheet.png")
    )
}

let combinedFrames = (0..<frameCount).map { frame in
    combined(Concept.allCases.compactMap { previewFramesByConcept[$0]?[frame] })
}
try writeGIF(
    combinedFrames,
    to: outputDirectory.appendingPathComponent("cursor-concepts-comparison.gif")
)
try writePNG(
    combinedFrames[0],
    to: outputDirectory.appendingPathComponent("cursor-concepts-comparison.png")
)

print("Rendered \(Concept.allCases.count) concepts to \(outputDirectory.path)")
