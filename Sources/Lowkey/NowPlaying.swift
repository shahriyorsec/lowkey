import AppKit
import Combine
import SwiftUI

struct Track: Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let artworkURL: String
}

enum LyricsState: Equatable { case idle, loading, ready, missing }

/// Follows the Spotify app over AppleScript and holds the song's lyrics and colors.
final class NowPlaying: ObservableObject {
    @Published private(set) var track: Track?
    /// Where the time bar is being dragged to, as a share of the song; nil when not dragging.
    @Published var scrubFraction: Double?
    /// The pointer is on the cover art, which then offers to hide the card.
    @Published var isHoveringCover = false
    /// The line the lyrics are scrolled to while browsing with the scroll wheel; nil follows the song.
    @Published private(set) var browseAnchor: Int?
    private var browseReset: DispatchWorkItem?

    /// Moves the lyrics by whole lines. A few seconds after the last scroll they glide back to the song.
    func browse(by step: Int) {
        let lines = displayLines
        guard !lines.isEmpty, step != 0 else { return }
        let start = browseAnchor ?? max(currentIndex, 0)
        browseAnchor = min(lines.count - 1, max(0, start + step))
        browseReset?.cancel()
        let reset = DispatchWorkItem { [weak self] in self?.browseAnchor = nil }
        browseReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: reset)
    }

    func stopBrowsing() {
        browseReset?.cancel()
        browseAnchor = nil
    }
    @Published private(set) var isPlaying = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var lyricsState = LyricsState.idle
    @Published private(set) var currentIndex = -1
    @Published private(set) var artwork: NSImage?
    @Published var isHovering = false
    @Published private(set) var meshColors: [RGB] = CoverColors.fallback
    /// The colors the background is blending away from, and when the blend began.
    private(set) var meshFrom: [RGB] = CoverColors.fallback
    private(set) var meshChangedAt = Date.distantPast
    static let meshBlend = 1.4
    /// Covers and their colors already worked out, so going back to a song recolors at once.
    private var coverCache: [String: (image: NSImage, colors: [RGB]?)] = [:]

    /// Starts a blend from whatever is showing right now, even halfway through an earlier blend,
    /// so a quick skip never makes the colors jump.
    private func setMesh(_ colors: [RGB]) {
        guard colors != meshColors else { return }
        let progress = min(1, max(0, Date().timeIntervalSince(meshChangedAt) / Self.meshBlend))
        if progress < 1, meshFrom.count == meshColors.count {
            meshFrom = zip(meshFrom, meshColors).map { $0.mixed(with: $1, progress) }
        } else {
            meshFrom = meshColors
        }
        meshChangedAt = Date()
        meshColors = colors
    }
    @Published private(set) var lineHeights: [Int: CGFloat] = [:]
    @Published var isSampleMode = false {
        didSet {
            lineHeights = [:]
            updateIndex()
        }
    }

    /// Lines start moving this early, so they've arrived when the singing starts.
    static let lineLead = 0.2

    private var ignorePositionUntil = Date.distantPast
    private var anchorPosition = 0.0
    private var anchorDate = Date()
    private let sampleEpoch = Date()
    private let scriptQueue = DispatchQueue(label: "app.lowkey.spotify")
    private var script: NSAppleScript?
    private var timers: [Timer] = []
    private var cache: [String: [LyricLine]] = [:]
    private var lyricsTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?

    /// Jumps the song to a time. The display moves at once, and the next few polls are ignored,
    /// since Spotify can still report the old position for a moment.
    func seek(to time: Double) {
        stopBrowsing()
        let target = max(0, time)
        anchorPosition = target - Settings.shared.p.syncOffset
        anchorDate = Date()
        ignorePositionUntil = Date().addingTimeInterval(0.8)
        updateIndex()
        send("set player position to \(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), max(0, anchorPosition)))")
    }

    func playPause() {
        isPlaying.toggle()
        send("playpause")
    }
    func nextTrack() { send("next track") }
    func previousTrack() { send("previous track") }

    private func send(_ command: String) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first != nil else { return }
        scriptQueue.async { [weak self] in
            NSAppleScript(source: "tell application \"Spotify\" to \(command)")?.executeAndReturnError(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.poll() }
        }
    }

    private let source = """
    tell application "Spotify"
        if player state is stopped then return {"stopped"}
        set t to current track
        return {player state as text, id of t, name of t, artist of t, album of t, duration of t, player position, artwork url of t}
    end tell
    """

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(playbackChanged),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)
        timers = [
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() },
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateIndex() },
        ]
        poll()
    }

    @objc private func playbackChanged() { poll() }

    func recordHeights(_ measured: [Int: CGFloat]) {
        let merged = lineHeights.merging(measured) { $1 }
        if merged != lineHeights { lineHeights = merged }
    }

    /// Position in the song, adjusted by the user's sync offset.
    func time(at date: Date) -> Double {
        if isSampleMode && track == nil {
            return date.timeIntervalSince(sampleEpoch).truncatingRemainder(dividingBy: LRC.sampleLength)
        }
        let elapsed = isPlaying ? date.timeIntervalSince(anchorDate) : 0
        return anchorPosition + elapsed + Settings.shared.p.syncOffset
    }

    /// Where the song really is, without the sync offset, for the time bar.
    func playbackPosition(at date: Date) -> Double {
        time(at: date) - (isSampleMode && track == nil ? 0 : Settings.shared.p.syncOffset)
    }

    var displayDuration: Double { isSampleMode && track == nil ? LRC.sampleLength : (track?.duration ?? 0) }

    /// Jumps to a share of the song, from the time bar.
    func seek(toFraction fraction: Double) {
        guard track != nil, displayDuration > 0 else { return }
        seek(to: min(1, max(0, fraction)) * displayDuration + Settings.shared.p.syncOffset)
    }

    var displayLines: [LyricLine] { isSampleMode && track == nil ? LRC.sample : lines }
    var displayPlaying: Bool { isPlaying || (isSampleMode && track == nil) }

    private func poll() {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first != nil else {
            apply(nil, playing: false, position: 0)
            return
        }
        scriptQueue.async { [weak self] in self?.runScript() }
    }

    private func runScript() {
        if script == nil {
            script = NSAppleScript(source: source)
            script?.compileAndReturnError(nil)
        }
        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error) else {
            let denied = (error?[NSAppleScript.errorNumber] as? Int) == -1743
            DispatchQueue.main.async { [weak self] in
                self?.permissionDenied = denied
                self?.apply(nil, playing: false, position: 0)
            }
            return
        }
        func text(_ i: Int) -> String { result.atIndex(i)?.stringValue ?? "" }
        guard text(1) != "stopped", result.numberOfItems >= 8 else {
            DispatchQueue.main.async { [weak self] in
                self?.permissionDenied = false
                self?.apply(nil, playing: false, position: 0)
            }
            return
        }
        let track = Track(id: text(2), title: text(3), artist: text(4), album: text(5),
                          duration: (result.atIndex(6)?.doubleValue ?? 0) / 1000, artworkURL: text(8))
        let position = result.atIndex(7)?.doubleValue ?? 0
        let playing = text(1) == "playing"
        DispatchQueue.main.async { [weak self] in
            self?.permissionDenied = false
            self?.apply(track, playing: playing, position: position)
        }
    }

    private func apply(_ newTrack: Track?, playing: Bool, position: Double) {
        let changed = newTrack != track
        if changed { track = newTrack }
        if isPlaying != playing { isPlaying = playing }

        // Smooth clock between polls: only snap back when Spotify really disagrees (a seek).
        let now = Date()
        let predicted = anchorPosition + (playing ? now.timeIntervalSince(anchorDate) : 0)
        let settling = !changed && now < ignorePositionUntil
        if !settling && (changed || !playing || abs(predicted - position) > 0.3) {
            anchorPosition = position
            anchorDate = now
        }
        if changed { loadExtras(for: newTrack) }
        updateIndex()
    }

    private func loadExtras(for track: Track?) {
        lyricsTask?.cancel()
        artworkTask?.cancel()
        currentIndex = -1
        lineHeights = [:]
        guard let track else {
            lines = []; lyricsState = .idle; artwork = nil; setMesh(CoverColors.fallback)
            return
        }
        if let cached = cache[track.id] {
            lines = cached
            lyricsState = cached.isEmpty ? .missing : .ready
        } else {
            lines = []
            lyricsState = .loading
            lyricsTask = Task { [weak self] in
                let found = await LRCLib.fetch(title: track.title, artist: track.artist, album: track.album, duration: track.duration)
                await MainActor.run {
                    guard let self, !Task.isCancelled, self.track?.id == track.id else { return }
                    self.cache[track.id] = found
                    self.lines = found
                    self.lyricsState = found.isEmpty ? .missing : .ready
                    self.updateIndex()
                }
            }
        }
        if let cached = coverCache[track.artworkURL] {
            artwork = cached.image
            if let colors = cached.colors { setMesh(colors) }
            return
        }
        artworkTask = Task { [weak self] in
            guard let url = URL(string: track.artworkURL),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            let colors = CoverColors.meshColors(from: image)
            await MainActor.run {
                guard let self else { return }
                if self.coverCache.count > 40 { self.coverCache.removeAll() }
                self.coverCache[track.artworkURL] = (image, colors)
                guard !Task.isCancelled, self.track?.id == track.id else { return }
                self.artwork = image
                if let colors { self.setMesh(colors) }
            }
        }
    }

    private func updateIndex() {
        let items = displayLines
        let t = time(at: Date()) + Self.lineLead
        var low = 0, high = items.count - 1, found = -1
        while low <= high {
            let mid = (low + high) / 2
            if items[mid].start <= t { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        if found != currentIndex { currentIndex = found }
    }
}
