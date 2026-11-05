import AppKit
import SwiftUI

/// Where each glass surface sits, in points from the panel's top-left corner.
struct GlassBlock: Equatable {
    var rect: CGRect
    var radius: CGFloat
}

/// One shared layout calculation for the view, the blur mask, the window size and the click area.
struct CardGeometry: Equatable {
    var size: CGSize
    var blocks: [GlassBlock]
    var coverRect: CGRect?
    var lyricsRect: CGRect
    var circles: [CGRect] = []
    var controlsRect: CGRect?
    /// Controls fade in on hover when the layout has no permanent place for them.
    var controlsOnHover = false

    static let width = 440.0
    static func lyricsHeight(_ p: Prefs) -> Double { Double(p.visibleLines) * (p.fontSize * 1.82) }

    init(_ p: Prefs) {
        let s = p.scale, w = Self.width * s, gap = 10 * s, radius = p.cornerRadius * s
        let lyricsBlockHeight = 34 * s + Self.lyricsHeight(p) * s

        func hoverControls(_ size: CGSize) -> CGRect? {
            p.showControls ? CGRect(x: size.width - 124 * s, y: 0, width: 124 * s, height: 72 * s) : nil
        }

        if p.layout == .classic {
            let header = p.showHeader ? 58.0 : 0
            let height = (40 + header + Self.lyricsHeight(p)) * s
            size = CGSize(width: w, height: height)
            lyricsRect = CGRect(origin: .zero, size: size)
            blocks = [GlassBlock(rect: lyricsRect, radius: radius)]
            controlsRect = hoverControls(size)
            controlsOnHover = true
        } else if !p.showHeader {
            size = CGSize(width: w, height: lyricsBlockHeight)
            lyricsRect = CGRect(origin: .zero, size: size)
            blocks = [GlassBlock(rect: lyricsRect, radius: radius)]
            controlsRect = hoverControls(size)
            controlsOnHover = true
        } else {
            let round = p.layout == .roundButtons && p.showControls
            let topHeight = (p.layout == .roundButtons ? 66 : 80) * s
            size = CGSize(width: w, height: topHeight + gap + lyricsBlockHeight)
            lyricsRect = CGRect(x: 0, y: topHeight + gap, width: w, height: lyricsBlockHeight)
            var coverWidth = w
            if round {
                let spacing = 8 * s
                let x = w - topHeight * 3 - spacing * 2
                circles = (0..<3).map { CGRect(x: x + CGFloat($0) * (topHeight + spacing), y: 0, width: topHeight, height: topHeight) }
                coverWidth = x - spacing
                controlsRect = CGRect(x: x, y: 0, width: w - x, height: topHeight)
            } else if p.showControls {
                controlsRect = CGRect(x: w - 142 * s, y: 0, width: 142 * s, height: topHeight)
            }
            let cover = CGRect(x: 0, y: 0, width: coverWidth, height: topHeight)
            coverRect = cover
            blocks = [GlassBlock(rect: cover, radius: radius), GlassBlock(rect: lyricsRect, radius: radius)]
                + circles.map { GlassBlock(rect: $0, radius: topHeight / 2) }
        }
    }
}

/// All the card's glass surfaces as one shape, so color and blur run across them as a single sheet.
struct BlocksShape: Shape {
    let blocks: [GlassBlock]
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for block in blocks {
            path.addRoundedRect(in: block.rect.insetBy(dx: inset, dy: inset),
                                cornerSize: CGSize(width: max(0, block.radius - inset), height: max(0, block.radius - inset)),
                                style: .continuous)
        }
        return path
    }
}

