import SwiftUI

enum MacIslandClientGlyphKind: Equatable {
    case codex
    case cursor
    case claudeCode
    case openCode
    case hermes
    case dsh
    case muse
    case grokBot
    case fallback

    nonisolated init(session: SessionState) {
        if session.provider == .codex {
            self = .codex
        } else if MacIslandProductPolicy.isCursorClient(session.clientInfo) {
            self = .cursor
        } else if session.clientInfo.isDSHClient {
            self = .dsh
        } else if session.clientInfo.isOpenCodeClient {
            self = .openCode
        } else if session.clientInfo.isHermesClient {
            self = .hermes
        } else if session.clientInfo.isClaudeCodeClient {
            self = .claudeCode
        } else {
            self = .fallback
        }
    }

    nonisolated init(personalAgent: PersonalAgentClient) {
        switch personalAgent {
        case .muse: self = .muse
        case .grokBot: self = .grokBot
        case .dot: self = .fallback
        }
    }
}

/// Small code-drawn client marks for Mac Island. These deliberately avoid
/// bundling or copying third-party icon assets while retaining a recognizable
/// stepped-tile / faceted-crystal visual language.
struct MacIslandClientGlyphView: View {
    let kind: MacIslandClientGlyphKind
    let status: MascotStatus
    var size: CGFloat = 24
    /// Presentation-only hover feedback for Personal Agents. It never means
    /// their execution state is known or that they are working.
    var interactionActive = false

