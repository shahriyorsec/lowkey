import AppKit
import Combine
import SwiftUI

final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        // Stays on every desktop and above full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var isEditing = false
    var onMoved: (() -> Void)?
    private var dragTimer: Timer?

    /// Dragging lives here, not in SwiftUI, so it works however the card is laid out and
    /// doesn't need the app to be active. Edit mode keeps its two controls clickable.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, startsDrag(event) {
            trackDrag()
            return
        }
        super.sendEvent(event)
    }

    private func startsDrag(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.option) { return true }
        guard isEditing else { return false }
        let point = event.locationInWindow
        let size = frame.size
        let onResizeHandle = point.x > size.width - 44 && point.y < 44
        let onDoneButton = point.x > size.width - 96 && point.y > size.height - 48
        return !onResizeHandle && !onDoneButton
    }

    /// Reads the pointer directly: a non-activating panel isn't sent every drag event,
    /// and this can't get stuck waiting for a mouse-up that never arrives.
    private func trackDrag() {
        dragTimer?.invalidate()
        let startMouse = NSEvent.mouseLocation
        let startOrigin = frame.origin
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            let mouse = NSEvent.mouseLocation
            let wanted = NSPoint(x: startOrigin.x + mouse.x - startMouse.x, y: startOrigin.y + mouse.y - startMouse.y)
            self.setFrameOrigin(self.keptOnScreen(wanted, mouse: mouse))
            if NSEvent.pressedMouseButtons & 1 == 0 {
                timer.invalidate()
                self.dragTimer = nil
                self.onMoved?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragTimer = timer
    }

    /// Free placement, but the whole card stays on the display under the pointer.
    private func keptOnScreen(_ origin: NSPoint, mouse: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? self.screen ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return origin }
        return NSPoint(x: min(max(area.minX, origin.x), area.maxX - frame.width),
                       y: min(max(area.minY, origin.y), area.maxY - frame.height))
    }
}

