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
    /// The cover art, which turns into a hide button under the pointer.
    var hideRect: CGRect?
    /// The time row under the title: elapsed time, the bar, and time left.
    var progressRect: CGRect?
    /// The time row floats in the gap between the blocks, with no glass behind it.
    var progressBetweenBlocks = false
    /// A small glass block of its own behind the floating time row (Glass Pill look).
    var progressPill: CGRect?
    /// Two Blocks: the time row runs under both the title and the playback buttons.
    var progressWide = false
    static func progressLabelWidth(_ s: Double, floating: Bool = false) -> Double { (floating ? 36 : 30) * s }
    static func progressSpacing(_ s: Double) -> Double { 6 * s }
    /// The draggable bar inside the time row.
    var progressBarRect: CGRect? {
        guard let row = progressRect else { return nil }
        let side = Self.progressLabelWidth(scale, floating: progressBetweenBlocks || progressWide) + Self.progressSpacing(scale)
        return CGRect(x: row.minX + side, y: row.minY, width: max(0, row.width - side * 2), height: row.height)
    }
    var scale: Double = 1
    /// Controls fade in on hover when the layout has no permanent place for them.
    var controlsOnHover = false
    var isFullScreen = false
    /// Text size and lyric area stay independent of the card's size, so resizing shows more
    /// lines instead of zooming.
    var lyricFont: Double
    var viewportHeight: Double

    static let width = 440.0
    static let minWidth = 300.0
    static let minHeight = 130.0
    static func progressRowHeight(_ layout: CardLayout) -> Double { layout == .roundButtons ? 12 : 14 }
    static func lyricsHeight(_ p: Prefs) -> Double { Double(p.visibleLines) * (p.fontSize * 1.82) }

    init(_ p: Prefs, fullScreen: CGSize? = nil) {
        let s = p.scale, gap = 10 * s, radius = p.cornerRadius * s
        scale = s
        lyricFont = p.fontSize * s
        viewportHeight = 0

        if let screen = fullScreen {
            isFullScreen = true
            size = screen
            let area = CGRect(origin: .zero, size: screen)
            blocks = [GlassBlock(rect: area, radius: 0)]
            coverRect = CGRect(x: 0, y: 0, width: screen.width * 0.4, height: screen.height)
            lyricsRect = CGRect(x: screen.width * 0.42, y: screen.height * 0.1,
                                width: screen.width * 0.53, height: screen.height * 0.8)
            lyricFont = min(screen.height * 0.058, screen.width * 0.04)
            viewportHeight = lyricsRect.height
            return
        }

        let w = max(Self.minWidth * s, p.cardWidth > 0 ? p.cardWidth : Self.width * s)
        let autoLyrics = Self.lyricsHeight(p) * s

        func hoverControls(_ width: Double) -> CGRect? {
            p.showControls ? CGRect(x: width - 124 * s, y: 0, width: 124 * s, height: 72 * s) : nil
        }
        /// The explicit height if the user dragged one, or else room for the chosen line count.
        func total(_ auto: Double) -> Double {
            p.cardHeight > 0 ? max(Self.minHeight * s, p.cardHeight) : auto
        }

        if p.layout == .classic {
            if p.showHeader { hideRect = CGRect(x: 24 * s, y: 20 * s, width: 44 * s, height: 44 * s) }
            let chrome = (40 + (p.showHeader ? 58.0 : 0)) * s
            let height = total(chrome + autoLyrics)
            size = CGSize(width: w, height: height)
            lyricsRect = CGRect(origin: .zero, size: size)
            viewportHeight = max(0, height - chrome)
            blocks = [GlassBlock(rect: lyricsRect, radius: radius)]
            controlsRect = hoverControls(w)
            controlsOnHover = true
        } else if !p.showHeader {
            let height = total(34 * s + autoLyrics)
            size = CGSize(width: w, height: height)
            lyricsRect = CGRect(origin: .zero, size: size)
            viewportHeight = max(0, height - 34 * s)
            blocks = [GlassBlock(rect: lyricsRect, radius: radius)]
            controlsRect = hoverControls(w)
            controlsOnHover = true
        } else {
            let round = p.layout == .roundButtons && p.showControls
            let topHeight = (p.layout == .roundButtons ? 66 : 80) * s
            let between = p.timeBar == .betweenBlocks
            // A wider gap holds the floating time row.
            let pill = between && p.timeBarLook == .glassPill
            let gap = pill ? 44 * s : between ? 34 * s : gap
            let height = max(topHeight + gap + 60 * s, total(topHeight + gap + 34 * s + autoLyrics))
            size = CGSize(width: w, height: height)
            lyricsRect = CGRect(x: 0, y: topHeight + gap, width: w, height: height - topHeight - gap)
            viewportHeight = max(0, lyricsRect.height - 34 * s)
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
            let artSide = (p.layout == .roundButtons ? 44 : 56) * s
            let art = CGRect(x: (p.layout == .roundButtons ? 11 : 12) * s, y: (topHeight - artSide) / 2, width: artSide, height: artSide)
            hideRect = art
            // The time row lines up with the bottom of the cover art, under the title and artist.
            let textX = art.maxX + (p.layout == .roundButtons ? 10 : 12) * s
            let textRight = round ? coverWidth - 14 * s
                : p.showControls ? w - (10 + 132 + 12) * s : w - 10 * s
            let rowHeight = Self.progressRowHeight(p.layout) * s
            let rowY = art.maxY - rowHeight + (p.layout == .roundButtons ? 4 : 1) * s
            if between {
                let row = 18 * s
                let inset = (pill ? 12 : 8) * s
                progressRect = CGRect(x: inset, y: topHeight + (gap - row) / 2, width: w - inset * 2, height: row)
                progressBetweenBlocks = true
                if pill {
                    let height = 26 * s
                    progressPill = CGRect(x: 0, y: topHeight + (gap - height) / 2, width: w, height: height)
                }
            } else if p.timeBar == .underTitle && p.layout == .twoBlocks {
                // Bigger, and wide enough to run under the buttons too; the buttons move up beside the title.
                let row = 17 * s
                let y = art.maxY - row + 2 * s
                progressRect = CGRect(x: textX, y: y, width: w - 16 * s - textX, height: row)
                progressWide = true
            } else if p.timeBar == .underTitle && textRight - textX > 120 * s {
                progressRect = CGRect(x: textX, y: rowY, width: textRight - textX, height: rowHeight)
            }
            coverRect = cover
            blocks = [GlassBlock(rect: cover, radius: radius), GlassBlock(rect: lyricsRect, radius: radius)]
                + circles.map { GlassBlock(rect: $0, radius: topHeight / 2) }
                + (progressPill.map { [GlassBlock(rect: $0, radius: $0.height / 2)] } ?? [])
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
    var fullScreenSize: CGSize? = nil
    var onDone: () -> Void
    var onExitFullScreen: () -> Void = {}
    var onHide: () -> Void = {}

    private var p: Prefs { settings.p }
    private var s: Double { p.scale }

    private var colors: [Color] {
        let list = p.useArtworkColors ? model.meshColors : CoverColors.meshColors(fromCustom: settings.customRGB)
        return list.prefix(2).map { Color(red: $0.r, green: $0.g, blue: $0.b) }
    }

    var body: some View {
        let geometry = CardGeometry(p, fullScreen: fullScreenSize)
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
            if g.isFullScreen {
                fullScreenCover(g).place(g.coverRect ?? .zero)
                LyricsViewport(settings: settings, model: model, font: g.lyricFont, height: g.viewportHeight,
                               width: g.lyricsRect.width)
                    .place(g.lyricsRect)
                Button(action: onExitFullScreen) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.black.opacity(0.3)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exit full screen")
                .padding(24)
            } else if p.layout == .classic {
                VStack(alignment: .leading, spacing: 14 * s) {
                    if p.showHeader { classicHeader }
                    LyricsViewport(settings: settings, model: model, font: g.lyricFont, height: g.viewportHeight,
                                   width: g.size.width - 48 * s)
                }
                .padding(EdgeInsets(top: 20 * s, leading: 24 * s, bottom: 20 * s, trailing: 24 * s))
            } else {
                if let cover = g.coverRect { coverBlock(g).place(cover) }
                if showsProgress(g), let row = g.progressRect {
                    let floating = g.progressBetweenBlocks
                    let look = floating ? p.timeBarLook : .glassPill
                    SongProgress(model: model, scale: s,
                                 fontSize: floating ? 12 : g.progressWide ? 11 : p.layout == .roundButtons ? 9.5 : 10,
                                 labelWidth: CardGeometry.progressLabelWidth(s, floating: floating || g.progressWide),
                                 spacing: CardGeometry.progressSpacing(s),
                                 barHeight: floating ? (g.progressPill != nil ? 4 : 5) * s : g.progressWide ? 4 * s : nil,
                                 floating: floating && look != .glassPill,
                                 tint: floating && look == .albumColor ? albumTint : nil)
                        .place(row)
                        .allowsHitTesting(false)
                }
                ForEach(Array(g.circles.enumerated()), id: \.offset) { index, rect in
                    circleButton(index, diameter: rect.width).place(rect)
                }
                LyricsViewport(settings: settings, model: model, font: g.lyricFont, height: g.viewportHeight,
                               width: g.lyricsRect.width - 48 * s)
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
                // Fully opaque colors hide the windows behind, so blurring them would be wasted work.
                if p.blurEnabled && !(p.showColorBlobs && p.colorStrength >= 0.99) {
                    BackdropBlur(radius: p.blurRadius, geometry: g, plain: false).allowsHitTesting(false)
                }
                Group {
                    if p.showColorBlobs {
                        if p.useArtworkColors {
                            LiquidBackground(colors: model.meshColors, from: model.meshFrom,
                                             changedAt: model.meshChangedAt, animated: moving)
                                .opacity(p.colorStrength)
                        } else {
                            let custom = CoverColors.meshColors(fromCustom: settings.customRGB)
                            LiquidBackground(colors: custom, from: custom, changedAt: .distantPast, animated: moving)
                                .opacity(p.colorStrength)
                        }
                    }
                    Color.black.opacity(p.panelOpacity)
                }
                .clipShape(shape)
                edge(g)
            case .blurOnly:
                BackdropBlur(radius: p.blurRadius, geometry: g, plain: true).allowsHitTesting(false)
                Color.black.opacity(p.glassDarkness).clipShape(shape)
                edge(g)
            case .transparent:
                Color.clear
            }
        }
    }

    private func fullScreenCover(_ g: CardGeometry) -> some View {
        let unit = g.size.height / 100
        let art = min(g.size.width * 0.28, g.size.height * 0.5)
        return VStack(alignment: .center, spacing: 3 * unit) {
            Group {
                if let image = model.artwork {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: art, height: art)
            .clipShape(RoundedRectangle(cornerRadius: art * 0.05, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 3 * unit, y: unit)
            VStack(spacing: 0.5 * unit) {
                Text(model.track?.title ?? "Lowkey")
                    .font(.system(size: 2.8 * unit, weight: .bold))
                    .foregroundStyle(.white)
                Text(model.track?.artist ?? "Preview")
                    .font(.system(size: 2.2 * unit))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .lineLimit(1)
            .frame(width: art)
            if model.track != nil && model.displayDuration > 0 {
                SongProgress(model: model, scale: 1, fontSize: 1.5 * unit, labelWidth: 5 * unit,
                             spacing: unit, barHeight: 0.6 * unit, draggable: true)
                    .frame(width: art * 1.15, height: 3 * unit)
            }
            PlaybackControls(model: model, scale: 1, buttonSize: 7 * unit, iconSize: 2.6 * unit,
                             mainIconSize: 3.8 * unit, buttonHeight: 7 * unit)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Light Edge catches light along each surface's top, as real glass does, and fades before the bottom.
    @ViewBuilder
    private func edge(_ g: CardGeometry) -> some View {
        if !g.isFullScreen {
            switch p.edgeStyle {
            case .lightEdge:
                ForEach(Array(g.blocks.enumerated()), id: \.offset) { _, block in
                    BlocksShape(blocks: [block], inset: 0.5).stroke(
                        LinearGradient(stops: [
                            .init(color: .white.opacity(0.42), location: 0),
                            .init(color: .white.opacity(0.1), location: 0.45),
                            .init(color: .white.opacity(0.03), location: 0.75),
                            .init(color: .white.opacity(0.1), location: 1),
                        ],
                        startPoint: UnitPoint(x: 0.5, y: block.rect.minY / max(1, g.size.height)),
                        endPoint: UnitPoint(x: 0.5, y: block.rect.maxY / max(1, g.size.height))),
                        lineWidth: 1)
                }
            case .hairline:
                BlocksShape(blocks: g.blocks, inset: 0.5).stroke(Color.white.opacity(0.16), lineWidth: 1)
            case .borderless:
                EmptyView()
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
        .overlay { hideButton(side: side, radius: radius) }
    }

    /// Under the pointer the cover offers to hide the card for now; Lowkey keeps running.
    @ViewBuilder
    private func hideButton(side: Double, radius: Double) -> some View {
        if model.isHoveringCover && !isEditing && fullScreenSize == nil {
            Button(action: onHide) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: side * 0.34 * s, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: side * s, height: side * s)
                    .background(RoundedRectangle(cornerRadius: radius * s, style: .continuous).fill(.black.opacity(0.5)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide Lowkey for now (⌃⌥⌘H)")
            .accessibilityLabel("Hide for now")
            .transition(.opacity)
        }
    }

    /// One strong color from the cover for the Album Color time bar: saturated and mid-bright,
    /// so it stands out over both white and dark windows.
    private var albumTint: Color {
        let list = p.useArtworkColors ? model.meshColors : CoverColors.meshColors(fromCustom: settings.customRGB)
        let best = list.max { a, b in
            func saturation(_ c: RGB) -> Double { let hi = max(c.r, c.g, c.b); return hi == 0 ? 0 : (hi - min(c.r, c.g, c.b)) / hi }
            return saturation(a) < saturation(b)
        } ?? RGB(r: 0.55, g: 0.35, b: 0.95)
        var h: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
        NSColor(srgbRed: best.r, green: best.g, blue: best.b, alpha: 1).getHue(&h, saturation: &sat, brightness: &bri, alpha: &a)
        // Blue at full brightness still looks dark, so judge by perceived lightness: lighten toward
        // white until it sits in the middle (about 18% luminance), readable on white and on black alike.
        let pure = NSColor(hue: h, saturation: max(sat, 0.7), brightness: 1, alpha: 1)
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        var mix: CGFloat = 0, color = pure
        while mix < 0.7 {
            color = pure.blended(withFraction: mix, of: .white) ?? pure
            let lum = 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
            if lum >= 0.18 { break }
            mix += 0.05
        }
        return Color(nsColor: color)
    }

    private func showsProgress(_ g: CardGeometry) -> Bool {
        g.progressRect != nil && (model.track != nil || model.isSampleMode) && model.displayDuration > 0
    }

    private func titles(titleSize: Double, artistSize: Double, spacing: Double = 2) -> some View {
        VStack(alignment: .leading, spacing: spacing * s) {
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
            if showsProgress(g) && !g.progressBetweenBlocks {
                // Title and artist sit at the top of the cover art; the time row takes its bottom edge.
                VStack(alignment: .leading, spacing: 0) {
                    titles(titleSize: isRound ? 14 : 15, artistSize: isRound ? 12 : 13, spacing: isRound ? 0 : 1)
                    Spacer(minLength: 0)
                }
                .frame(height: (isRound ? 44 : 56) * s)
                .offset(y: (isRound ? -2 : 0) * s)
            } else {
                titles(titleSize: isRound ? 14 : 15, artistSize: isRound ? 12 : 13)
            }
            Spacer(minLength: 0)
            if !isRound && p.showControls {
                PlaybackControls(model: model, scale: s, buttonSize: 44, iconSize: 16, mainIconSize: 22)
                    // With the wide time row below, the buttons sit level with the title instead.
                    .offset(y: showsProgress(g) && g.progressWide
                        ? ((g.progressRect?.minY ?? 0) - (g.coverRect?.height ?? 0)) / 2 : 0)
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
                .allowsHitTesting(false)
                .accessibilityHidden(true)
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
    let font: Double
    let height: Double
    let width: Double

    private var p: Prefs { settings.p }
    /// Spacing unit: follows the text size, not the size of the card.
    private var s: Double { font / 22 }
    private var gap: Double { 8 * s }
    /// As many lines as the lyric area has room for.
    private var lineCount: Int { max(1, Int((height + gap) / (font * 1.3 + gap))) }
    /// One finished line stays visible above the current one when there's room.
    private var pastSlots: Int { lineCount >= 3 ? 1 : 0 }

    var body: some View {
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

    @ViewBuilder
    private var message: some View {
        switch model.lyricsState {
        case .missing:
            VStack(alignment: .leading, spacing: 3 * s) {
                Text("No lyrics for this one")
                    .font(.system(size: 18 * s, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                Text("Just vibes")
                    .font(.system(size: 13 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        case .loading:
            Text("Finding lyrics…")
                .font(.system(size: 15 * s, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        default:
            Text("Play something on Spotify")
                .font(.system(size: 15 * s, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
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

    /// A line's height is worked out from its text before it's drawn, so a line that wraps onto a second
    /// row always gets the room for it. The drawn height is used too when it's larger.
    private func lineHeight(_ id: Int) -> Double {
        let lines = model.displayLines
        let computed = id < lines.count ? TextHeight.of(lines[id], font: font, width: width) : font * 1.3
        return max(computed, Double(model.lineHeights[id] ?? 0))
    }

    private func lineStack(_ lines: [LyricLine]) -> some View {
        let browsing = model.browseAnchor != nil
        let anchor = model.browseAnchor ?? max(model.currentIndex, 0)
        // Lines outside the viewport stay rendered: they're measured before they scroll in,
        // and fade out fully before they're dropped, so nothing pops.
        let lower = max(0, anchor - 4)
        let upper = min(lines.count - 1, anchor + lineCount + 4)
        let animate = p.animationsEnabled
        return ZStack(alignment: .topLeading) {
            ForEach(lines[lower...upper]) { line in
                let d = line.id - model.currentIndex
                // While browsing, lines are placed and faded around the scrolled-to line instead.
                let v = browsing ? line.id - anchor : d
                Button {
                    model.seek(to: line.start)
                } label: {
                    LineView(line: line, distance: d, model: model, font: font, animate: animate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LinePress())
                .disabled(!p.clickToSeek || model.isSampleMode)
                .allowsHitTesting(opacity(v) > 0)
                .accessibilityHint("Plays the song from this line")
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: [line.id: $0.size.height]) })
                    .scaleEffect(d == 0 || !animate ? 1 : 0.97, anchor: .leading)
                    .animation(animate ? Self.scaleSpring.delay(stagger(d)) : nil, value: model.currentIndex)
                    .blur(radius: animate && !browsing ? blur(d) * s : 0)
                    .opacity(browsing ? (opacity(v) > 0 ? (d == 0 ? 1 : 0.75) : 0) : opacity(d))
                    .animation(animate ? .easeInOut(duration: 0.45) : nil, value: model.currentIndex)
                    .animation(animate ? .easeInOut(duration: 0.3) : nil, value: model.browseAnchor)
                    .offset(y: yOffset(line.id, anchor: anchor))
                    .animation(animate ? Self.moveSpring.delay(stagger(d)) : nil, value: model.currentIndex)
                    .animation(animate ? Self.moveSpring : nil, value: model.browseAnchor)
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
        let future = lineCount - pastSlots - 1
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
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: distance != 0 || !model.displayPlaying)) { context in
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
        let progress = time.map { line.letterProgress(at: $0) } ?? (distance < 0 ? 1 : 0)
        return Text(line.text)
            .font(.system(size: font, weight: .bold))
            .kerning(-0.01 * font)
            .foregroundStyle(.white)
            .lineSpacing(font * 0.08)
            .textRenderer(LetterRiseRenderer(progress: animate ? progress : (distance <= 0 ? 1 : 0),
                                             lift: animate && isActive ? font * 0.06 : 0,
                                             riseDuration: 1.1 / max(line.sungDuration, 0.1),
                                             maxLift: font * 0.06,
                                             lineTime: time.map { ($0 - line.start) / line.sungDuration } ?? 0,
                                             emphases: animate && isActive ? line.emphases : [],
                                             font: font))
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
    /// How far through the line the song is, 0...1, for held words.
    var lineTime: Double = 0
    var emphases: [Emphasis] = []
    var font: Double = 22

    /// Risen, swollen and glowing letters stay inside the area SwiftUI redraws.
    var displayPadding: EdgeInsets {
        let room = emphases.isEmpty ? 0 : font * 0.45
        return EdgeInsets(top: maxLift + 1 + room, leading: room, bottom: room, trailing: room)
    }

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
                    if let held = emphases.first(where: { position >= $0.letterFrom && position < $0.letterTo }) {
                        swell(&letter, glyph: glyph, held: held,
                              letterIndex: index - Int((held.letterFrom * Double(total)).rounded()))
                    }
                    // Without this, text snaps to the pixel grid and shakes during slow movement.
                    letter.draw(glyph, options: .disablesSubpixelQuantization)
                    index += 1
                }
            }
        }
    }

    /// A held word's letters, one after another, grow a little, lean apart from the middle, float up
    /// and glow, then settle back as the note ends.
    private func swell(_ letter: inout GraphicsContext, glyph: Text.Layout.RunSlice, held: Emphasis, letterIndex: Int) {
        let count = Double(held.letterCount)
        let i = Double(max(0, min(held.letterCount - 1, letterIndex)))
        // Measured in lengths of the word: the effect lasts at least a second, a little longer on the last word.
        let span = max(1, held.seconds) * (held.isLastWord ? 1.2 : 1) / held.seconds
        let local = (lineTime - held.timeFrom) / max(0.001, held.timeTo - held.timeFrom)
        let delay = span / 2.5 / count * i
        let x = min(1, max(0, (local - delay) / span))
        let floatX = min(1, max(0, (local - delay) / (span * 1.4)))
        guard x > 0 else { return }

        // Rises quickly to its peak at the middle of the note, then eases back down.
        let shape = x < 0.5 ? 1 - pow(1 - x * 2, 3) : 1 - Self.smoothed(x * 2 - 1)
        let scale = 1 + shape * 0.1 * held.amount
        let spreadX = -shape * 0.03 * held.amount * (count / 2 - i) * font
        let floatY = -(sin(floatX * .pi) * 0.05 + floatX * 0.05) * font - shape * 0.025 * held.amount * font

        let box = glyph.typographicBounds.rect
        letter.translateBy(x: box.midX + spreadX, y: box.midY + floatY)
        letter.scaleBy(x: scale, y: scale)
        letter.translateBy(x: -box.midX, y: -box.midY)
        let glow = shape * held.glow
        if glow > 0.01 {
            letter.addFilter(.shadow(color: .white.opacity(min(1, glow)), radius: min(0.3, held.glow * 0.3) * font))
        }
    }

    /// Starts and ends with no speed, so no letter visibly jerks.
    private static func smoothed(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}

/// Measures lyric text the way it's drawn: bold system font, the same tracking and line spacing.
enum TextHeight {
    private static var cache: [String: Double] = [:]

    static func of(_ line: LyricLine, font: Double, width: Double) -> Double {
        if line.isInterlude { return font * 1.2 }
        let key = "\(line.text)|\(Int(font * 10))|\(Int(width))"
        if let known = cache[key] { return known }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = font * 0.08
        let text = NSAttributedString(string: line.text, attributes: [
            .font: NSFont.systemFont(ofSize: font, weight: .bold),
            .kern: -0.01 * font,
            .paragraphStyle: style,
        ])
        let box = text.boundingRect(with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = ceil(box.height)
        if cache.count > 2000 { cache.removeAll() }
        cache[key] = height
        return height
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
/// Elapsed time, a slim bar, and time left, like the mini player in Apple Music.
/// In the card the panel drives dragging (see OverlayPanel); full screen uses a SwiftUI drag.
struct SongProgress: View {
    @ObservedObject var model: NowPlaying
    let scale: Double
    let fontSize: Double
    let labelWidth: Double
    let spacing: Double
    var barHeight: Double? = nil
    var draggable = false
    /// Sitting on no glass, so it gets a soft shadow to stay readable over any window.
    var floating = false
    /// Album Color look: the bar and numbers take this color instead of white.
    var tint: Color? = nil

    var body: some View {
        let scrubbing = model.scrubFraction != nil
        TimelineView(.animation(minimumInterval: 0.25, paused: !model.displayPlaying || scrubbing)) { context in
            let duration = model.displayDuration
            let played = min(1, max(0, model.scrubFraction ?? model.playbackPosition(at: context.date) / max(1, duration)))
            HStack(spacing: spacing) {
                Text(Self.format(played * duration))
                    .frame(width: labelWidth, alignment: .leading)
                GeometryReader { bar in
                    let thick = (barHeight ?? 3 * scale) * (scrubbing ? 1.7 : 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill((tint ?? .white).opacity(tint != nil ? 0.4 : floating ? 0.3 : 0.22))
                        Capsule().fill((tint ?? .white).opacity(tint != nil ? 1 : scrubbing ? 0.95 : 0.8))
                            .frame(width: max(thick, bar.size.width * played))
                    }
                    .frame(height: thick)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { model.scrubFraction = min(1, max(0, $0.location.x / max(1, bar.size.width))) }
                        .onEnded { _ in
                            if let target = model.scrubFraction { model.seek(toFraction: target) }
                            model.scrubFraction = nil
                        }, including: draggable ? .all : .none)
                }
                Text("-" + Self.format(max(0, duration - played * duration)))
                    .frame(width: labelWidth, alignment: .trailing)
            }
            .font(.system(size: fontSize * (draggable ? 1 : scale), weight: .medium).monospacedDigit())
            .foregroundStyle(tint ?? .white.opacity(floating ? 0.9 : 0.6))
            // A wide, faint glow keeps white readable over bright windows without looking like an outline.
            .shadow(color: .black.opacity(floating && tint == nil ? 0.22 : 0), radius: 6 * scale)
            .lineLimit(1)
            .animation(.easeOut(duration: 0.15), value: scrubbing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Song position")
        .accessibilityValue(Self.format(model.playbackPosition(at: Date())))
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct PlaybackControls: View {
    @ObservedObject var model: NowPlaying
    let scale: Double
    var buttonSize = 30.0
    var iconSize = 13.0
    var mainIconSize = 17.0
    var buttonHeight = 36.0

    var body: some View {
        HStack(spacing: 1 * scale) {
            PlaybackButton(symbol: "backward.fill", label: "Previous", iconSize: iconSize * scale,
                           width: buttonSize * scale, height: buttonHeight * scale, action: model.previousTrack)
            PlaybackButton(symbol: model.isPlaying ? "pause.fill" : "play.fill", label: model.isPlaying ? "Pause" : "Play",
                           iconSize: mainIconSize * scale, width: buttonSize * scale, height: buttonHeight * scale, action: model.playPause)
            PlaybackButton(symbol: "forward.fill", label: "Next", iconSize: iconSize * scale,
                           width: buttonSize * scale, height: buttonHeight * scale, action: model.nextTrack)
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
    /// A new cover's colors flow in cell by cell from these, inside the same moving mesh,
    /// instead of one background fading over another.
    var from: [RGB] = []
    var changedAt = Date.distantPast
    let animated: Bool

    var body: some View {
        // Keeps drawing while a color change finishes, even when the song is paused.
        let blending = Date().timeIntervalSince(changedAt) < NowPlaying.meshBlend
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated && !blending)) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000)
            let blend = min(1, max(0, context.date.timeIntervalSince(changedAt) / NowPlaying.meshBlend))
            MeshGradient(width: 4, height: 4, points: points(t), colors: blended(t, blend: blend),
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
                let dx = edgeX ? 0 : (edgeY ? 0.09 : 0.14) * sin(t / (3.4 + seed * 0.29) + seed * 1.7)
                let dy = edgeY ? 0 : (edgeX ? 0.09 : 0.14) * cos(t / (4.1 + seed * 0.23) + seed * 2.3)
                result.append(SIMD2(Float(baseX + dx), Float(baseY + dy)))
            }
        }
        return result
    }

    /// The colors also travel from cell to cell, one step every few seconds.
    private func blended(_ t: Double, blend: Double) -> [Color] {
        guard colors.count == 16 else { return Array(repeating: .black, count: 16) }
        // Ease out the change of cover, so most of it happens early and the end settles softly.
        let change = 1 - pow(1 - blend, 3)
        let target = from.count == 16 && change < 1 ? zip(from, colors).map { $0.mixed(with: $1, change) } : colors
        let position = t / 3.2
        let step = Int(position.rounded(.down)) % 16
        let fraction = position - position.rounded(.down)
        let eased = fraction * fraction * (3 - 2 * fraction)
        return (0..<16).map { index in
            let mixed = target[(index + step) % 16].mixed(with: target[(index + step + 1) % 16], eased)
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