    @ObservedObject private var energyGovernor = EnergyGovernor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if shouldAnimateGlyph {
                TimelineView(.animation(minimumInterval: glyphAnimationInterval)) { context in
                    glyph(animationTime: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                glyph(animationTime: nil)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func glyph(animationTime: TimeInterval?) -> some View {
        switch kind {
        case .codex:
            codexGlyph(time: animationTime)
        case .cursor:
            cursorGlyph(time: animationTime)
        case .claudeCode:
            claudeGlyph(time: animationTime)
        case .openCode:
            openCodeGlyph(time: animationTime)
        case .hermes:
            hermesGlyph(time: animationTime)
        case .dsh:
            dshGlyph(time: animationTime)
        case .muse:
            personalAgentGlyph(.muse, time: animationTime)
        case .grokBot:
            personalAgentGlyph(.grokBot, time: animationTime)
        case .fallback:
            fallbackGlyph
        }
    }

    private func personalAgentGlyph(_ client: MacIslandPersonalAgentGlyph, time: TimeInterval?) -> some View {
        let pixel = size / CGFloat(MacIslandPersonalAgentPixelArt.gridSize)
        return ZStack(alignment: .topLeading) {
            ForEach(MacIslandPersonalAgentPixelArt.pixels(for: client, at: time)) { cell in
                Rectangle()
                    .fill(Color(red: cell.red, green: cell.green, blue: cell.blue))
                    .frame(width: pixel, height: pixel)
                    .offset(x: CGFloat(cell.x) * pixel, y: CGFloat(cell.y) * pixel)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
    }

    private func codexGlyph(time: TimeInterval?) -> some View {
        let pixel = max(1, floor(size / 11))
        let darkBlue = Color(red: 0.039, green: 0.451, blue: 0.969)
        let lightBlue = Color(red: 0.133, green: 0.780, blue: 0.937)
        let gridSize = pixel * 11
        let rotation = time.map(MacIslandCodexPixelMotion.rotationDegrees(at:)) ?? 0
        let scale = time.map(MacIslandCodexPixelMotion.scale(at:)) ?? 1
        let breathingOpacity = time.map(MacIslandCodexPixelMotion.breathingOpacity(at:)) ?? 1

        return ZStack(alignment: .topLeading) {
            ForEach(0..<4, id: \.self) { index in
                MacIslandCodexSteppedTileShape()
                    .fill(
                        MacIslandCodexPixelMotion.usesDarkColor(tileIndex: index)
                            ? darkBlue
                            : lightBlue
                    )
                    .frame(width: pixel * 5, height: pixel * 5)
                    .opacity(
                        time.map {
                            MacIslandCodexPixelMotion.opacity(tileIndex: index, at: $0)
                        } ?? 1
                    )
                    .offset(
                        x: CGFloat(index % 2) * pixel * 6,
                        y: CGFloat(index / 2) * pixel * 6
                    )
            }
        }
        .frame(width: gridSize, height: gridSize, alignment: .topLeading)
        .rotationEffect(.degrees(rotation))
        .scaleEffect(scale)
        .opacity(breathingOpacity)
        .frame(width: size, height: size)
    }

    private func cursorGlyph(time: TimeInterval?) -> some View {
        let pixel = size / CGFloat(MacIslandCursorPixelArt.gridSize)
        let openness = time.map(MacIslandCursorPixelMotion.openness(at:)) ?? 0
        let separation = time.map(MacIslandCursorPixelMotion.separation(at:)) ?? 0
        let scale = time.map(MacIslandCursorPixelMotion.scale(at:)) ?? 1
        let cells = MacIslandCursorPixelArt.cells(separation: separation)

        return ZStack(alignment: .topLeading) {
            ForEach(cells) { cell in
                Rectangle()
                    .fill(cursorFacetColor(for: cell.facet, openness: openness))
                    .frame(width: pixel, height: pixel)
                    .offset(
                        x: CGFloat(cell.x) * pixel,
                        y: CGFloat(cell.y) * pixel
                    )
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .scaleEffect(scale)
    }

    private func cursorFacetColor(
        for facet: MacIslandCursorFacet,
        openness: Double
    ) -> Color {
        let base: (red: Double, green: Double, blue: Double)
        let maximumBrightening: Double
        switch facet {
        case .topLeft:
            base = (0.737, 0.737, 0.722)
            maximumBrightening = 0.08
        case .topRight:
            base = (0.953, 0.953, 0.941)
            maximumBrightening = 0
        case .bottomRight:
            base = (0.298, 0.298, 0.286)
            maximumBrightening = 0.05
        case .bottomLeft:
            base = (0.522, 0.522, 0.506)
            maximumBrightening = 0.08
        }

        let amount = min(1, max(0, openness)) * maximumBrightening
        return Color(
            red: base.red + (1 - base.red) * amount,
            green: base.green + (1 - base.green) * amount,
            blue: base.blue + (1 - base.blue) * amount
        )
    }

    private func claudeGlyph(time: TimeInterval?) -> some View {
        let motion = time.map(MacIslandClaudeGlyphMotion.state(at:)) ?? .staticState
        let lightCoral = Color(red: 0.910, green: 0.475, blue: 0.357)
        let darkCoral = Color(red: 0.663, green: 0.275, blue: 0.204)

        return ZStack(alignment: .topLeading) {
            ForEach(0..<MacIslandClaudePixelArt.rayCount, id: \.self) { rayIndex in
                ZStack(alignment: .topLeading) {
                    ForEach(
                        Array(MacIslandClaudePixelArt.segments(forRay: rayIndex).enumerated()),
                        id: \.offset
                    ) { _, segment in
                        pixelRectangle(
                            segment,
                            color: rayIndex.isMultiple(of: 2) ? lightCoral : darkCoral
                        )
                    }
                }
                .frame(width: 64, height: 64, alignment: .topLeading)
                .scaleEffect(x: 1, y: motion.rayScaleY, anchor: .center)
                .offset(y: motion.rayTranslationY)
                .opacity(motion.rayOpacity)
                .rotationEffect(.degrees(Double(rayIndex) * 30))
            }

            pixelRectangle(MacIslandClaudePixelArt.core, color: lightCoral)
                .scaleEffect(motion.coreScale)
                .opacity(motion.coreOpacity)
        }
        .frame(width: 64, height: 64, alignment: .topLeading)
        .scaleEffect(size / 64)
        .frame(width: size, height: size)
    }

    private func openCodeGlyph(time: TimeInterval?) -> some View {
        let motion = time.map(MacIslandOpenCodeGlyphMotion.state(at:)) ?? .staticState

        return ZStack(alignment: .topLeading) {
            openCodeBracket(MacIslandOpenCodePixelArt.leftBracket)
                .offset(x: motion.leftTranslationX)
            openCodeBracket(MacIslandOpenCodePixelArt.rightBracket)
                .offset(x: motion.rightTranslationX)
        }
        .frame(width: 64, height: 64, alignment: .topLeading)
        .scaleEffect(size / 64)
        .frame(width: size, height: size)
    }

    private func openCodeBracket(_ pixels: [MacIslandOpenCodePixel]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(pixels.enumerated()), id: \.offset) { _, pixel in
                pixelRectangle(pixel.rect, color: openCodeColor(pixel.tone))
            }
        }
        .frame(width: 64, height: 64, alignment: .topLeading)
    }

    private func hermesGlyph(time: TimeInterval?) -> some View {
        let motion = time.map(MacIslandHermesGlyphMotion.state(at:)) ?? .staticState
        let purple = Color(red: 0.545, green: 0.361, blue: 0.965)
        let lightPurple = Color(red: 0.769, green: 0.710, blue: 0.992)
        let darkPurple = Color(red: 0.357, green: 0.129, blue: 0.714)
        let phonePurple = Color(red: 0.655, green: 0.545, blue: 0.980)
        let phoneDarkPurple = Color(red: 0.427, green: 0.157, blue: 0.851)

        return ZStack(alignment: .topLeading) {
            pixelRectangle(.init(x: 23, y: 14, width: 18, height: 5), color: lightPurple)
            pixelRectangle(.init(x: 18, y: 19, width: 28, height: 6), color: purple)
            pixelRectangle(.init(x: 15, y: 25, width: 8, height: 20), color: purple)
            pixelRectangle(.init(x: 41, y: 25, width: 8, height: 20), color: darkPurple)
            pixelRectangle(.init(x: 18, y: 42, width: 9, height: 7), color: lightPurple)
            pixelRectangle(.init(x: 37, y: 42, width: 9, height: 7), color: purple)
            pixelRectangle(.init(x: 23, y: 23, width: 7, height: 6), color: darkPurple)
            pixelRectangle(.init(x: 35, y: 23, width: 7, height: 6), color: darkPurple)

            ZStack(alignment: .topLeading) {
                ForEach(
                    Array(MacIslandHermesPixelArt.facialFeatures.enumerated()),
                    id: \.offset
                ) { _, eye in
                    pixelRectangle(
                        .init(
                            x: eye.x - MacIslandHermesPixelArt.eyeBounds.x,
                            y: eye.y - MacIslandHermesPixelArt.eyeBounds.y,
                            width: eye.width,
                            height: eye.height
                        ),
                        color: lightPurple
                    )
                }
            }
            .frame(
                width: MacIslandHermesPixelArt.eyeBounds.width,
                height: MacIslandHermesPixelArt.eyeBounds.height,
                alignment: .topLeading
            )
            .scaleEffect(
                x: motion.eyeScaleX,
                y: motion.eyeScaleY,
                anchor: .center
            )
            .offset(
                x: MacIslandHermesPixelArt.eyeBounds.x,
                y: MacIslandHermesPixelArt.eyeBounds.y + motion.eyeTranslationY
            )

            ZStack(alignment: .topLeading) {
                pixelRectangle(.init(x: 9, y: 19, width: 5, height: 10), color: phoneDarkPurple)
                pixelRectangle(.init(x: 6, y: 29, width: 7, height: 15), color: phonePurple)
                pixelRectangle(.init(x: 50, y: 19, width: 5, height: 10), color: phoneDarkPurple)
                pixelRectangle(.init(x: 51, y: 29, width: 7, height: 15), color: phonePurple)
                pixelRectangle(.init(x: 14, y: 11, width: 6, height: 5), color: lightPurple)
                pixelRectangle(.init(x: 20, y: 7, width: 24, height: 5), color: lightPurple)
                pixelRectangle(.init(x: 44, y: 11, width: 6, height: 5), color: lightPurple)
            }
            .frame(width: 64, height: 64, alignment: .topLeading)
            .offset(y: motion.headphoneTranslationY)
        }
        .frame(width: 64, height: 64, alignment: .topLeading)
        .scaleEffect(size / 64)
        .frame(width: size, height: size)
    }

    /// An original, code-drawn blue wave mark for DeepSeek Harness. It keeps the
    /// pixel language used by Mac Island without embedding DeepSeek artwork.
    private func dshGlyph(time: TimeInterval?) -> some View {
        let motion = time.map(MacIslandDSHGlyphMotion.state(at:)) ?? .staticState
        let deepBlue = Color(red: 0.075, green: 0.345, blue: 0.950)
        let blue = Color(red: 0.075, green: 0.610, blue: 0.980)
        let cyan = Color(red: 0.180, green: 0.820, blue: 0.980)

        return ZStack(alignment: .topLeading) {
            pixelRectangle(.init(x: 8, y: 25, width: 8, height: 8), color: cyan)
                .offset(y: motion.waveOffset(index: 0))
            pixelRectangle(.init(x: 8, y: 35, width: 8, height: 8), color: deepBlue)
                .offset(y: motion.waveOffset(index: 1))
            pixelRectangle(.init(x: 16, y: 20, width: 30, height: 8), color: blue)
                .offset(y: motion.waveOffset(index: 2))
            pixelRectangle(.init(x: 16, y: 30, width: 38, height: 8), color: cyan)
                .offset(y: motion.waveOffset(index: 3))
            pixelRectangle(.init(x: 20, y: 40, width: 26, height: 8), color: deepBlue)
                .offset(y: motion.waveOffset(index: 4))
            pixelRectangle(.init(x: 46, y: 22, width: 8, height: 8), color: deepBlue)
                .offset(y: motion.waveOffset(index: 5))
        }
        .frame(width: 64, height: 64, alignment: .topLeading)
        .scaleEffect(motion.scale)
        .opacity(motion.opacity)
        .scaleEffect(size / 64)
        .frame(width: size, height: size)
    }

    private func pixelRectangle(
        _ rect: MacIslandPixelRect,
        color: Color
    ) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.x, y: rect.y)
    }

    private func openCodeColor(_ tone: MacIslandOpenCodeTone) -> Color {
        switch tone {
        case .light:
            Color(red: 0.957, green: 0.957, blue: 0.961)
        case .mid:
            Color(red: 0.651, green: 0.651, blue: 0.678)
        case .dark:
            Color(red: 0.290, green: 0.290, blue: 0.314)
        }
    }

    private var fallbackGlyph: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Color.white.opacity(status == .warning ? 0.82 : 0.48))
            .frame(width: size * 0.42, height: size * 0.42)
    }

    private var shouldAnimateGlyph: Bool {
        MacIslandClientGlyphMotionPolicy.shouldAnimate(
            kind: kind,
            status: status,
            reduceMotion: reduceMotion,
            animationLevel: energyGovernor.policy.animationLevel,
            interactionActive: interactionActive
        )
    }

    private var glyphAnimationInterval: TimeInterval {
        switch energyGovernor.policy.animationLevel {
        case .full:
            (kind == .muse || kind == .grokBot) ? 1 / 16 : MacIslandCodexPixelMotion.fullFrameInterval
        case .reduced:
            (kind == .muse || kind == .grokBot)
                ? max(1 / 8, MacIslandCodexPixelMotion.reducedFrameInterval)
                : MacIslandCodexPixelMotion.reducedFrameInterval
        case .staticFrames:
            MacIslandCodexPixelMotion.fullFrameInterval
        }
    }

    private var accessibilityLabel: Text {
        let client =
            switch kind {
            case .codex: "Codex"
            case .cursor: "Cursor"
            case .claudeCode: "Claude Code"
            case .openCode: "OpenCode"
            case .hermes: "Hermes"
            case .dsh: "DeepSeek Harness"
            case .muse: "Muse"
            case .grokBot: "Grok Bot"
            case .fallback: "Agent"
            }
        return Text(kind == .muse || kind == .grokBot ? "\(client) pixel icon" : "\(client) pixel status icon")
    }
}

private struct MacIslandCodexSteppedTileShape: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 5
        let points = MacIslandCodexPixelMotion.unitOutline.map {
            CGPoint(x: $0.x * unit, y: $0.y * unit)
        }

        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

enum MacIslandClientGlyphMotionPolicy {
    static func shouldAnimate(
        kind: MacIslandClientGlyphKind,
        status: MascotStatus,
        reduceMotion: Bool,
        animationLevel: EnergyAnimationLevel,
        interactionActive: Bool = false
    ) -> Bool {
        guard kind != .fallback,
            !reduceMotion,
            animationLevel != .staticFrames
        else {
            return false
        }
        if kind == .muse || kind == .grokBot { return interactionActive }
        return status == .working
    }
}

struct MacIslandDSHGlyphMotionState: Equatable, Sendable {
    let phase: Double
    let scale: CGFloat
    let opacity: Double