final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let model = NowPlaying()
    private let panel = OverlayPanel()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var bag = Set<AnyCancellable>()

    private var userHidden = false
    private var isEditing = false
    private var editingBinding: Binding<Bool>!
    private var isVisible = false

    private var pointerTimer: Timer?
    private var resizeStart: (mouse: NSPoint, scale: Double, width: Double)?

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let previousItem = NSMenuItem(title: "Previous", action: #selector(previousTrack), keyEquivalent: "")
    private let playItem = NSMenuItem(title: "Play", action: #selector(playPause), keyEquivalent: "")
    private let nextItem = NSMenuItem(title: "Next", action: #selector(nextTrack), keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "", action: #selector(toggleVisible), keyEquivalent: "")
    private let editItem = NSMenuItem(title: "", action: #selector(toggleEditing), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        editingBinding = Binding(get: { [unowned self] in isEditing }, set: { [unowned self] in setEditing($0) })
        buildStatusItem()
        rebuildContent()
        panel.onMoved = { [weak self] in self?.saveCustomOrigin() }
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.updateMouseHandling() }
        updateFrame()

        settings.$p.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateFrame() }.store(in: &bag)
        model.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.updateVisibility() }.store(in: &bag)
        settings.$p.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateVisibility() }.store(in: &bag)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.updateFrame() }
        model.start()
        updateVisibility()
        if CommandLine.arguments.contains("--edit") { setEditing(true) }
    }

    // MARK: Overlay

    private func rebuildContent() {
        let root = OverlayView(
            settings: settings, model: model, isEditing: editingBinding,
            onResize: { [weak self] in self?.handleResize($0) },
            onDone: { [weak self] in self?.setEditing(false) })
        let host = ClickableHostingView(rootView: root)
        host.sizingOptions = []
        host.wantsLayer = true
        panel.contentView = host
    }

    private func panelSize() -> NSSize {
        CardGeometry(settings.p).size
    }

    private func updateFrame() {
        let size = panelSize()
        panel.hasShadow = settings.p.backgroundStyle != .transparent
        let frame = NSRect(origin: origin(for: size), size: size).integral
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        // The shadow follows the card's outline, which a setting can change without resizing the window.
        DispatchQueue.main.async { [weak self] in self?.panel.invalidateShadow() }
    }

    private func origin(for size: NSSize) -> NSPoint {
        let p = settings.p
        let primary = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin = 32.0
        switch p.anchor {
        case .bottomRight: return NSPoint(x: primary.maxX - size.width - margin, y: primary.minY + margin)
        case .bottomCenter: return NSPoint(x: primary.midX - size.width / 2, y: primary.minY + margin)
        case .bottomLeft: return NSPoint(x: primary.minX + margin, y: primary.minY + margin)
        case .topRight: return NSPoint(x: primary.maxX - size.width - margin, y: primary.maxY - size.height - margin)
        case .topCenter: return NSPoint(x: primary.midX - size.width / 2, y: primary.maxY - size.height - margin)
        case .topLeft: return NSPoint(x: primary.minX + margin, y: primary.maxY - size.height - margin)
        case .custom:
            let wanted = NSRect(x: p.customX, y: p.customY - size.height, width: size.width, height: size.height)
            // A saved spot on an unplugged monitor falls back to the primary display.
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(wanted) }) { return wanted.origin }
            return NSPoint(x: primary.maxX - size.width - margin, y: primary.minY + margin)
        }
    }

    private func updateVisibility() {
        let p = settings.p
        // objectWillChange fires before the value changes, so read on the next pass.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hasTrack = self.model.track != nil
            let playingOK = self.model.isPlaying || !p.hideWhenPaused
            let lyricsOK = !p.hideWhenNoLyrics || self.model.lyricsState == .ready || self.model.lyricsState == .loading
            // Pausing from the card's own button mustn't hide the button needed to resume.
            let holdForPointer = self.isVisible && self.model.isHovering && hasTrack
            self.setVisible(self.isEditing || (!self.userHidden && hasTrack && (playingOK || holdForPointer) && lyricsOK))
        }
    }

    private func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = visible ? 1 : 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isVisible else { return }
            self.panel.orderOut(nil)
        })
    }

    // MARK: Edit mode

    private func setEditing(_ editing: Bool) {
        isEditing = editing
        panel.isEditing = editing
        updateMouseHandling()
        model.isSampleMode = editing
        rebuildContent()
        updateVisibility()
    }

    @objc private func toggleEditing() { setEditing(!isEditing) }

    /// Hit area of the playback controls, in window coordinates (origin at the bottom left).
    private func controlsRect() -> NSRect? {
        let geometry = CardGeometry(settings.p)
        guard let rect = geometry.controlsRect else { return nil }
        return NSRect(x: rect.minX, y: geometry.size.height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The lyric area, while it has lines that can be clicked.
    private func seekRect() -> NSRect? {
        guard settings.p.clickToSeek, !model.lines.isEmpty else { return nil }
        let geometry = CardGeometry(settings.p)
        let rect = geometry.lyricsRect
        return NSRect(x: rect.minX, y: geometry.size.height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The card lets clicks through to the apps below. It only catches them in edit mode,
    /// while Option is held, or with the pointer on the playback controls or the lyrics.
    private func updateMouseHandling() {
        let mouse = NSEvent.mouseLocation
        let hovering = isVisible && panel.frame.contains(mouse)
        if model.isHovering != hovering { model.isHovering = hovering }
        let inWindow = NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        let onControls = hovering && ((controlsRect()?.contains(inWindow) ?? false) || (seekRect()?.contains(inWindow) ?? false))
        let catchesMouse = isEditing || onControls || NSEvent.modifierFlags.contains(.option)
        if panel.ignoresMouseEvents == catchesMouse { panel.ignoresMouseEvents = !catchesMouse }
    }

    private func saveCustomOrigin() {
        settings.p.customX = panel.frame.minX
        settings.p.customY = panel.frame.maxY
        settings.p.anchor = .custom
    }

    private func handleResize(_ mouse: NSPoint?) {
        guard let mouse else {
            resizeStart = nil
            return
        }
        if resizeStart == nil {
            // The top-left corner stays put while the bottom-right corner follows the mouse.
            saveCustomOrigin()
            resizeStart = (mouse, settings.p.scale, panel.frame.width)
        }
        guard let start = resizeStart else { return }
        let width = start.width + mouse.x - start.mouse.x
        settings.p.scale = min(1.8, max(0.7, start.scale * width / start.width))
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "Lowkey")
        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        for item in [previousItem, playItem, nextItem] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let hint = NSMenuItem(title: "Hold ⌥ Option and drag to move", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        for item in [toggleItem, editItem] {
            item.target = self
            menu.addItem(item)
        }
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Lowkey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if model.permissionDenied {
            statusLine.title = "Allow Spotify access in System Settings → Automation"
        } else if let track = model.track {
            statusLine.title = "\(track.title) — \(track.artist)"
        } else {
            statusLine.title = "Nothing playing on Spotify"
        }
        playItem.title = model.isPlaying ? "Pause" : "Play"
        toggleItem.title = userHidden ? "Show Overlay" : "Hide Overlay"
        editItem.title = isEditing ? "Finish Editing" : "Edit Position and Size"
    }

    @objc private func previousTrack() { model.previousTrack() }
    @objc private func playPause() { model.playPause() }
    @objc private func nextTrack() { model.nextTrack() }

    @objc private func toggleVisible() {
        userHidden.toggle()
        updateVisibility()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(settings: settings, onEdit: { [weak self] in self?.setEditing(true) })))
            window.title = "Lowkey Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