struct OverlayView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var model: NowPlaying
    @Binding var isEditing: Bool
    var onResize: (NSPoint?) -> Void
    var onDone: () -> Void

    private var p: Prefs { settings.p }
    private var s: Double { p.scale }

    private var colors: [Color] {
        let list = p.useArtworkColors ? model.meshColors : CoverColors.meshColors(fromCustom: settings.customRGB)
        return list.prefix(2).map { Color(red: $0.r, green: $0.g, blue: $0.b) }
    }

    var body: some View {
        let geometry = CardGeometry(p)
        ZStack(alignment: .topLeading) {
            background(geometry)
            content(geometry)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Without a tinted panel, a soft shadow keeps white text readable over bright windows.
                .shadow(color: .black.opacity(p.backgroundStyle == .albumColor ? 0 : 0.5), radius: 5 * s, y: 1)
            if isEditing { editChrome }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func content(_ g: CardGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            if p.layout == .classic {
                VStack(alignment: .leading, spacing: 14 * s) {
                    if p.showHeader { classicHeader }
                    LyricsViewport(settings: settings, model: model)
                }
                .padding(EdgeInsets(top: 20 * s, leading: 24 * s, bottom: 20 * s, trailing: 24 * s))
            } else {
                if let cover = g.coverRect { coverBlock(g).place(cover) }
                ForEach(Array(g.circles.enumerated()), id: \.offset) { index, rect in
                    circleButton(index, diameter: rect.width).place(rect)
                }
                LyricsViewport(settings: settings, model: model)
                    .padding(EdgeInsets(top: 16 * s, leading: 24 * s, bottom: 18 * s, trailing: 24 * s))
                    .place(g.lyricsRect)
            }
            if g.controlsOnHover && !p.showHeader && hoverControlsVisible(g) {
                HStack {
                    Spacer()
                    PlaybackControls(model: model, scale: s)
                        .padding(.horizontal, 4 * s)
                        .background(Capsule().fill(.black.opacity(0.4)))
                }
                .padding(EdgeInsets(top: 14 * s, leading: 0, bottom: 0, trailing: 16 * s))
                .transition(.opacity)
            }
        }
    }

    private func hoverControlsVisible(_ g: CardGeometry) -> Bool {
        p.showControls && g.controlsOnHover && model.isHovering && !isEditing
    }

    private func background(_ g: CardGeometry) -> some View {
        let shape = BlocksShape(blocks: g.blocks)
        let moving = p.animationsEnabled && model.displayPlaying
        return ZStack {
            switch p.backgroundStyle {
            case .albumColor:
                if p.blurEnabled {
                    BackdropBlur(radius: p.blurRadius, geometry: g, plain: false).allowsHitTesting(false)
                }
                Group {
                    if p.showColorBlobs {
                        let meshColors = p.useArtworkColors ? model.meshColors : CoverColors.meshColors(fromCustom: settings.customRGB)
                        LiquidBackground(colors: meshColors, animated: moving)
                            .opacity(p.colorStrength)
                            .id(meshColors.map { "\($0.r)\($0.g)\($0.b)" }.joined())
                            .transition(.opacity)
                    }
                    Color.black.opacity(p.panelOpacity)
                }
                .animation(.easeInOut(duration: 0.9), value: model.meshColors)
                .clipShape(shape)
                BlocksShape(blocks: g.blocks, inset: 0.5).stroke(Color.white.opacity(0.16), lineWidth: 1)
            case .blurOnly:
                BackdropBlur(radius: p.blurRadius, geometry: g, plain: true).allowsHitTesting(false)
                Color.black.opacity(p.glassDarkness).clipShape(shape)
                BlocksShape(blocks: g.blocks, inset: 0.5).stroke(Color.white.opacity(0.2), lineWidth: 1)
            case .transparent:
                Color.clear
            }
        }
    }

    private func artwork(side: Double, radius: Double) -> some View {
        Group {
            if let art = model.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: Array(colors.prefix(2)), startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .frame(width: side * s, height: side * s)
        .clipShape(RoundedRectangle(cornerRadius: radius * s, style: .continuous))
    }

    private func titles(titleSize: Double, artistSize: Double) -> some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            Text(model.track?.title ?? "Lowkey")
                .font(.system(size: titleSize * s, weight: .semibold))
                .foregroundStyle(.white)
            Text(model.track?.artist ?? "Preview")
                .font(.system(size: artistSize * s))
                .foregroundStyle(.white.opacity(0.8))
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    /// Cover, title and artist; in Two Blocks the playback buttons share this block.
    private func coverBlock(_ g: CardGeometry) -> some View {
        let isRound = p.layout == .roundButtons
        return HStack(spacing: (isRound ? 10 : 12) * s) {
            artwork(side: isRound ? 44 : 56, radius: isRound ? 10 : 12)
            titles(titleSize: isRound ? 14 : 15, artistSize: isRound ? 12 : 13)
            Spacer(minLength: 0)
            if !isRound && p.showControls {
                PlaybackControls(model: model, scale: s, buttonSize: 44, iconSize: 16, mainIconSize: 22)
            }
        }
        .padding(EdgeInsets(top: 0, leading: (isRound ? 11 : 12) * s, bottom: 0, trailing: (isRound ? 14 : 10) * s))
    }

    private func circleButton(_ index: Int, diameter: Double) -> some View {
        let isMain = index == 1
        return PlaybackButton(
            symbol: index == 0 ? "backward.fill" : isMain ? (model.isPlaying ? "pause.fill" : "play.fill") : "forward.fill",
            label: index == 0 ? "Previous" : isMain ? (model.isPlaying ? "Pause" : "Play") : "Next",
            iconSize: (isMain ? 23 : 18) * s, width: diameter, height: diameter,
            action: index == 0 ? model.previousTrack : isMain ? model.playPause : model.nextTrack)
    }

    private var classicHeader: some View {
        let hovering = p.showControls && model.isHovering && !isEditing
        return HStack(spacing: 12 * s) {
            artwork(side: 44, radius: 10)
            titles(titleSize: 14, artistSize: 13)
                .padding(.trailing, hovering ? 92 * s : 0)
            Spacer(minLength: 8 * s)
            Equalizer(active: p.animationsEnabled && model.displayPlaying, scale: s)
                .opacity(hovering ? 0 : 1)
        }
        .overlay(alignment: .trailing) {
            if hovering { PlaybackControls(model: model, scale: s).transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.18), value: hovering)
    }

    private var editChrome: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .allowsHitTesting(false)
            VStack {
                HStack {
                    Spacer()
                    Button("Done", action: onDone)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(10)
                Spacer()
            }
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white))
                .padding(6)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { _ in onResize(NSEvent.mouseLocation) }
                    .onEnded { _ in onResize(nil) })
                .accessibilityLabel("Resize")
        }
    }
}

