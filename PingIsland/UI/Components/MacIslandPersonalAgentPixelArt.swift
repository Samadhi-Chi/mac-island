import Foundation

nonisolated enum MacIslandPersonalAgentGlyph: String, CaseIterable, Sendable {
    case muse, grokBot

    var cycleDuration: TimeInterval { self == .muse ? 3.2 : 4.2 }
}

/// Original 16-cell artwork. Both the native view and exported previews consume
/// these frames; there are no third-party icon assets or UI-state dependencies.
nonisolated struct MacIslandPersonalAgentPixel: Identifiable, Equatable, Sendable {
    let x: Int
    let y: Int
    let red: Double
    let green: Double
    let blue: Double
    var isDetail: Bool = false
    var id: Int { y * MacIslandPersonalAgentPixelArt.gridSize + x }
}

nonisolated enum MacIslandPersonalAgentPixelArt {
    static let gridSize = 16

    static func pixels(for kind: MacIslandPersonalAgentGlyph, at time: TimeInterval? = nil)
        -> [MacIslandPersonalAgentPixel]
    {
        let phase = time.flatMap { value -> Double? in
            guard value.isFinite else { return nil }
            let cycle = kind.cycleDuration
            return ((value.truncatingRemainder(dividingBy: cycle) + cycle).truncatingRemainder(dividingBy: cycle))
                / cycle
        }
        switch kind {
        case .muse: return muse(phase: phase)
        case .grokBot: return grok(phase: phase)
        }
    }

    private static func muse(phase: Double?) -> [MacIslandPersonalAgentPixel] {
        // A stepped M with a slight handwritten slant. Two-cell strokes leave
        // clear negative space and keep the small native mark easy to read.
        let points = [(2, 12), (3, 3), (7, 8), (12, 3), (11, 12)]
        var cells = Set<Int>()
        for index in 1..<points.count {
            cells.formUnion(stroke(from: points[index - 1], to: points[index]))
        }
        return cells.sorted().map { id in
            let x = id % gridSize
            let y = id / gridSize
            let base: (Double, Double, Double) = y >= 11 ? (0.055, 0.290, 0.825) : (0.055, 0.420, 0.965)
            let highlight: Double =
                phase.map { progress -> Double in
                    // Light crosses the fixed silhouette; geometry never scales or
                    // rotates. Both ends of the loop settle to the resting blue.
                    let center = -4.0 + progress * 24.0
                    let distance = abs(Double(x) - center)
                    return max(0.0, 1.0 - distance / 3.0) * 0.62
                } ?? 0
            return .init(
                x: x, y: y,
                red: base.0 + (0.45 - base.0) * highlight,
                green: base.1 + (0.76 - base.1) * highlight,
                blue: base.2 + (1 - base.2) * highlight)
        }
    }

    private static func grok(phase: Double?) -> [MacIslandPersonalAgentPixel] {
        var cells: [Int: MacIslandPersonalAgentPixel] = [:]
        for y in 2...13 {
            for x in 2...13 {
                let radius = pow((Double(x) - 7.5) / 6.1, 2) + pow((Double(y) - 7.5) / 6.1, 2)
                guard radius <= 1 else { continue }
                let tone: (Double, Double, Double)
                if radius > 0.78 {
                    tone = (0.48, 0.50, 0.54)
                } else if x >= 10 || y >= 11 {
                    tone = (0.64, 0.66, 0.70)
                } else {
                    tone = (0.81, 0.82, 0.84)
                }
                let pixel = MacIslandPersonalAgentPixel(x: x, y: y, red: tone.0, green: tone.1, blue: tone.2)
                cells[pixel.id] = pixel
            }
        }
        let shift = grokLookOffset(phase: phase)
        // Two short diagonal cuts, no pupils, mouth, shine or component plate.
        for id in stroke(from: (5 + shift, 6), to: (6 + shift, 9))
            .union(stroke(from: (9 + shift, 4), to: (10 + shift, 7))) where cells[id] != nil
        {
            cells[id] = .init(
                x: id % gridSize, y: id / gridSize,
                red: 0.105, green: 0.110, blue: 0.125, isDetail: true)
        }
        return cells.values.sorted { $0.id < $1.id }
    }

    private static func grokLookOffset(phase: Double?) -> Int {
        guard let phase else { return 0 }
        if (0.30..<0.44).contains(phase) { return 1 }
        if (0.68..<0.82).contains(phase) { return -1 }
        return 0
    }

    private static func stroke(from start: (Int, Int), to end: (Int, Int)) -> Set<Int> {
        var result = Set<Int>()
        var x = start.0
        var y = start.1
        let dx = abs(end.0 - x)
        let dy = -abs(end.1 - y)
        let sx = x < end.0 ? 1 : -1
        let sy = y < end.1 ? 1 : -1
        var error = dx + dy
        while true {
            for py in y..<(y + 2) where (0..<gridSize).contains(py) {
                for px in x..<(x + 2) where (0..<gridSize).contains(px) { result.insert(py * gridSize + px) }
            }
            if x == end.0 && y == end.1 { break }
            let twice = 2 * error
            if twice >= dy {
                error += dy
                x += sx
            }
            if twice <= dx {
                error += dx
                y += sy
            }
        }
        return result
    }
}
