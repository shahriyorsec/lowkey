import AppKit
import SwiftUI

enum Anchor: String, Codable, CaseIterable, Identifiable {
    case bottomRight, bottomCenter, bottomLeft, topRight, topCenter, topLeft, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bottomRight: return "Bottom right"
        case .bottomCenter: return "Bottom center"
        case .bottomLeft: return "Bottom left"
        case .topRight: return "Top right"
        case .topCenter: return "Top center"
        case .topLeft: return "Top left"
        case .custom: return "Custom"
        }
    }
}

enum CardLayout: String, Codable, CaseIterable, Identifiable {
    case twoBlocks, roundButtons, classic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .twoBlocks: return "Two Blocks"
        case .roundButtons: return "Round Buttons"
        case .classic: return "Classic"
        }
    }
}

enum BackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case albumColor, blurOnly, transparent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .albumColor: return "Album Color"
        case .blurOnly: return "Blur Only"
        case .transparent: return "Transparent"
        }
    }
}

/// Every user-tunable value.
struct Prefs: Codable, Equatable {
    var layout = CardLayout.twoBlocks
    var backgroundStyle = BackgroundStyle.albumColor
    var glassDarkness = 0.14
    var showControls = true
    var clickToSeek = true
    var blurEnabled = true
    var blurRadius = 34.0
    var panelOpacity = 0.24
    var colorStrength = 1.0
    var cornerRadius = 24.0
    var useArtworkColors = true
    var showColorBlobs = true
    var customR = 0.54, customG = 0.30, customB = 1.0

    var fontSize = 22.0
    var visibleLines = 3
    var animationsEnabled = true
    var showHeader = true
    var syncOffset = 0.0

    var anchor = Anchor.bottomRight
    var customX = 0.0   // top-left corner, global screen coordinates
    var customY = 0.0
    var scale = 1.0
    var cardWidth = 0.0    // 0 means automatic
    var cardHeight = 0.0

    var hideWhenPaused = true
    var hideWhenNoLyrics = false
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private static let key = "prefs.v1"

    @Published var p: Prefs {
        didSet {
            if p != oldValue, let data = try? JSONEncoder().encode(p) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
    }

    private init() {
        p = Self.load() ?? Prefs()
    }

    /// Saved values laid over the defaults, so settings added in a new version don't lose the old ones.
    private static func load() -> Prefs? {
        guard let saved = UserDefaults.standard.data(forKey: key),
              let savedFields = try? JSONSerialization.jsonObject(with: saved) as? [String: Any],
              let defaults = try? JSONEncoder().encode(Prefs()),
              let defaultFields = try? JSONSerialization.jsonObject(with: defaults) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: defaultFields.merging(savedFields) { $1 })
        else { return nil }
        return try? JSONDecoder().decode(Prefs.self, from: merged)
    }

    func resetToDefaults() { p = Prefs() }

    var customRGB: RGB { RGB(r: p.customR, g: p.customG, b: p.customB) }

    var customColor: Color {
        get { Color(red: p.customR, green: p.customG, blue: p.customB) }
        set {
            guard let c = NSColor(newValue).usingColorSpace(.deviceRGB) else { return }
            p.customR = c.redComponent
            p.customG = c.greenComponent
            p.customB = c.blueComponent
        }
    }
}