private extension View {
    func place(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height, alignment: .leading)
            .offset(x: rect.minX, y: rect.minY)
    }
}

// MARK: - Lyrics

private struct HeightKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct LyricsViewport: View {
    @ObservedObject var settings: Settings
    @ObservedObject var model: NowPlaying

    private var p: Prefs { settings.p }
    private var s: Double { p.scale }
    private var font: Double { p.fontSize * s }
    private var gap: Double { 8 * s }
    /// One finished line stays visible above the current one when there's room.
    private var pastSlots: Int { p.visibleLines >= 3 ? 1 : 0 }

    var body: some View {
        let height = CardGeometry.lyricsHeight(p) * s
        Group {
            let lines = model.displayLines
            if lines.isEmpty {
                message.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                lineStack(lines)
            }
        }
        .frame(height: height, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
        .mask(fadeMask(height: height))
    }

    private var message: some View {
        let text: String
        switch model.lyricsState {
        case .loading: text = "Finding lyrics…"
        case .missing: text = "No synced lyrics for this song"
        default: text = "Play something on Spotify"
        }
        return Text(text)
            .font(.system(size: 15 * s, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
    }

    private func fadeMask(height: Double) -> some View {
        let top = min(0.15, 8 * s / max(height, 1))
        let bottom = min(0.25, 22 * s / max(height, 1))
        return LinearGradient(stops: [
            .init(color: pastSlots > 0 ? .clear : .black, location: 0),
            .init(color: .black, location: pastSlots > 0 ? top : 0),
            .init(color: .black, location: 1 - bottom),
            .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    private func lineHeight(_ id: Int) -> Double { Double(model.lineHeights[id] ?? font * 1.3) }

    private func lineStack(_ lines: [LyricLine]) -> some View {
        let anchor = max(model.currentIndex, 0)
        // Lines outside the viewport stay rendered: they're measured before they scroll in,
        // and fade out fully before they're dropped, so nothing pops.
        let lower = max(0, anchor - 4)
        let upper = min(lines.count - 1, anchor + p.visibleLines + 4)
        let animate = p.animationsEnabled
        return ZStack(alignment: .topLeading) {
            ForEach(lines[lower...upper]) { line in
                let d = line.id - model.currentIndex
                Button {
                    model.seek(to: line.start)
                } label: {
                    LineView(line: line, distance: d, model: model, font: font, animate: animate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LinePress())
                .disabled(!p.clickToSeek || model.isSampleMode)
                .allowsHitTesting(opacity(d) > 0)
                .accessibilityHint("Plays the song from this line")
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: [line.id: $0.size.height]) })
                    .scaleEffect(d == 0 || !animate ? 1 : 0.97, anchor: .leading)
                    .animation(animate ? Self.scaleSpring.delay(stagger(d)) : nil, value: model.currentIndex)
                    .blur(radius: animate ? blur(d) * s : 0)
                    .opacity(opacity(d))
                    .animation(animate ? .easeInOut(duration: 0.45) : nil, value: model.currentIndex)
                    .offset(y: yOffset(line.id, anchor: anchor))
                    .animation(animate ? Self.moveSpring.delay(stagger(d)) : nil, value: model.currentIndex)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onPreferenceChange(HeightKey.self) { [model] in model.recordHeights($0) }
        .id(model.track?.id ?? "sample")
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.35), value: model.track?.id)
    }

    /// Slightly over-damped so lines glide to rest without bouncing.
    private static let moveSpring = Animation.interpolatingSpring(mass: 0.9, stiffness: 195, damping: 30.7)
    private static let scaleSpring = Animation.interpolatingSpring(mass: 2, stiffness: 100, damping: 25)

    /// Top lines start first, opening room for the ones rising from below.
    private func stagger(_ d: Int) -> Double {
        Double(max(0, min(d + pastSlots, 5))) * 0.05
    }

    private func yOffset(_ id: Int, anchor: Int) -> Double {
        var y = Double(pastSlots) * (font * 1.3 + gap)
        if id >= anchor {
            for i in anchor..<id { y += lineHeight(i) + gap }
        } else {
            for i in id..<anchor { y -= lineHeight(i) + gap }
        }
        return y
    }

    private func opacity(_ d: Int) -> Double {
        if d == 0 { return 1 }
        if d < 0 { return d == -1 && pastSlots > 0 ? 0.45 : 0 }
        let future = p.visibleLines - pastSlots - 1
        if d > future { return 0 }
        return d == future && future > 1 ? 0.6 : 0.92
    }

    private func blur(_ d: Int) -> Double {
        switch d {
        case 0: return 0
        case -1: return 0.5
        case 1: return 0
        default: return 0.6
        }
    }
}

struct LineView: View {
    let line: LyricLine
    let distance: Int
    @ObservedObject var model: NowPlaying
    let font: Double
    let animate: Bool

    var body: some View {
        // Same view tree whether active or not, so a line changing role never re-creates its text.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: distance != 0 || !model.displayPlaying)) { context in
            let time = distance == 0 ? model.time(at: context.date) : nil
            if line.isInterlude {
                InterludeDots(progress: time.map { ($0 - line.start) / line.sungDuration } ?? (distance < 0 ? 1 : 0),
                              clock: time ?? 0, font: font)
            } else {
                words(time: time)
            }
        }
    }

    private func words(time: Double?) -> some View {
        let isActive = distance == 0
        let progress = time.map { min(1, max(0, ($0 - line.start) / line.sungDuration)) } ?? (distance < 0 ? 1 : 0)
        return Text(line.text)
            .font(.system(size: font, weight: .bold))
            .kerning(-0.01 * font)
            .foregroundStyle(.white)
            .lineSpacing(font * 0.08)
            .textRenderer(LetterRiseRenderer(progress: animate ? progress : (distance <= 0 ? 1 : 0),
                                             lift: animate && isActive ? font * 0.06 : 0,
                                             riseDuration: 1.1 / max(line.sungDuration, 0.1),
                                             maxLift: font * 0.06))
            // Letters that have risen ease back down together when the line stops being current.
            .animation(animate ? .easeInOut(duration: 0.55) : nil, value: isActive)
    }
}

/// Draws a line glyph by glyph: as the song passes each letter it brightens and glides upward,
/// with the movement overlapping its neighbors so the line rises in one soft wave.
struct LetterRiseRenderer: TextRenderer, Animatable {
    var progress: Double
    var lift: Double
    /// One letter's rise, as a share of the line. A fixed time keeps it gentle on quick lines too.
    var riseDuration: Double
    var maxLift: Double

    /// Risen letters stay inside the area SwiftUI redraws.
    var displayPadding: EdgeInsets { EdgeInsets(top: maxLift + 1, leading: 0, bottom: 0, trailing: 0) }

    var animatableData: Double {
        get { lift }
        set { lift = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var total = 0
        for textLine in layout { for run in textLine { total += run.count } }
        guard total > 0 else { return }

        // How much of the line each letter's change takes, never narrower than a few letters.
        let fillWindow = max(0.1, 3.0 / Double(total))
        let riseWindow = max(0.2, min(1, riseDuration))
        var index = 0
        for textLine in layout {
            for run in textLine {
                for glyph in run {
                    let position = Double(index) / Double(total)
                    let fill = Self.smoothed((progress * (1 + fillWindow) - position) / fillWindow)
                    let rise = Self.smoothed((progress * (1 + riseWindow) - position) / riseWindow)
                    var letter = context
                    letter.opacity = 0.5 + 0.5 * fill
                    letter.translateBy(x: 0, y: -lift * rise)
                    // Without this, text snaps to the pixel grid and shakes during slow movement.
                    letter.draw(glyph, options: .disablesSubpixelQuantization)
                    index += 1
                }
            }
        }
    }

    /// Starts and ends with no speed, so no letter visibly jerks.
    private static func smoothed(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}

/// Three dots that fill during an instrumental break.
struct InterludeDots: View {
    let progress: Double
    let clock: Double
    let font: Double

    var body: some View {
        HStack(spacing: font * 0.32) {
            ForEach(0..<3, id: \.self) { index in
                let fill = min(1, max(0, progress * 3 - Double(index)))
                Circle().fill(.white)
                    .frame(width: font * 0.36, height: font * 0.36)
                    .opacity(0.3 + 0.7 * fill)
                    .scaleEffect(1 + 0.08 * sin(clock * 2.4))
            }
        }
        .frame(height: font * 1.2, alignment: .leading)
    }
}

/// Previous, play/pause and next in one row.
struct PlaybackControls: View {
    @ObservedObject var model: NowPlaying
    let scale: Double
    var buttonSize = 30.0
    var iconSize = 13.0
    var mainIconSize = 17.0

    var body: some View {
        HStack(spacing: 1 * scale) {
            PlaybackButton(symbol: "backward.fill", label: "Previous", iconSize: iconSize * scale,
                           width: buttonSize * scale, height: 36 * scale, action: model.previousTrack)
            PlaybackButton(symbol: model.isPlaying ? "pause.fill" : "play.fill", label: model.isPlaying ? "Pause" : "Play",
                           iconSize: mainIconSize * scale, width: buttonSize * scale, height: 36 * scale, action: model.playPause)
            PlaybackButton(symbol: "forward.fill", label: "Next", iconSize: iconSize * scale,
                           width: buttonSize * scale, height: 36 * scale, action: model.nextTrack)
        }
    }
}

struct PlaybackButton: View {
    let symbol: String
    let label: String
    let iconSize: Double
    let width: Double
    let height: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: width, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFade())
        .accessibilityLabel(label)
    }
}

private struct LinePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PressFade: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Decoration

/// The cover's colors flowing slowly behind the lyrics. Built on a mesh gradient, which is drawn
/// on the GPU and blends perceptually, so the colors stay clean where they meet.
struct LiquidBackground: View {
    let colors: [RGB]
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000)
            MeshGradient(width: 4, height: 4, points: points(t), colors: blended(t),
                         smoothsColors: true, colorSpace: .perceptual)
        }
        .allowsHitTesting(false)
    }

