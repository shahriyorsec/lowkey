import AppKit
import IOKit.pwr_mgt

/// Notices when a video is playing anywhere, such as YouTube in a browser, QuickTime or IINA.
/// Video players ask macOS to keep the display awake while they play; music doesn't, so that
/// request is a reliable sign of video without needing any extra permission.
final class VideoWatcher: ObservableObject {
    @Published private(set) var isPlaying = false
    /// The app playing it, for the menu bar menu.
    private(set) var appName = ""

    private var timer: Timer?
    private var lastSeen = Date.distantPast
    private var runStart: Date?
    /// A video has to keep playing this long first. Pages start short muted clips all the time
    /// (feeds, previews, ads), and those mustn't make the card vanish on that page's desktop.
    private let minimumRun: TimeInterval = 12
    /// Tools that keep the screen awake for reasons other than video.
    private let ignored: Set<String> = ["caffeinate", "Amphetamine", "KeepingYouAwake", "Lungo", "Spotify", "Lowkey"]

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.check() }
        timer?.tolerance = 0.3
        check()
    }

    private func check() {
        let now = Date()
        if let name = videoApp() {
            appName = name
            if runStart == nil { runStart = now }
            lastSeen = now
        } else if now.timeIntervalSince(lastSeen) >= 3 {
            runStart = nil
        }
        // Hide once a video has played for a while; come back a moment after it stops,
        // so pausing briefly or skipping an ad doesn't make the card flicker.
        let playing = runStart.map { now.timeIntervalSince($0) >= minimumRun } ?? false
        if playing != isPlaying { isPlaying = playing }
    }

    private func videoApp() -> String? {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return nil }
        for (pid, assertions) in byProcess {
            let keepsDisplayOn = assertions.contains {
                let type = $0[kIOPMAssertionTypeKey] as? String
                return type == kIOPMAssertPreventUserIdleDisplaySleep as String || type == kIOPMAssertionTypeNoDisplaySleep as String
            }
            guard keepsDisplayOn else { continue }
            let app = NSRunningApplication(processIdentifier: pid.int32Value)
            let name = app?.localizedName ?? app?.executableURL?.lastPathComponent ?? ""
            if !name.isEmpty, !ignored.contains(name), app?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                return name
            }
        }
        return nil
    }
}
