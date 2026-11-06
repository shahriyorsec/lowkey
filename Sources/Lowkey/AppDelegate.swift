import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Which sides of the card a resize drag moves.
struct ResizeEdges: OptionSet {
    let rawValue: Int
    static let left = ResizeEdges(rawValue: 1)
    static let right = ResizeEdges(rawValue: 2)
    static let top = ResizeEdges(rawValue: 4)
    static let bottom = ResizeEdges(rawValue: 8)

    /// The zone under a point in window coordinates. Corners get a bigger target than edges.
    static func zone(at point: NSPoint, in size: NSSize) -> ResizeEdges {
        guard point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else { return [] }
        let edge = 7.0, corner = 16.0
        let nearX: ResizeEdges = point.x < corner ? .left : point.x > size.width - corner ? .right : []
        let nearY: ResizeEdges = point.y < corner ? .bottom : point.y > size.height - corner ? .top : []
        if !nearX.isEmpty && !nearY.isEmpty { return nearX.union(nearY) }
        var result: ResizeEdges = []
        if point.x < edge { result.insert(.left) }
        if point.x > size.width - edge { result.insert(.right) }
        if point.y < edge { result.insert(.bottom) }
        if point.y > size.height - edge { result.insert(.top) }
        return result
    }

    var cursor: NSCursor? {
        let position: NSCursor.FrameResizePosition
        switch self {
        case [.left]: position = .left
        case [.right]: position = .right
        case [.top]: position = .top
        case [.bottom]: position = .bottom
        case [.top, .left]: position = .topLeft
        case [.top, .right]: position = .topRight
        case [.bottom, .left]: position = .bottomLeft
        case [.bottom, .right]: position = .bottomRight
        default: return nil
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }
}

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
    /// Only full screen takes the keyboard, so Esc can close it.
    var acceptsKeyboard = false
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { acceptsKeyboard }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override var canBecomeMain: Bool { false }

    var isEditing = false
    var onMoved: (() -> Void)?
    var resizeEnabled = false
    var onResizeBegan: ((ResizeEdges) -> Void)?
    var onResizing: ((NSPoint) -> Void)?
    var onResizeEnded: (() -> Void)?
    private var dragTimer: Timer?

