import AppKit

/// The library's only public surface.
///
/// Everything else stays internal — the executable needs exactly one entry
/// point, and the test runner reaches the rest through `@testable import`.
public enum VitriumApp {

    public static func run() -> Never {
        let application = NSApplication.shared
        // The delegate is held by this frame, which `run()` never leaves.
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        exit(0)
    }
}
