import AppKit

/// Asks the window server which desktops a window is really on.
/// AppKit's `isOnActiveSpace` answers "yes" for any window marked for every desktop,
/// even after macOS has quietly pinned it to one, so it can't see the problem.
enum Desktops {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias ActiveSpace = @convention(c) (Int32) -> UInt64
    private typealias SpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias DisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias MoveToSpace = @convention(c) (Int32, CFArray, UInt64) -> Void

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        guard let skyLight, let pointer = dlsym(skyLight, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
    private static let connection = symbol("SLSMainConnectionID", as: MainConnection.self)?()
    private static let activeSpaceFn = symbol("SLSGetActiveSpace", as: ActiveSpace.self)
    private static let spacesFn = symbol("SLSCopySpacesForWindows", as: SpacesForWindows.self)
    private static let displaySpacesFn = symbol("SLSCopyManagedDisplaySpaces", as: DisplaySpaces.self)
    private static let moveFn = symbol("SLSMoveWindowsToManagedSpace", as: MoveToSpace.self)

    static var activeSpace: UInt64? {
        guard let connection, let activeSpaceFn else { return nil }
        let space = activeSpaceFn(connection)
        return space == 0 ? nil : space
    }

    /// Desktops the window is on, or nil when the window server can't be asked.
    static func spaces(of window: NSWindow) -> [UInt64]? {
        guard let connection, let spacesFn, window.windowNumber > 0 else { return nil }
        let ids = [NSNumber(value: window.windowNumber)] as CFArray
        guard let result = spacesFn(connection, 7, ids)?.takeRetainedValue() as? [NSNumber] else { return nil }
        return result.map(\.uint64Value)
    }

    /// How many desktops exist across all screens.
    static var desktopCount: Int? {
        guard let connection, let displaySpacesFn,
              let displays = displaySpacesFn(connection)?.takeRetainedValue() as? [[String: Any]] else { return nil }
        return displays.reduce(0) { $0 + (($1["Spaces"] as? [Any])?.count ?? 0) }
    }

    /// True when the window is missing from the desktop showing now.
    static func isStuckElsewhere(_ window: NSWindow) -> Bool {
        guard let active = activeSpace, let spaces = spaces(of: window), !spaces.isEmpty else { return false }
        return !spaces.contains(active)
    }

    /// True when macOS has pinned the window to a single desktop although there are more,
    /// so it would vanish on the next switch. Caught before the user ever sees it.
    static func isPinned(_ window: NSWindow) -> Bool {
        guard let spaces = spaces(of: window), let total = desktopCount, total > 1 else { return false }
        return spaces.count == 1
    }

    static func move(_ window: NSWindow, to space: UInt64) {
        guard let connection, let moveFn, window.windowNumber > 0 else { return }
        moveFn(connection, [NSNumber(value: window.windowNumber)] as CFArray, space)
    }
}