    nonisolated static let staticState = MacIslandDSHGlyphMotionState(
        phase: 0,
        scale: 1,
        opacity: 1
    )

    nonisolated func waveOffset(index: Int) -> CGFloat {
        CGFloat(sin(phase + Double(index) * 0.72) * 1.8)
    }
}

enum MacIslandDSHGlyphMotion {
    nonisolated static let cycleDuration: TimeInterval = 2.6

    nonisolated static func state(at time: TimeInterval) -> MacIslandDSHGlyphMotionState {
        guard time.isFinite else { return .staticState }
        let phase = (time.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration) * 2 * Double.pi
        return MacIslandDSHGlyphMotionState(
            phase: phase,
            scale: 0.98 + CGFloat((sin(phase) + 1) * 0.012),
            opacity: 0.88 + (sin(phase - 0.4) + 1) * 0.06
        )
    }
}

struct MacIslandPixelRect: Equatable, Sendable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

enum MacIslandClaudePixelArt {
    nonisolated static let rayCount = 12
    nonisolated static let core = MacIslandPixelRect(x: 28, y: 28, width: 8, height: 8)

    private nonisolated static let rayPatterns: [[MacIslandPixelRect]] = [
        [
            .init(x: 29, y: 5, width: 6, height: 7),
            .init(x: 29, y: 14, width: 6, height: 6),
            .init(x: 29, y: 22, width: 6, height: 5),
        ],
        [
            .init(x: 29, y: 10, width: 6, height: 6),
            .init(x: 29, y: 18, width: 6, height: 5),
            .init(x: 29, y: 25, width: 6, height: 3),
        ],
        [
            .init(x: 29, y: 7, width: 6, height: 6),
            .init(x: 29, y: 15, width: 6, height: 6),
            .init(x: 29, y: 23, width: 6, height: 4),
        ],
        [
            .init(x: 29, y: 4, width: 6, height: 8),
            .init(x: 29, y: 14, width: 6, height: 6),
            .init(x: 29, y: 22, width: 6, height: 5),
        ],
        [
            .init(x: 29, y: 11, width: 6, height: 5),
            .init(x: 29, y: 18, width: 6, height: 5),
            .init(x: 29, y: 25, width: 6, height: 3),
        ],
        [
            .init(x: 29, y: 7, width: 6, height: 6),
            .init(x: 29, y: 15, width: 6, height: 6),
            .init(x: 29, y: 23, width: 6, height: 4),
        ],
    ]

