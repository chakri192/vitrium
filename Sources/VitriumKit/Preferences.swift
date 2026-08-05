import AppKit

/// Everything Vitrium remembers between launches.
enum Preferences {

    private static let defaults = UserDefaults.standard

    private enum Key {
        static let openFiles = "session.openFiles"
        static let selectedTab = "session.selectedTab"
        static let windowFrame = "session.windowFrame"
        static let fontSize = "editor.fontSize"
        static let wrapsLines = "editor.wrapsLines"
        static let tint = "glass.tint"
        static let recentFiles = "recentFiles"
    }

    // MARK: Session

    static var openFiles: [String] {
        get { defaults.stringArray(forKey: Key.openFiles) ?? [] }
        set { defaults.set(newValue, forKey: Key.openFiles) }
    }

    static var selectedTab: Int {
        get { defaults.integer(forKey: Key.selectedTab) }
        set { defaults.set(newValue, forKey: Key.selectedTab) }
    }

    static var windowFrame: NSRect? {
        get {
            guard let string = defaults.string(forKey: Key.windowFrame) else { return nil }
            let rect = NSRectFromString(string)
            return rect.width > 100 && rect.height > 100 ? rect : nil
        }
        set {
            guard let newValue else { return }
            defaults.set(NSStringFromRect(newValue), forKey: Key.windowFrame)
        }
    }

    // MARK: Editor

    static var fontSize: CGFloat {
        get {
            let stored = defaults.double(forKey: Key.fontSize)
            guard stored >= Double(Theme.minFontSize), stored <= Double(Theme.maxFontSize) else {
                return Theme.defaultFontSize
            }
            return CGFloat(stored)
        }
        set { defaults.set(Double(newValue), forKey: Key.fontSize) }
    }

    static var wrapsLines: Bool {
        get { defaults.object(forKey: Key.wrapsLines) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.wrapsLines) }
    }

    static var tint: CGFloat {
        get {
            guard let stored = defaults.object(forKey: Key.tint) as? Double else {
                return Theme.defaultTint
            }
            return min(Theme.maxTint, max(Theme.minTint, CGFloat(stored)))
        }
        set { defaults.set(Double(newValue), forKey: Key.tint) }
    }

    // MARK: Recent files

    static var recentFiles: [URL] {
        (defaults.stringArray(forKey: Key.recentFiles) ?? []).map { URL(fileURLWithPath: $0) }
    }

    static func noteRecentFile(_ url: URL) {
        var paths = defaults.stringArray(forKey: Key.recentFiles) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        defaults.set(Array(paths.prefix(Theme.maxRecentFiles)), forKey: Key.recentFiles)
    }

    static func clearRecentFiles() {
        defaults.removeObject(forKey: Key.recentFiles)
    }
}
