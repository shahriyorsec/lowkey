import AppKit
import IOKit.pwr_mgt

/// Notices when a video is playing anywhere, such as YouTube in a browser, QuickTime or IINA.
/// Video players ask macOS to keep the display awake while they play; music doesn't, so that
/// request is a reliable sign of video without needing any extra permission.
final class VideoWatcher: ObservableObject {
    @Published private(set) var isPlaying = false

    private var timer: Timer?
    private var lastSeen = Date.distantPast
    /// Tools that keep the screen awake for reasons other than video.
    private let ignored: Set<String> = ["caffeinate", "Amphetamine", "KeepingYouAwake", "Lungo", "Spotify", "Lowkey"]

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.check() }
        timer?.tolerance = 0.3
        check()
    }

    private func check() {
        let now = Date()
        if videoAssertionExists() { lastSeen = now }
        // Hide as soon as a video starts; come back a moment after it stops, so pausing briefly
        // or skipping an ad doesn't make the card flicker.
        let playing = now.timeIntervalSince(lastSeen) < 3
        if playing != isPlaying { isPlaying = playing }
    }

    private func videoAssertionExists() -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        for (pid, assertions) in byProcess {
            let keepsDisplayOn = assertions.contains {
                let type = $0[kIOPMAssertionTypeKey] as? String
                return type == kIOPMAssertPreventUserIdleDisplaySleep as String || type == kIOPMAssertionTypeNoDisplaySleep as String
            }
            guard keepsDisplayOn else { continue }
            let app = NSRunningApplication(processIdentifier: pid.int32Value)
            let name = app?.localizedName ?? app?.executableURL?.lastPathComponent ?? ""
            if !name.isEmpty, !ignored.contains(name), app?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                return true
            }
        }
        return false
    }
}
