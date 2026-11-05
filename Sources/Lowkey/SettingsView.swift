import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    var onEdit: () -> Void
    var onFullScreen: () -> Void

    private var customColor: Binding<Color> {
        Binding(get: { settings.customColor }, set: { settings.customColor = $0 })
    }

    var body: some View {
        Form {
            Section("Layout") {
                Picker("Layout", selection: $settings.p.layout) {
                    ForEach(CardLayout.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section("Background") {
                Picker("Style", selection: $settings.p.backgroundStyle) {
                    ForEach(BackgroundStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                switch settings.p.backgroundStyle {
                case .albumColor:
                    Toggle("Blur windows behind", isOn: $settings.p.blurEnabled)
                    blurStrength.disabled(!settings.p.blurEnabled)
                    labeled("Darkness", value: "\(Int(settings.p.panelOpacity * 100))%") {
                        Slider(value: $settings.p.panelOpacity, in: 0...0.9)
                    }
                    Toggle("Moving colors", isOn: $settings.p.showColorBlobs)
                    labeled("Color strength", value: "\(Int(settings.p.colorStrength * 100))%") {
                        Slider(value: $settings.p.colorStrength, in: 0.3...1)
                    }
                    .disabled(!settings.p.showColorBlobs)
                    Toggle("Use colors from album art", isOn: $settings.p.useArtworkColors)
                    ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
                        .disabled(settings.p.useArtworkColors)
                case .blurOnly:
                    blurStrength
                    labeled("Darkness", value: "\(Int(settings.p.glassDarkness * 100))%") {
                        Slider(value: $settings.p.glassDarkness, in: 0...0.6)
                    }
                case .transparent:
                    Text("Only the lyrics are shown, directly over your windows.")
                        .foregroundStyle(.secondary)
                }
                if settings.p.backgroundStyle != .transparent {
                    Picker("Border", selection: $settings.p.edgeStyle) {
                        ForEach(EdgeStyle.allCases) { Text($0.label).tag($0) }
                    }
                }
                labeled("Corner radius", value: "\(Int(settings.p.cornerRadius))") {
                    Slider(value: $settings.p.cornerRadius, in: 0...40)
                }
                .disabled(settings.p.backgroundStyle == .transparent)
            }
            Section("Lyrics") {
                labeled("Font size", value: "\(Int(settings.p.fontSize))") {
                    Slider(value: $settings.p.fontSize, in: 14...40, step: 1)
                }
                Stepper("Visible lines: \(settings.p.visibleLines)", value: $settings.p.visibleLines, in: 1...6)
                    .disabled(settings.p.cardHeight > 0)
                Toggle("Show song title and art", isOn: $settings.p.showHeader)
                Toggle("Animations", isOn: $settings.p.animationsEnabled)
                labeled("Sync offset", value: String(format: "%+.1f s", settings.p.syncOffset)) {
                    Slider(value: $settings.p.syncOffset, in: -2...2, step: 0.1)
                }
            }
            Section("Position and size") {
                Picker("Position", selection: $settings.p.anchor) {
                    ForEach(Anchor.allCases) { Text($0.label).tag($0) }
                }
                labeled("Content size", value: "\(Int((settings.p.scale * 100).rounded()))%") {
                    Slider(value: $settings.p.scale, in: 0.7...3)
                }
                Toggle("Resize by dragging the card's edges", isOn: $settings.p.resizeFromEdges)
                Button("Move and resize on screen…", action: onEdit)
                Button("Automatic card size") {
                    settings.p.cardWidth = 0
                    settings.p.cardHeight = 0
                }
                .disabled(settings.p.cardWidth == 0 && settings.p.cardHeight == 0)
                Button("Full Screen Lyrics", action: onFullScreen)
            }
            Section("Behavior") {
                Toggle("Show playback controls", isOn: $settings.p.showControls)
                Toggle("Click a lyric line to jump to it", isOn: $settings.p.clickToSeek)
                Toggle("Hide when paused", isOn: $settings.p.hideWhenPaused)
                Toggle("Hide when no lyrics are found", isOn: $settings.p.hideWhenNoLyrics)
            }
            Section {
                Button("Reset to defaults", role: .destructive) { settings.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
    }

    private var blurStrength: some View {
        labeled("Blur strength", value: "\(Int(settings.p.blurRadius))") {
            Slider(value: $settings.p.blurRadius, in: 1...60)
        }
    }

    private func labeled<Content: View>(_ title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        LabeledContent {
            HStack {
                content()
                Text(value).monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}
