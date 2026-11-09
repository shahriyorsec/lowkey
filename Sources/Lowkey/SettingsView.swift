import SwiftUI

/// The sidebar sections, laid out like System Settings.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, lyrics, position, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .lyrics: return "Lyrics"
        case .position: return "Position & Size"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintpalette.fill"
        case .lyrics: return "quote.bubble.fill"
        case .position: return "arrow.up.left.and.arrow.down.right"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Color(hex: 0x8E8E93)
        case .appearance: return Color(hex: 0x0A84FF)
        case .lyrics: return Color(hex: 0xFF375F)
        case .position: return Color(hex: 0xFF9F0A)
        case .about: return Color(hex: 0x5E5CE6)
        }
    }

    var summary: String {
        switch self {
        case .general: return "Layout, icon and how Lowkey behaves."
        case .appearance: return "Background, blur, colors and border."
        case .lyrics: return "Text size, lines, animation and timing."
        case .position: return "Where the card sits and how big it is."
        case .about: return "Version and shortcuts."
        }
    }
}

final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane? = .general
}

/// A colored rounded tile with a white symbol, as System Settings draws its sidebar icons.
struct PaneIcon: View {
    let pane: SettingsPane
    var size = 22.0

    var body: some View {
        Image(systemName: pane.symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: [pane.tint.opacity(0.85), pane.tint], startPoint: .top, endPoint: .bottom)))
            .accessibilityHidden(true)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var navigation: SettingsNavigation
    var onEdit: () -> Void
    var onFullScreen: () -> Void

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.pane) {
                ForEach(SettingsPane.allCases) { pane in
                    NavigationLink(value: pane) {
                        Label { Text(pane.title) } icon: { PaneIcon(pane: pane) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            // Only the sidebar is see-through: the desktop and windows behind show through it, blurred.
            .background(SidebarBlur().ignoresSafeArea())
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            let pane = navigation.pane ?? .general
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PaneHeader(pane: pane)
                    switch pane {
                    case .general: GeneralPane(settings: settings)
                    case .appearance: AppearancePane(settings: settings)
                    case .lyrics: LyricsPane(settings: settings)
                    case .position: PositionPane(settings: settings, onEdit: onEdit, onFullScreen: onFullScreen)
                    case .about: AboutPane(settings: settings)
                    }
                }
                .padding(EdgeInsets(top: 12, leading: 26, bottom: 28, trailing: 26))
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            .navigationTitle(pane.title)
        }
        .toggleStyle(.switch)
        .frame(minWidth: 720, minHeight: 540)
    }
}

/// The system's sidebar material, blurring whatever is behind the window, as in Finder.
private struct SidebarBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A titled group of settings on a rounded card, with hairlines between rows like System Settings.
private struct GlassSection<Content: View>: View {
    let title: String?
    var footer: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 10)
            }
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        row.padding(.vertical, 11)
                        if index < rows.count - 1 { Divider() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
            if let footer {
                Text(footer).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 10)
            }
        }
    }
}

/// A setting's name on the left and its control on the right.
private struct SettingRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            control
        }
        .frame(minHeight: 24)
    }
}

private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title) { Toggle(title, isOn: $isOn).labelsHidden() }
    }
}

/// The large icon, title and one-line summary at the top of each pane.
private struct PaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        HStack(spacing: 14) {
            PaneIcon(pane: pane, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(pane.title).font(.title2.weight(.semibold))
                Text(pane.summary).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
    }
}

/// A slider row with its value shown at the end.
private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let format: (Double) -> String

    var body: some View {
        SettingRow(title: title) {
            HStack(spacing: 10) {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
            .frame(width: 270)
        }
    }
}