    nonisolated static func segments(forRay index: Int) -> [MacIslandPixelRect] {
        guard !rayPatterns.isEmpty else { return [] }
        let normalizedIndex = ((index % rayPatterns.count) + rayPatterns.count) % rayPatterns.count
        return rayPatterns[normalizedIndex]
    }
}

struct MacIslandClaudeGlyphMotionState: Equatable, Sendable {
    let rayTranslationY: CGFloat
    let rayScaleY: CGFloat
    let rayOpacity: Double
    let coreScale: CGFloat
    let coreOpacity: Double

    nonisolated static let staticState = MacIslandClaudeGlyphMotionState(
        rayTranslationY: 0,
        rayScaleY: 1,
        rayOpacity: 1,
        coreScale: 1,
        coreOpacity: 1
    )
}

enum MacIslandClaudeGlyphMotion {
    nonisolated static let cycleDuration: TimeInterval = 2.9

    nonisolated static func state(at time: TimeInterval) -> MacIslandClaudeGlyphMotionState {
        guard time.isFinite else { return .staticState }
        let progress = MacIslandGlyphMotionMath.normalizedProgress(
            at: time,
            duration: cycleDuration
        )
        return MacIslandClaudeGlyphMotionState(
            rayTranslationY: CGFloat(
                MacIslandGlyphMotionMath.interpolate(
                    progress,
                    keyframes: [(0, 0), (0.45, 9), (0.55, 9), (0.72, -0.5), (1, 0)]
                )),
            rayScaleY: CGFloat(
                MacIslandGlyphMotionMath.interpolate(
                    progress,
                    keyframes: [(0, 1), (0.45, 0.42), (0.55, 0.42), (0.72, 1.03), (1, 1)]
                )),
            rayOpacity: MacIslandGlyphMotionMath.interpolate(
                progress,
                keyframes: [(0, 1), (0.45, 0.68), (0.55, 0.68), (0.72, 1), (1, 1)]
            ),
            coreScale: CGFloat(
                MacIslandGlyphMotionMath.interpolate(
                    progress,
                    keyframes: [
                        (0, 0.8), (0.38, 0.8), (0.51, 0.62),
                        (0.66, 1.25), (0.82, 0.94), (1, 0.8),
                    ]
                )),
            coreOpacity: MacIslandGlyphMotionMath.interpolate(
                progress,
                keyframes: [
                    (0, 0.68), (0.38, 0.68), (0.51, 0.48),
                    (0.66, 1), (0.82, 0.86), (1, 0.68),
                ]
            )
        )
    }
}

enum MacIslandOpenCodeTone: Hashable, Sendable {
    case light
    case mid
    case dark
}

struct MacIslandOpenCodePixel: Equatable, Sendable {
    let rect: MacIslandPixelRect
    let tone: MacIslandOpenCodeTone
}

enum MacIslandOpenCodePixelArt {
    nonisolated static let leftBracket = [
        MacIslandOpenCodePixel(rect: .init(x: 7, y: 13, width: 8, height: 38), tone: .dark),
        MacIslandOpenCodePixel(rect: .init(x: 15, y: 9, width: 14, height: 8), tone: .light),
        MacIslandOpenCodePixel(rect: .init(x: 15, y: 47, width: 14, height: 8), tone: .mid),
        MacIslandOpenCodePixel(rect: .init(x: 15, y: 18, width: 6, height: 8), tone: .mid),
        MacIslandOpenCodePixel(rect: .init(x: 15, y: 38, width: 6, height: 8), tone: .dark),
    ]

