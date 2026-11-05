import AppKit

struct RGB: Equatable {
    var r, g, b: Double

    func distance(to other: RGB) -> Double {
        // Weighted for how the eye separates colors.
        let dr = r - other.r, dg = g - other.g, db = b - other.b
        return (2 * dr * dr + 4 * dg * dg + 3 * db * db).squareRoot()
    }

    func mixed(with other: RGB, _ amount: Double) -> RGB {
        RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
    }

    var hsb: (h: Double, s: Double, b: Double) {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
        NSColor(deviceRed: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: nil)
        return (h, s, v)
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(h: Double, s: Double, b: Double) {
        let c = NSColor(deviceHue: h, saturation: s, brightness: b, alpha: 1)
        self.init(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
    }
}

/// Turns a cover into the 16 colors of the background mesh, keeping its small accents as well as its main colors.
enum CoverColors {
    static let cellCount = 16

    static func meshColors(from image: NSImage) -> [RGB]? {
        let pixels = samplePixels(of: image)
        guard !pixels.isEmpty else { return nil }
        return arrange(clusters(of: pixels, count: 7))
    }

    /// Variations of one color, for when the user picks their own.
    static func meshColors(fromCustom color: RGB) -> [RGB] {
        let (h, s, b) = color.hsb
        let shades = [(0.0, 1.0, 1.0), (0.035, 0.95, 0.8), (-0.035, 1.05, 0.65), (0.07, 0.8, 0.95), (-0.07, 1.1, 0.5)]
        let list = shades.map { offset, satScale, brightScale in
            RGB(h: (h + offset + 1).truncatingRemainder(dividingBy: 1), s: min(1, s * satScale), b: min(1, b * brightScale))
        }
        return arrange(list.map { ($0, 1.0) })
    }

    static let fallback: [RGB] = meshColors(fromCustom: RGB(r: 0.55, g: 0.3, b: 0.8))

    private static func samplePixels(of image: NSImage) -> [RGB] {
        let side = 28
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return [] }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        var result: [RGB] = []
        for x in 0..<side {
            for y in 0..<side {
                if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    result.append(RGB(r: c.redComponent, g: c.greenComponent, b: c.blueComponent))
                }
            }
        }
        return result
    }

    /// K-means seeded with the colors farthest apart, so rare accents get a cluster of their own.
    private static func clusters(of pixels: [RGB], count: Int) -> [(color: RGB, share: Double)] {
        var centers = [pixels.max { $0.hsb.s * $0.hsb.b < $1.hsb.s * $1.hsb.b }!]
        while centers.count < count {
            guard let far = pixels.max(by: { a, b in
                centers.map { a.distance(to: $0) }.min()! < centers.map { b.distance(to: $0) }.min()!
            }) else { break }
            centers.append(far)
        }
        var members = [[RGB]](repeating: [], count: centers.count)
        for _ in 0..<8 {
            members = [[RGB]](repeating: [], count: centers.count)
            for pixel in pixels {
                let nearest = centers.indices.min { pixel.distance(to: centers[$0]) < pixel.distance(to: centers[$1]) }!
                members[nearest].append(pixel)
            }
            for index in centers.indices where !members[index].isEmpty {
                let n = Double(members[index].count)
                centers[index] = RGB(r: members[index].reduce(0) { $0 + $1.r } / n,
                                     g: members[index].reduce(0) { $0 + $1.g } / n,
                                     b: members[index].reduce(0) { $0 + $1.b } / n)
            }
        }
        var merged: [(color: RGB, share: Double)] = []
        let found = centers.indices.map { (centers[$0], Double(members[$0].count) / Double(pixels.count)) }
        for item in found.sorted(by: { $0.1 > $1.1 }) where item.1 > 0.004 {
            if let same = merged.firstIndex(where: { $0.color.distance(to: item.0) < 0.12 }) {
                merged[same].share += item.1
            } else {
                merged.append((item.0, item.1))
            }
        }
        return merged
    }

    /// Keeps the background clean: grays and near-blacks are dropped when the cover has real color,
    /// and colors sit next to their closest hues, so they never blend through gray where they meet.
    private static func arrange(_ list: [(color: RGB, share: Double)]) -> [RGB] {
        let colorful = list.filter { $0.color.hsb.s >= 0.2 && $0.color.hsb.b >= 0.2 }
        let usable = colorful.reduce(0) { $0 + $1.share } >= 0.1 ? colorful : list
        var swatches = usable.map { item -> (color: RGB, weight: Double) in
            let (h, s, b) = item.color.hsb
            let isGray = s < 0.2
            let lifted = RGB(h: h, s: isGray ? s : min(1, s * 1.3 + 0.1), b: min(0.86, max(isGray ? 0.3 : 0.5, b * 1.08)))
            return (lifted, item.share.squareRoot())
        }
        // A nearly single-color cover still needs movement, so it gets neighboring hues.
        if swatches.count < 3, let main = swatches.first {
            let (h, s, b) = main.color.hsb
            swatches.append((RGB(h: (h + 0.05).truncatingRemainder(dividingBy: 1), s: s, b: max(0.3, b * 0.7)), main.weight * 0.6))
            swatches.append((RGB(h: (h + 0.95).truncatingRemainder(dividingBy: 1), s: s * 0.9, b: min(0.9, b * 1.15)), main.weight * 0.6))
        }
        swatches.sort { $0.color.hsb.h < $1.color.hsb.h }

        let total = swatches.reduce(0) { $0 + $1.weight }
        var ordered: [RGB] = []
        for swatch in swatches {
            ordered += Array(repeating: swatch.color, count: max(1, Int((swatch.weight / total * Double(cellCount)).rounded())))
        }
        while ordered.count < cellCount { ordered.append(ordered.last ?? RGB(r: 0.3, g: 0.3, b: 0.3)) }
        ordered = Array(ordered.prefix(cellCount))

        // Snake down the 4×4 grid, so each cell also touches its neighbors in hue order.
        var cells = ordered
        for row in 0..<4 {
            for column in 0..<4 {
                cells[row * 4 + column] = ordered[row * 4 + (row % 2 == 0 ? column : 3 - column)]
            }
        }
        return cells
    }
}