private struct PickerRow<Option: Hashable & Identifiable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        SettingRow(title: title) {
            Picker(title, selection: $selection) {
                ForEach(options) { Text(label($0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

// MARK: - Panes

private struct GeneralPane: View {
    @ObservedObject var settings: Settings

    var body: some View {
        GlassSection(title: "Layout") {
            ChoiceTiles(options: CardLayout.allCases, selection: $settings.p.layout, label: \.label) { layout, selected in
                LayoutThumbnail(layout: layout, selected: selected)
            }
        }
        GlassSection(title: "App Icon") {
            IconPicker(selection: $settings.p.appIcon)
        }
        GlassSection(title: "Startup", footer: LoginItem.isInstalled ? nil : "Works once Lowkey is installed in Applications.") {
            ToggleRow(title: "Open at login", isOn: $settings.p.openAtLogin)
        }
        GlassSection(title: "Behavior", footer: "A video counts once it has played for about 12 seconds, so short clips in feeds don't hide the card. Press ⌃⌥⌘H to bring the card back during a video.") {
            ToggleRow(title: "Show playback controls", isOn: $settings.p.showControls)
            PickerRow(title: "Time bar", options: TimeBarStyle.allCases, selection: $settings.p.timeBar) { $0.label }
            if settings.p.timeBar == .betweenBlocks {
                PickerRow(title: "Time bar look", options: TimeBarLook.allCases, selection: $settings.p.timeBarLook) { $0.label }
            }
            ToggleRow(title: "Click a lyric line to jump to it", isOn: $settings.p.clickToSeek)
            ToggleRow(title: "Hide when paused", isOn: $settings.p.hideWhenPaused)
            ToggleRow(title: "Hide when no lyrics are found", isOn: $settings.p.hideWhenNoLyrics)
            ToggleRow(title: "Hide while a video is playing", isOn: $settings.p.hideDuringVideo)
        }
    }
}

private struct AppearancePane: View {
    @ObservedObject var settings: Settings

    private var customColor: Binding<Color> {
        Binding(get: { settings.customColor }, set: { settings.customColor = $0 })
    }

    var body: some View {
        GlassSection(title: "Background") {
            ChoiceTiles(options: BackgroundStyle.allCases, selection: $settings.p.backgroundStyle, label: \.label) { style, selected in
                BackgroundThumbnail(style: style, selected: selected)
            }
        }
        switch settings.p.backgroundStyle {
        case .albumColor:
            GlassSection(title: "Color") {
                ToggleRow(title: "Moving colors", isOn: $settings.p.showColorBlobs)
                ToggleRow(title: "Use colors from album art", isOn: $settings.p.useArtworkColors)
                    .disabled(!settings.p.showColorBlobs)
                if !settings.p.useArtworkColors {
                    SettingRow(title: "Custom color") {
                        ColorPicker("Custom color", selection: customColor, supportsOpacity: false).labelsHidden()
                    }
                }
                SliderRow(title: "Color strength", value: $settings.p.colorStrength, range: 0.3...1) { "\(Int($0 * 100))%" }
                    .disabled(!settings.p.showColorBlobs)
                SliderRow(title: "Darkness", value: $settings.p.panelOpacity, range: 0...0.9) { "\(Int($0 * 100))%" }
            }
            GlassSection(title: "Blur", footer: "Only visible when Color strength is below 100%.") {
                ToggleRow(title: "Blur windows behind", isOn: $settings.p.blurEnabled)
                SliderRow(title: "Blur strength", value: $settings.p.blurRadius, range: 1...60) { "\(Int($0))" }
                    .disabled(!settings.p.blurEnabled)
            }
        case .blurOnly:
            GlassSection(title: "Blur") {
                SliderRow(title: "Blur strength", value: $settings.p.blurRadius, range: 1...60) { "\(Int($0))" }
                SliderRow(title: "Darkness", value: $settings.p.glassDarkness, range: 0...0.6) { "\(Int($0 * 100))%" }
            }
        case .transparent:
            GlassSection(title: nil) {
                Text("Only the lyrics are shown, directly over your windows, with a soft shadow for contrast.")
                    .foregroundStyle(.secondary)
            }
        }
        if settings.p.backgroundStyle != .transparent {
            GlassSection(title: "Shape") {
                PickerRow(title: "Border", options: EdgeStyle.allCases, selection: $settings.p.edgeStyle) { $0.label }
                SliderRow(title: "Corner radius", value: $settings.p.cornerRadius, range: 0...40) { "\(Int($0))" }
            }
        }
    }
}

private struct LyricsPane: View {
    @ObservedObject var settings: Settings

    var body: some View {
        GlassSection(title: "Text") {
            SliderRow(title: "Font size", value: $settings.p.fontSize, range: 14...40, step: 1) { "\(Int($0)) pt" }
            SettingRow(title: "Visible lines") {
                Text("\(settings.p.visibleLines)").monospacedDigit().foregroundStyle(.secondary)
                Stepper("Visible lines", value: $settings.p.visibleLines, in: 1...6).labelsHidden()
            }
            .disabled(settings.p.cardHeight > 0)
            ToggleRow(title: "Show song title and art", isOn: $settings.p.showHeader)
        }
        GlassSection(title: "Motion") {
            ToggleRow(title: "Animations", isOn: $settings.p.animationsEnabled)
        }
        GlassSection(title: "Timing", footer: "Move this if the lyrics run ahead of or behind the song.") {
            SliderRow(title: "Sync offset", value: $settings.p.syncOffset, range: -2...2, step: 0.1) {
                String(format: "%+.1f s", $0)
            }
        }
    }
}

private struct PositionPane: View {
    @ObservedObject var settings: Settings
    var onEdit: () -> Void
    var onFullScreen: () -> Void

    var body: some View {
        GlassSection(title: "Position") {
            PickerRow(title: "Place on screen", options: Anchor.allCases, selection: $settings.p.anchor) { $0.label }
            SettingRow(title: "Move by hand") { Button("Edit on Screen…", action: onEdit) }
        }
        GlassSection(title: "Size", footer: "Hold ⌥ Option and drag the card to move it at any time.") {
            SliderRow(title: "Content size", value: $settings.p.scale, range: 0.7...3) { "\(Int(($0 * 100).rounded()))%" }
            ToggleRow(title: "Resize by dragging the card's edges", isOn: $settings.p.resizeFromEdges)
            SettingRow(title: "Card size") {
                Button("Use Automatic Size") {
                    settings.p.cardWidth = 0
                    settings.p.cardHeight = 0
                }
                .disabled(settings.p.cardWidth == 0 && settings.p.cardHeight == 0)
            }
            SettingRow(title: "Too big to grab?") {
                Button("Reset Size") {
                    settings.p.scale = 1
                    settings.p.cardWidth = 0
                    settings.p.cardHeight = 0
                    settings.p.anchor = .bottomRight
                }
            }
        }
        GlassSection(title: "Full Screen") {
            SettingRow(title: "Lyrics across the whole screen") {
                Button("Full Screen Lyrics", action: onFullScreen)
            }
        }
    }
}

private struct AboutPane: View {
    @ObservedObject var settings: Settings

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        GlassSection(title: nil) {
            HStack(spacing: 16) {
                IconArt(theme: settings.p.appIcon, size: 76, withMargin: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lowkey").font(.title2.weight(.semibold))
                    Text("Version \(version)").foregroundStyle(.secondary)
                    Text("Synced Spotify lyrics on every desktop. Lyrics by LRCLIB.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        GlassSection(title: "Shortcuts") {
            SettingRow(title: "Open Settings") { Text("⌃⌥⌘L").foregroundStyle(.secondary) }
            SettingRow(title: "Hide or show the card") { Text("⌃⌥⌘H").foregroundStyle(.secondary) }
            SettingRow(title: "Move the card") { Text("⌥ Option + drag").foregroundStyle(.secondary) }
            SettingRow(title: "Exit full screen") { Text("Esc").foregroundStyle(.secondary) }
        }
        GlassSection(title: nil) {
            SettingRow(title: "Start over") {
                Button("Reset All Settings", role: .destructive) { settings.resetToDefaults() }
            }
        }
    }
}

// MARK: - Picture choices

/// A row of picture tiles with a caption under each; the chosen one gets an accent ring.
private struct ChoiceTiles<Option: Hashable & Identifiable, Tile: View>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: KeyPath<Option, String>
    @ViewBuilder let tile: (Option, Bool) -> Tile

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(options) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    VStack(spacing: 7) {
                        tile(option, selected)
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5))
                        Text(option[keyPath: label])
                            .font(.callout.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// A desktop-like backdrop for the little previews.
private struct PreviewBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0x3B4A6B), Color(hex: 0x6B4B6E), Color(hex: 0xA8664F)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct LayoutThumbnail: View {
    let layout: CardLayout
    let selected: Bool

    private let glass = Color.white.opacity(0.22)
    private let edge = Color.white.opacity(0.4)

    var body: some View {
        ZStack {
            PreviewBackdrop()
            switch layout {
            case .twoBlocks:
                VStack(spacing: 4) {
                    block(height: 18) { art; bars(2); Spacer(); dots }
                    block(height: 30) { lines }
                }
            case .roundButtons:
                VStack(spacing: 4) {
                    HStack(spacing: 3) {
                        block(height: 16) { art; bars(2) }
                        ForEach(0..<3, id: \.self) { _ in Circle().fill(glass).overlay(Circle().strokeBorder(edge, lineWidth: 0.5)).frame(width: 16, height: 16) }
                    }
                    block(height: 30) { lines }
                }
            case .classic:
                block(height: 52) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) { art; bars(2) }
                        lines
                    }
                }
            }
        }
        .frame(width: 112, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var art: some View {
        RoundedRectangle(cornerRadius: 2).fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
            .frame(width: 10, height: 10)
    }

    private func bars(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                Capsule().fill(.white.opacity(index == 0 ? 0.9 : 0.5)).frame(width: index == 0 ? 22 : 14, height: 2.5)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 2.5) { ForEach(0..<3, id: \.self) { _ in Circle().fill(.white).frame(width: 3, height: 3) } }
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(.white).frame(width: 48, height: 4)
            Capsule().fill(.white.opacity(0.5)).frame(width: 36, height: 4)
            Capsule().fill(.white.opacity(0.3)).frame(width: 26, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func block<Content: View>(height: Double, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) { content() }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(glass))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(edge, lineWidth: 0.5))
            .padding(.horizontal, 12)
    }
}

private struct BackgroundThumbnail: View {
    let style: BackgroundStyle
    let selected: Bool

    var body: some View {
        ZStack {
            PreviewBackdrop()
            // A pretend window behind the card, so the blur and transparency read.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<6, id: \.self) { index in
                    Capsule().fill(.white.opacity(0.55)).frame(width: [60, 44, 70, 38, 56, 48][index], height: 3)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            card
        }
        .frame(width: 112, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let text = VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(.white).frame(width: 44, height: 4)
            Capsule().fill(.white.opacity(0.5)).frame(width: 30, height: 4)
        }
        .padding(8)
        .frame(width: 76, height: 36, alignment: .leading)
        switch style {
        case .albumColor:
            text.background(shape.fill(LinearGradient(colors: [Color(hex: 0x6B4DFF), Color(hex: 0xC2477A), Color(hex: 0xFF8A3D)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
        case .blurOnly:
            text.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
        case .transparent:
            text.shadow(color: .black.opacity(0.5), radius: 2)
        }
    }
}