    /// Each point drifts on its own slow, unrelated cycle, so the motion never visibly repeats.
    private func points(_ t: Double) -> [SIMD2<Float>] {
        var result: [SIMD2<Float>] = []
        for row in 0..<4 {
            for column in 0..<4 {
                let baseX = Double(column) / 3, baseY = Double(row) / 3
                let seed = Double(row * 4 + column)
                let edgeX = column == 0 || column == 3, edgeY = row == 0 || row == 3
                // Edge points may only slide along their edge, or the corners would show through.
                let dx = edgeX ? 0 : (edgeY ? 0.09 : 0.14) * sin(t / (7.3 + seed * 0.61) + seed * 1.7)
                let dy = edgeY ? 0 : (edgeX ? 0.09 : 0.14) * cos(t / (8.9 + seed * 0.47) + seed * 2.3)
                result.append(SIMD2(Float(baseX + dx), Float(baseY + dy)))
            }
        }
        return result
    }

    /// The colors also travel from cell to cell, one step every few seconds.
    private func blended(_ t: Double) -> [Color] {
        guard colors.count == 16 else { return Array(repeating: .black, count: 16) }
        let position = t / 5.5
        let step = Int(position.rounded(.down)) % 16
        let fraction = position - position.rounded(.down)
        let eased = fraction * fraction * (3 - 2 * fraction)
        return (0..<16).map { index in
            let mixed = colors[(index + step) % 16].mixed(with: colors[(index + step + 1) % 16], eased)
            return Color(red: mixed.r, green: mixed.g, blue: mixed.b)
        }
    }
}