    nonisolated static let rightBracket = [
        MacIslandOpenCodePixel(rect: .init(x: 49, y: 13, width: 8, height: 38), tone: .dark),
        MacIslandOpenCodePixel(rect: .init(x: 35, y: 9, width: 14, height: 8), tone: .mid),
        MacIslandOpenCodePixel(rect: .init(x: 35, y: 47, width: 14, height: 8), tone: .light),
        MacIslandOpenCodePixel(rect: .init(x: 43, y: 18, width: 6, height: 8), tone: .dark),
        MacIslandOpenCodePixel(rect: .init(x: 43, y: 38, width: 6, height: 8), tone: .mid),
    ]
}

struct MacIslandOpenCodeGlyphMotionState: Equatable, Sendable {
    let leftTranslationX: CGFloat
    let rightTranslationX: CGFloat

    nonisolated static let staticState = MacIslandOpenCodeGlyphMotionState(
        leftTranslationX: 0,
        rightTranslationX: 0
    )
}

enum MacIslandOpenCodeGlyphMotion {
    nonisolated static let cycleDuration: TimeInterval = 1.65

    nonisolated static func state(at time: TimeInterval) -> MacIslandOpenCodeGlyphMotionState {
        guard time.isFinite else { return .staticState }
        let progress = MacIslandGlyphMotionMath.normalizedProgress(
            at: time,
            duration: cycleDuration
        )
        let inwardProgress = (1 - cos(2 * Double.pi * progress)) / 2
        return MacIslandOpenCodeGlyphMotionState(
            leftTranslationX: CGFloat(-5 + 9 * inwardProgress),
            rightTranslationX: CGFloat(5 - 9 * inwardProgress)
        )
    }
}

enum MacIslandHermesPixelArt {
    nonisolated static let facialFeatures = [
        MacIslandPixelRect(x: 25, y: 31, width: 4, height: 5),
        MacIslandPixelRect(x: 36, y: 31, width: 4, height: 5),
    ]
    nonisolated static let eyeBounds = MacIslandPixelRect(x: 25, y: 31, width: 15, height: 5)
}

enum MacIslandHermesEyePhase: Equatable, Sendable {
    case open
    case halfClosed
    case closed
}

struct MacIslandHermesGlyphMotionState: Equatable, Sendable {
    let eyePhase: MacIslandHermesEyePhase
    let eyeScaleX: CGFloat
    let eyeScaleY: CGFloat
    let eyeTranslationY: CGFloat
    let headphoneTranslationY: CGFloat

