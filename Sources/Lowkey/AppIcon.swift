import AppKit
import SwiftUI

/// The app icon's color sets. Night Flame is the primary icon; the rest can be picked in Settings.
enum IconTheme: String, Codable, CaseIterable, Identifiable {
    case nightFlame, midnight, mint, ocean, graphite, white
    var id: String { rawValue }

    var name: String {
        switch self {
        case .nightFlame: return "Night Flame"
        case .midnight: return "Midnight"
        case .mint: return "Mint"
        case .ocean: return "Ocean"
        case .graphite: return "Graphite"
        case .white: return "White"
        }
    }

    fileprivate struct Glow {
        let color: Color
        let center: UnitPoint
        let reach: Double   // radius as a share of the icon
    }

    fileprivate var base: (top: Color, bottom: Color) {
        switch self {
        case .nightFlame: return (Color(hex: 0x2B1D52), Color(hex: 0x120F22))
        case .midnight: return (Color(hex: 0x0F1F4A), Color(hex: 0x060B1C))
        case .mint: return (Color(hex: 0x0F5A5A), Color(hex: 0x121233))
        case .ocean: return (Color(hex: 0x04364D), Color(hex: 0x04122A))
        case .graphite: return (Color(hex: 0x3A3B42), Color(hex: 0x121216))
        case .white: return (Color(hex: 0xF3F2F7), Color(hex: 0xD9D7E3))
        }
    }

    fileprivate var glows: [Glow] {
        switch self {
        case .nightFlame:
            return [Glow(color: Color(hex: 0xFF7A3D), center: .bottomLeading, reach: 0.66),
                    Glow(color: Color(hex: 0x6B4DFF), center: .topTrailing, reach: 0.56)]
        case .midnight:
            return [Glow(color: Color(hex: 0x3D7BFF), center: .topTrailing, reach: 0.6),
                    Glow(color: Color(hex: 0x1FD1FF), center: .bottomLeading, reach: 0.45)]
        case .mint:
            return [Glow(color: Color(hex: 0x3FF2C0), center: .topLeading, reach: 0.6),
                    Glow(color: Color(hex: 0x4B3CFF), center: .bottomTrailing, reach: 0.6)]
        case .ocean:
            return [Glow(color: Color(hex: 0x00E0D0), center: .bottomLeading, reach: 0.6),
                    Glow(color: Color(hex: 0x2A6BFF), center: .topTrailing, reach: 0.6)]
        case .graphite:
            return [Glow(color: .white.opacity(0.22), center: UnitPoint(x: 0.3, y: 0), reach: 0.6)]
        case .white:
            return [Glow(color: .white, center: .top, reach: 0.7)]
        }
    }

    fileprivate var shapeColor: Color { self == .white ? Color(hex: 0x1B1830) : .white }
}

/// The icon artwork: five shapes rising like the letters of a sung line.
struct IconArt: View {
    let theme: IconTheme
    let size: Double
    /// App icons leave a margin around the tile, as macOS expects.
    var withMargin = true

    var body: some View {
        let tile = withMargin ? size * 0.805 : size
        ZStack {
            ZStack {
                LinearGradient(colors: [theme.base.top, theme.base.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                ForEach(Array(theme.glows.enumerated()), id: \.offset) { _, glow in
                    RadialGradient(colors: [glow.color, glow.color.opacity(0)], center: glow.center,
                                   startRadius: 0, endRadius: tile * glow.reach * 1.1)
                }
                shapes(tile)
            }
            .frame(width: tile, height: tile)
            .clipShape(RoundedRectangle(cornerRadius: tile * 0.224, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: tile * 0.224, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)], startPoint: .top, endPoint: .center),
                                  lineWidth: max(1, tile * 0.004)))
            .shadow(color: .black.opacity(withMargin ? 0.3 : 0), radius: tile * 0.03, y: tile * 0.015)
        }
        .frame(width: size, height: size)
    }

    private func shapes(_ tile: Double) -> some View {
        let width = tile * 0.11, height = tile * 0.2, gap = tile * 0.04
        let rises = [0.09, 0.09, 0.05, 0, 0]
        let opacity = [1, 1, 0.85, 0.36, 0.36]
        return HStack(alignment: .top, spacing: gap) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: width * 0.24, style: .continuous)
                    .fill(theme.shapeColor.opacity(opacity[index]))
                    .frame(width: width, height: height)
                    .offset(y: -tile * rises[index])
            }
        }
        .offset(y: tile * 0.045)
    }
}

enum AppIcon {
    @MainActor
    static func image(_ theme: IconTheme, size: Double = 1024) -> NSImage? {
        let renderer = ImageRenderer(content: IconArt(theme: theme, size: size))
        renderer.scale = 1
        return renderer.nsImage
    }

    /// Shows the chosen icon in Finder and Launchpad. Night Flame is built into the app, so choosing it
    /// removes the custom icon instead of storing a copy.
    @MainActor
    static func apply(_ theme: IconTheme) {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { return }
        let image = theme == .nightFlame ? nil : Self.image(theme)
        NSWorkspace.shared.setIcon(image, forFile: path, options: [])
        NSApp.applicationIconImage = image ?? NSImage(named: NSImage.applicationIconName)
    }

    /// Used by the build script to make the bundled icon from the same drawing.
    @MainActor
    static func exportIconSet(to folder: String) -> Bool {
        let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for (points, scale) in sizes {
            guard let image = image(.nightFlame, size: Double(points * scale)),
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            guard (try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))) != nil else { return false }
        }
        return true
    }

    /// The menu bar version: the same rising shapes as a template image, so macOS tints it.
    static let menuBarGlyph: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let width = 2.6, height = 4.4, gap = 0.9
            let rises = [2.6, 2.6, 1.4, 0, 0], alpha = [1, 1, 1, 0.45, 0.45]
            var x = (18 - (width * 5 + gap * 4)) / 2
            let top = (18 - height) / 2 + 1.3
            for index in 0..<5 {
                NSColor.black.withAlphaComponent(alpha[index]).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: top - rises[index], width: width, height: height), xRadius: 1, yRadius: 1).fill()
                x += width + gap
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Picker of small icon previews; the selected one gets a ring.
struct IconPicker: View {
    @Binding var selection: IconTheme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(IconTheme.allCases) { theme in
                Button { selection = theme } label: {
                    VStack(spacing: 5) {
                        IconArt(theme: theme, size: 46, withMargin: false)
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(selection == theme ? Color.accentColor : .clear, lineWidth: 2))
                        Text(theme.name).font(.caption).foregroundStyle(selection == theme ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(theme.name) icon")
                .accessibilityAddTraits(selection == theme ? .isSelected : [])
            }
        }
    }
}
