import AppKit

// The build script calls this to make the bundled icon from the same drawing the app uses.
if let flag = CommandLine.arguments.firstIndex(of: "--export-iconset"), flag + 1 < CommandLine.arguments.count {
    let ok = MainActor.assumeIsolated { AppIcon.exportIconSet(to: CommandLine.arguments[flag + 1]) }
    exit(ok ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