    nonisolated static let staticState = MacIslandHermesGlyphMotionState(
        eyePhase: .open,
        eyeScaleX: 1,
        eyeScaleY: 1,
        eyeTranslationY: 0,
        headphoneTranslationY: 0
    )
}

enum MacIslandHermesGlyphMotion {
    nonisolated static let blinkCycleDuration: TimeInterval = 4.6
    nonisolated static let headphoneCycleDuration: TimeInterval = 1.8

    nonisolated static func state(at time: TimeInterval) -> MacIslandHermesGlyphMotionState {
        guard time.isFinite else { return .staticState }
        let blinkProgress = MacIslandGlyphMotionMath.normalizedProgress(
            at: time,
            duration: blinkCycleDuration
        )
        let phase = eyePhase(at: blinkProgress)
        let eyeTransform: (x: CGFloat, y: CGFloat, translationY: CGFloat) =
            switch phase {
            case .open:
                (1, 1, 0)
            case .halfClosed:
                (1.15, 0.6, 0.5)
            case .closed:
                (1.35, 0.16, 1)
            }
        let headphoneProgress = MacIslandGlyphMotionMath.normalizedProgress(
            at: time,
            duration: headphoneCycleDuration
        )
        let headphoneTranslation = CGFloat(
            -0.5 - 1.5 * cos(2 * Double.pi * headphoneProgress)
        )

        return MacIslandHermesGlyphMotionState(
            eyePhase: phase,
            eyeScaleX: eyeTransform.x,
            eyeScaleY: eyeTransform.y,
            eyeTranslationY: eyeTransform.translationY,
            headphoneTranslationY: headphoneTranslation
        )
    }