    /// Dragging lives here, not in SwiftUI, so it works however the card is laid out and
    /// doesn't need the app to be active. Edit mode keeps its two controls clickable.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let onDoneButton = isEditing && event.locationInWindow.x > frame.width - 96 && event.locationInWindow.y > frame.height - 48
            let zone = resizeEnabled && !onDoneButton ? ResizeEdges.zone(at: event.locationInWindow, in: frame.size) : []
            if !zone.isEmpty {
                trackResize(zone)
                return
            }
            if startsDrag(event) {
                trackDrag()
                return
            }
        }
        super.sendEvent(event)
    }

    private func startsDrag(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.option) { return true }
        guard isEditing else { return false }
        let point = event.locationInWindow
        return !(point.x > frame.width - 96 && point.y > frame.height - 48)
    }

    private func trackResize(_ edges: ResizeEdges) {
        dragTimer?.invalidate()
        onResizeBegan?(edges)
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            self.onResizing?(NSEvent.mouseLocation)
            if NSEvent.pressedMouseButtons & 1 == 0 {
                timer.invalidate()
                self.dragTimer = nil
                self.onResizeEnded?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragTimer = timer
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
    private let settingsNavigation = SettingsNavigation()
    private var bag = Set<AnyCancellable>()

    private var userHidden = false
    private var isEditing = false
    private var editingBinding: Binding<Bool>!
    private var isVisible = false

    private var pointerTimer: Timer?
    private var settingsHotKey: EventHotKeyRef?
    private var resizeStart: (edges: ResizeEdges, mouse: NSPoint, frame: NSRect, scale: Double)?
    private var shownCursorZone: ResizeEdges = []
    private var fullScreenSize: CGSize?
    private let fullScreenItem = NSMenuItem(title: "", action: #selector(toggleFullScreen), keyEquivalent: "")

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
        panel.onEscape = { [weak self] in self?.setFullScreen(false) }
        panel.onResizeBegan = { [weak self] in self?.beginResize($0) }
        panel.onResizing = { [weak self] in self?.handleResize($0) }
        panel.onResizeEnded = { [weak self] in self?.resizeStart = nil }
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateMouseHandling() }
        updateFrame()

        settings.$p.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateFrame() }.store(in: &bag)
        model.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.updateVisibility() }.store(in: &bag)
        settings.$p.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateVisibility() }.store(in: &bag)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.updateFrame() }
        model.start()
        registerSettingsShortcut()
        updateVisibility()
        AppIcon.apply(settings.p.appIcon)
        LoginItem.apply(settings.p.openAtLogin)
        settings.$p.map(\.openAtLogin).removeDuplicates().dropFirst().receive(on: RunLoop.main)
            .sink { LoginItem.apply($0) }.store(in: &bag)
        settings.$p.map(\.appIcon).removeDuplicates().dropFirst().receive(on: RunLoop.main)
            .sink { AppIcon.apply($0) }.store(in: &bag)
        if CommandLine.arguments.contains("--edit") { setEditing(true) }
    }

    // MARK: Overlay

    private func rebuildContent() {
        let root = OverlayView(
            settings: settings, model: model, isEditing: editingBinding, fullScreenSize: fullScreenSize,
            onDone: { [weak self] in self?.setEditing(false) },
            onExitFullScreen: { [weak self] in self?.setFullScreen(false) })
        let host = ClickableHostingView(rootView: root)
        host.sizingOptions = []
        host.wantsLayer = true
        panel.contentView = host
    }

    private func currentGeometry() -> CardGeometry {
        CardGeometry(settings.p, fullScreen: fullScreenSize)
    }

    private func panelSize() -> NSSize {
        currentGeometry().size
    }

    private func updateFrame() {
        if fullScreenSize != nil, let screen = panel.screen ?? NSScreen.screens.first {
            if panel.frame != screen.frame { panel.setFrame(screen.frame, display: true) }
            panel.hasShadow = false
            return
        }
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
            self.setVisible(self.fullScreenSize != nil || self.isEditing || (!self.userHidden && hasTrack && (playingOK || holdForPointer) && lyricsOK))
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

    @objc private func toggleFullScreen() { setFullScreen(fullScreenSize == nil) }

    private func setFullScreen(_ on: Bool) {
        if on && isEditing { setEditing(false) }
        if on {
            guard let screen = panel.screen ?? NSScreen.screens.first else { return }
            fullScreenSize = screen.frame.size
        } else {
            fullScreenSize = nil
        }
        panel.acceptsKeyboard = on
        rebuildContent()
        updateFrame()
        updateMouseHandling()
        updateVisibility()
        if on {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.resignKey()
        }
    }

    /// Hit area of the playback controls, in window coordinates (origin at the bottom left).
    private func controlsRect() -> NSRect? {
        let geometry = currentGeometry()
        guard let rect = geometry.controlsRect else { return nil }
        return NSRect(x: rect.minX, y: geometry.size.height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The lyric area, while it has lines that can be clicked.
    private func seekRect() -> NSRect? {
        guard settings.p.clickToSeek, !model.lines.isEmpty else { return nil }
        let geometry = currentGeometry()
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
        let resizeAllowed = fullScreenSize == nil && (settings.p.resizeFromEdges || isEditing)
        let zone = hovering && resizeAllowed ? ResizeEdges.zone(at: inWindow, in: panel.frame.size) : []
        panel.resizeEnabled = resizeAllowed
        if resizeStart == nil && zone != shownCursorZone {
            shownCursorZone = zone
            (zone.cursor ?? .arrow).set()
        }
        let catchesMouse = fullScreenSize != nil || isEditing || onControls || !zone.isEmpty || NSEvent.modifierFlags.contains(.option)
        if panel.ignoresMouseEvents == catchesMouse { panel.ignoresMouseEvents = !catchesMouse }
    }

    private func saveCustomOrigin() {
        settings.p.customX = panel.frame.minX
        settings.p.customY = panel.frame.maxY
        settings.p.anchor = .custom
    }

    private func beginResize(_ edges: ResizeEdges) {
        resizeStart = (edges, NSEvent.mouseLocation, panel.frame, settings.p.scale)
    }

    /// Moves the dragged sides, keeps the opposite ones still, and grows the content along with the card.
    private func handleResize(_ mouse: NSPoint) {
        guard let start = resizeStart else { return }
        let dx = mouse.x - start.mouse.x, dy = mouse.y - start.mouse.y
        let area = (panel.screen ?? NSScreen.screens.first)?.visibleFrame.size ?? NSSize(width: 4000, height: 4000)
        var width = start.frame.width + (start.edges.contains(.right) ? dx : start.edges.contains(.left) ? -dx : 0)
        var height = start.frame.height + (start.edges.contains(.bottom) ? -dy : start.edges.contains(.top) ? dy : 0)

        let growth = ((width / start.frame.width) * (height / start.frame.height)).squareRoot()
        let scale = min(3, max(0.7, start.scale * max(0.01, growth)))
        width = min(area.width, max(CardGeometry.minWidth * scale, width))
        height = min(area.height, max(CardGeometry.minHeight * scale, height))

        var p = settings.p
        p.scale = scale
        p.cardWidth = width
        p.cardHeight = height
        p.anchor = .custom
        p.customX = start.edges.contains(.left) ? start.frame.maxX - width : start.frame.minX
        p.customY = start.edges.contains(.top) ? start.frame.minY + height : start.frame.maxY
        settings.p = p
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = AppIcon.menuBarGlyph
        statusItem.button?.image?.accessibilityDescription = "Lowkey"
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
        for item in [toggleItem, fullScreenItem, editItem] {
            item.target = self
            menu.addItem(item)
        }
        let settingsItem = NSMenuItem(title: "Settings…   ⌃⌥⌘L", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Lowkey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    /// Opening Lowkey again (from Finder, Launchpad or Spotlight) while it runs shows Settings,
    /// since the menu bar icon can be hidden behind the notch on a full menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    /// Control-Option-Command-L opens Settings from any app. A Carbon hot key needs no extra permission.
    private func registerSettingsShortcut() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { delegate.openSettings() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let id = EventHotKeyID(signature: OSType(0x4C4B5931), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey | cmdKey), id,
                            GetApplicationEventTarget(), 0, &settingsHotKey)
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
        fullScreenItem.title = fullScreenSize == nil ? "Full Screen Lyrics" : "Exit Full Screen"
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

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(settings: settings, navigation: settingsNavigation,
                                       onEdit: { [weak self] in self?.setEditing(true) },
                                       onFullScreen: { [weak self] in self?.setFullScreen(true) })))
            window.title = "Lowkey Settings"
            // A unified toolbar lets the sidebar run to the top of the window, as in System Settings.
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbar = NSToolbar(identifier: "settings")
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = true
            window.setContentSize(NSSize(width: 760, height: 580))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
