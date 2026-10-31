import AppKit
import ImageIO

/// Render the production artwork without starting the app or live monitoring.
/// Example: swiftc -parse-as-library <pixel-art.swift> <this-file.swift> -o <renderer>
@main
struct PersonalAgentGlyphRenderer {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw RenderError.outputRequired }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for kind in MacIslandPersonalAgentGlyph.allCases {
            let directory = output.appendingPathComponent(kind.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stem = kind == .muse ? "mac-island-muse-pixel" : "mac-island-grok-bot-pixel"
            try png(render(kind, time: nil)).write(to: output.appendingPathComponent("\(stem).png"))
            let frames = Int((kind.cycleDuration * 10).rounded())
            guard
                let gif = CGImageDestinationCreateWithURL(
                    output.appendingPathComponent("\(stem).gif") as CFURL,
                    "com.compuserve.gif" as CFString, frames, nil)
            else {
                throw RenderError.image
            }
            CGImageDestinationSetProperties(
                gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for index in 0..<frames {
                let name = String(format: "%03d.png", index)
                let image = try render(kind, time: Double(index) / 10)
                try png(image).write(to: directory.appendingPathComponent(name))
                CGImageDestinationAddImage(
                    gif, image,
                    [
                        kCGImagePropertyGIFDictionary: [
                            kCGImagePropertyGIFDelayTime: 0.1,
                            kCGImagePropertyGIFUnclampedDelayTime: 0.1,
                        ]
                    ] as CFDictionary)
            }
            guard CGImageDestinationFinalize(gif) else { throw RenderError.image }
        }
    }

    private static func render(_ kind: MacIslandPersonalAgentGlyph, time: TimeInterval?) throws -> CGImage {
        let size = 128
        guard
            let context = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw RenderError.context }
        context.setAllowsAntialiasing(false)
        // SwiftUI cells use a top-left origin; bitmap contexts start at the bottom.
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        let unit = CGFloat(size) / CGFloat(MacIslandPersonalAgentPixelArt.gridSize)
        for pixel in MacIslandPersonalAgentPixelArt.pixels(for: kind, at: time) {
            context.setFillColor(CGColor(red: pixel.red, green: pixel.green, blue: pixel.blue, alpha: 1))
            context.fill(CGRect(x: CGFloat(pixel.x) * unit, y: CGFloat(pixel.y) * unit, width: unit, height: unit))
        }
        guard let image = context.makeImage() else { throw RenderError.image }
        return image
    }

    private static func png(_ image: CGImage) throws -> Data {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw RenderError.image
        }
        return data
    }

    private enum RenderError: Error { case outputRequired, context, image }
}