    private nonisolated static func eyePhase(at progress: Double) -> MacIslandHermesEyePhase {
        if (0.62..<0.64).contains(progress)
            || (0.68..<0.70).contains(progress)
            || (0.80..<0.82).contains(progress)
            || (0.86..<0.87).contains(progress)
        {
            return .halfClosed
        }
        if (0.64..<0.68).contains(progress)
            || (0.82..<0.86).contains(progress)
        {
            return .closed
        }
        return .open
    }
}

private enum MacIslandGlyphMotionMath {
    nonisolated static func normalizedProgress(
        at time: TimeInterval,
        duration: TimeInterval
    ) -> Double {
        guard time.isFinite, duration > 0 else { return 0 }
        let remainder = time.truncatingRemainder(dividingBy: duration)
        return (remainder < 0 ? remainder + duration : remainder) / duration
    }

    nonisolated static func interpolate(
        _ progress: Double,
        keyframes: [(progress: Double, value: Double)]
    ) -> Double {
        guard let first = keyframes.first else { return 0 }
        guard progress > first.progress else { return first.value }

        for index in 1..<keyframes.count {
            let previous = keyframes[index - 1]
            let next = keyframes[index]
            guard progress <= next.progress else { continue }
            let span = next.progress - previous.progress
            guard span > 0 else { return next.value }
            let linear = min(1, max(0, (progress - previous.progress) / span))
            let eased = (1 - cos(Double.pi * linear)) / 2
            return previous.value + (next.value - previous.value) * eased
        }

        return keyframes.last?.value ?? first.value
    }
}

enum MacIslandCodexPixelMotion {
    nonisolated static let cycleDuration: TimeInterval = 3.6
    nonisolated static let fullFrameInterval: TimeInterval = 1.0 / 30.0
    nonisolated static let reducedFrameInterval: TimeInterval = 1.0 / 15.0
    nonisolated static let minimumOpacity = 0.68
    nonisolated static let minimumScale = 0.94
    nonisolated static let maximumScale = 1.04
    nonisolated static let minimumBreathingOpacity = 0.88

    nonisolated static let tileRows = [
        ".###.",
        "#####",
        "#####",
        "#####",
        ".###.",
    ]

    nonisolated static let unitOutline = [
        CGPoint(x: 1, y: 0),
        CGPoint(x: 4, y: 0),
        CGPoint(x: 4, y: 1),
        CGPoint(x: 5, y: 1),
        CGPoint(x: 5, y: 4),
        CGPoint(x: 4, y: 4),
        CGPoint(x: 4, y: 5),
        CGPoint(x: 1, y: 5),
        CGPoint(x: 1, y: 4),
        CGPoint(x: 0, y: 4),
        CGPoint(x: 0, y: 1),
        CGPoint(x: 1, y: 1),
    ]

    nonisolated static func usesDarkColor(tileIndex: Int) -> Bool {
        tileIndex == 0 || tileIndex == 3
    }