struct Equalizer: View {
    let active: Bool
    let scale: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3 * scale) {
                ForEach(0..<3, id: \.self) { i in
                    let level = active ? 0.6 + 0.4 * sin(t * (4.5 + Double(i) * 1.7) + Double(i)) : 0.25
                    Capsule().fill(.white)
                        .frame(width: 3 * scale, height: max(3 * scale, 16 * scale * level))
                }
            }
            .frame(height: 16 * scale, alignment: .bottom)
        }
    }
}

// MARK: - Blur

/// Blurs whatever is behind the window. AppKit has no public blur-radius API, so the radius
/// is set on the view's backdrop filter; its opacity also fades, so weak values stay weak
/// even if a future macOS ignores the radius.
struct BackdropBlur: NSViewRepresentable {
    let radius: Double
    let geometry: CardGeometry
    /// Only the blurred windows behind, with none of the system's gray tint.
    let plain: Bool

    func makeNSView(context: Context) -> TunableEffectView {
        let view = TunableEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: TunableEffectView, context: Context) {
        view.radius = radius
        view.plain = plain
        view.alphaValue = min(1, radius / 16)
        if view.maskedGeometry != geometry {
            view.maskedGeometry = geometry
            view.maskImage = Self.mask(geometry)
        }
        view.applyRadius()
    }

    /// AppKit clips behind-window blur only through a mask image, so it's drawn from the same shape as the view.
    private static func mask(_ geometry: CardGeometry) -> NSImage {
        let path = BlocksShape(blocks: geometry.blocks).path(in: CGRect(origin: .zero, size: geometry.size)).cgPath
        return NSImage(size: geometry.size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
    }
}

final class TunableEffectView: NSVisualEffectView {
    var radius = 30.0
    var plain = false
    var maskedGeometry: CardGeometry?

    override func layout() {
        super.layout()
        applyRadius()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.applyRadius() }
    }

    func applyRadius() {
        guard let layer else { return }
        apply(to: layer)
    }

    private func apply(to layer: CALayer) {
        let names = (layer.filters ?? []).compactMap { ($0 as? NSObject)?.value(forKey: "name") as? String }
        if names.contains("gaussianBlur") {
            layer.setValue(radius, forKeyPath: "filters.gaussianBlur.inputRadius")
            // Its siblings ("fill", "tone", "desktop tint") are the material's gray wash.
            layer.superlayer?.sublayers?.filter { $0 !== layer }.forEach { $0.isHidden = plain }
        }
        layer.sublayers?.forEach(apply(to:))
    }
}
