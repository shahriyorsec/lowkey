import Foundation

struct LyricWord: Identifiable {
    let id: Int
    let text: String
    let from: Double   // share of the line's sung time, 0...1
    let to: Double
}

struct LyricLine: Identifiable {
    let id: Int
    let start: Double
    let sungDuration: Double
    let words: [LyricWord]
    var isInterlude: Bool { words.isEmpty }
    var text: String { words.map(\.text).joined(separator: " ") }

    /// LRC only times whole lines, so word timing is estimated from word length.
    func progress(of word: LyricWord, at time: Double) -> Double {
        let lineProgress = (time - start) / sungDuration
        return min(1, max(0, (lineProgress - word.from) / max(0.001, word.to - word.from)))
    }
}

enum LRC {
    static func parse(_ source: String) -> [LyricLine] {
        let pattern = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[.:]\d+)?)\]"#)
        var stamped: [(Double, String)] = []
        for raw in source.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = pattern.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: match.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                stamped.append((minutes * 60 + seconds, text))
            }
        }
        stamped.sort { $0.0 < $1.0 }

        // Blank LRC lines mark instrumental gaps: keep one of each run.
        var cleaned: [(Double, String)] = []
        for item in stamped {
            if item.1.isEmpty && (cleaned.isEmpty || cleaned.last!.1.isEmpty) { continue }
            cleaned.append(item)
        }
        return build(withInterludes(cleaned))
    }

    /// Adds an interlude before a late first line and in long silences the source left unmarked.
    private static func withInterludes(_ items: [(Double, String)]) -> [(Double, String)] {
        var result: [(Double, String)] = []
        if let first = items.first, first.0 > 3 { result.append((0, "")) }
        for (index, item) in items.enumerated() {
            result.append(item)
            guard index + 1 < items.count, !item.1.isEmpty, !items[index + 1].1.isEmpty else { continue }
            let sung = sungEstimate(item.1)
            if items[index + 1].0 - item.0 - sung > 6 { result.append((item.0 + sung + 0.6, "")) }
        }
        return result
    }

    private static func sungEstimate(_ text: String) -> Double {
        Double(text.count + 1) * 0.11 + 1.0
    }

    static func build(_ items: [(Double, String)]) -> [LyricLine] {
        items.enumerated().map { index, item in
            let next = index + 1 < items.count ? items[index + 1].0 : item.0 + 5
            let pieces = item.1.split(separator: " ").map(String.init)
            let total = max(1, pieces.reduce(0) { $0 + $1.count + 1 })
            var used = 0
            let words: [LyricWord] = pieces.enumerated().map { wordIndex, piece in
                let from = Double(used) / Double(total)
                used += piece.count + 1
                return LyricWord(id: wordIndex, text: piece, from: from, to: Double(used) / Double(total))
            }
            // A pause after a line must not stretch the singing across the whole gap.
            // It also ends just before the next line takes over, so the fill never snaps.
            let estimated = pieces.isEmpty ? next - item.0 : Double(total) * 0.11 + 1.0
            let sung = max(0.4, min(next - item.0 - NowPlaying.lineLead, estimated))
            return LyricLine(id: index, start: item.0, sungDuration: sung, words: words)
        }
    }

    static let sample: [LyricLine] = build([
        (0.0, "Drag Lowkey wherever you like"),
        (3.6, "Pull the corner to resize it"),
        (7.2, "Change blur and colors in Settings"),
        (10.8, "Press Done when it looks right"),
    ])
    static let sampleLength = 14.4
}

/// Time-synced lyrics from LRCLIB (https://lrclib.net).
enum LRCLib {
    private struct Record: Decodable {
        let syncedLyrics: String?
        let duration: Double?
    }

    private static func request(_ path: String, _ query: [String: String]) async -> Data? {
        var parts = URLComponents(string: "https://lrclib.net/api/\(path)")!
        parts.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: parts.url!)
        request.timeoutInterval = 12
        request.setValue("Lowkey/0.1", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// "Song - Remastered 2011" and "Song (feat. X)" often miss; the bare title matches.
    private static func simplified(_ title: String) -> String {
        var result = title
        for separator in [" - ", " (", " ["] {
            if let range = result.range(of: separator) { result = String(result[..<range.lowerBound]) }
        }
        return result
    }

    static func fetch(title: String, artist: String, album: String, duration: Double) async -> [LyricLine] {
        let exact = ["track_name": title, "artist_name": artist, "album_name": album, "duration": String(Int(duration.rounded()))]
        if let data = await request("get", exact),
           let record = try? JSONDecoder().decode(Record.self, from: data),
           let synced = record.syncedLyrics, !synced.isEmpty {
            return LRC.parse(synced)
        }
        let query = ["track_name": simplified(title), "artist_name": artist]
        guard let data = await request("search", query),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        let match = records.first {
            guard let synced = $0.syncedLyrics, !synced.isEmpty else { return false }
            return abs(($0.duration ?? duration) - duration) <= 4
        }
        return match?.syncedLyrics.map(LRC.parse) ?? []
    }
}