    nonisolated static func opacity(tileIndex: Int, at time: TimeInterval) -> Double {
        guard time.isFinite, (0..<4).contains(tileIndex) else { return 1 }

        let clockwiseRank = [0, 1, 3, 2][tileIndex]
        let phase = 2 * Double.pi * (time / cycleDuration - Double(clockwiseRank) / 4)
        let wave = (cos(phase) + 1) / 2
        return minimumOpacity + (1 - minimumOpacity) * wave
    }

    nonisolated static func rotationDegrees(at time: TimeInterval) -> Double {
        guard time.isFinite else { return 0 }
        return normalizedProgress(at: time) * 360
    }

    nonisolated static func scale(at time: TimeInterval) -> Double {
        guard time.isFinite else { return 1 }
        let wave = (sin(2 * Double.pi * normalizedProgress(at: time) * 2) + 1) / 2
        return minimumScale + (maximumScale - minimumScale) * wave
    }

    nonisolated static func breathingOpacity(at time: TimeInterval) -> Double {
        guard time.isFinite else { return 1 }
        let wave = (cos(2 * Double.pi * normalizedProgress(at: time)) + 1) / 2
        return minimumBreathingOpacity + (1 - minimumBreathingOpacity) * wave
    }

    private nonisolated static func normalizedProgress(at time: TimeInterval) -> Double {
        let remainder = time.truncatingRemainder(dividingBy: cycleDuration)
        let positiveRemainder = remainder < 0 ? remainder + cycleDuration : remainder
        return positiveRemainder / cycleDuration
    }
}

enum MacIslandCursorFacet: Int, Sendable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft
}

struct MacIslandCursorPixelCell: Identifiable, Equatable, Sendable {
    let id: Int
    let x: Int
    let y: Int
    let facet: MacIslandCursorFacet
}

enum MacIslandCursorPixelArt {
    nonisolated static let gridSize = 19

    /// A code-drawn 17x17 four-facet crystal. Working animation moves each
    /// facet outward by one logical pixel, leaving a black center seam.
    nonisolated static func cells(separation: Int) -> [MacIslandCursorPixelCell] {
        let separation = min(1, max(0, separation))
        let center = gridSize / 2
        var cells: [MacIslandCursorPixelCell] = []
        var id = 0

        for relativeY in -8...8 {
            let halfWidth = min(8, 9 - abs(relativeY))
            for relativeX in (-halfWidth)...halfWidth {
                let facet: MacIslandCursorFacet
                if relativeY <= 0 {
                    facet = relativeX <= 0 ? .topLeft : .topRight
                } else {
                    facet = relativeX > 0 ? .bottomRight : .bottomLeft
                }

                let horizontalDirection = facet == .topLeft || facet == .bottomLeft ? -1 : 1
                let verticalDirection = facet == .topLeft || facet == .topRight ? -1 : 1
                cells.append(
                    MacIslandCursorPixelCell(
                        id: id,
                        x: center + relativeX + horizontalDirection * separation,
                        y: center + relativeY + verticalDirection * separation,
                        facet: facet
                    )
                )
                id += 1
            }
        }

        return cells
    }
}

enum MacIslandCursorPixelMotion {
    nonisolated static let cycleDuration: TimeInterval = 1.76
    nonisolated static let fullFrameInterval: TimeInterval = 1.0 / 30.0
    nonisolated static let reducedFrameInterval: TimeInterval = 1.0 / 15.0
    nonisolated static let minimumScale = 0.92
    nonisolated static let maximumScale = 1.0

    nonisolated static func openness(at time: TimeInterval) -> Double {
        guard time.isFinite else { return 0 }
        let progress = normalizedProgress(at: time)
        return (sin(2 * Double.pi * progress - Double.pi / 2) + 1) / 2
    }

    nonisolated static func separation(at time: TimeInterval) -> Int {
        openness(at: time) > 0.46 ? 1 : 0
    }

    nonisolated static func scale(at time: TimeInterval) -> Double {
        guard time.isFinite else { return maximumScale }
        return minimumScale + (maximumScale - minimumScale) * openness(at: time)
    }

    private nonisolated static func normalizedProgress(at time: TimeInterval) -> Double {
        let remainder = time.truncatingRemainder(dividingBy: cycleDuration)
        let positiveRemainder = remainder < 0 ? remainder + cycleDuration : remainder
        return positiveRemainder / cycleDuration
    }
}
