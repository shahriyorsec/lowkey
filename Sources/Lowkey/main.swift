import AppKit

// The build script calls this to make the bundled icon from the same drawing the app uses.
if let flag = CommandLine.arguments.firstIndex(of: "--export-iconset"), flag + 1 < CommandLine.arguments.count {
    let ok = MainActor.assumeIsolated { AppIcon.exportIconSet(to: CommandLine.arguments[flag + 1]) }
    exit(ok ? 0 : 1)
}

// Only one Lowkey at a time. A second launch (Spotlight, Finder, a stray build copy)
// asks the running one to open Settings and quits right away.
let showSettingsNote = Notification.Name("app.lowkey.overlay.showSettings")
let me = ProcessInfo.processInfo.processIdentifier
if NSRunningApplication.runningApplications(withBundleIdentifier: "app.lowkey.overlay")
    .contains(where: { $0.processIdentifier != me && !$0.isTerminated }) {
    DistributedNotificationCenter.default().postNotificationName(
        showSettingsNote, object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
