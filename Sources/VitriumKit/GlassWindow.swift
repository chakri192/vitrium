import AppKit

/// The transparent window itself.
///
/// The blur is a real `NSVisualEffectView` in `.behindWindow` blending mode —
/// the compositor samples what is actually behind the window. There is no
/// screenshot trick and no CSS-style approximation involved.
final class GlassWindow: NSWindow {

    let visualEffectView = NSVisualEffectView()
    private let tintView = NSView()

    /// 0 = pure blur, 1 = effectively solid.
    var tint: CGFloat = Theme.defaultTint {
        didSet {
            tint = min(Theme.maxTint, max(Theme.minTint, tint))
            tintView.layer?.backgroundColor = NSColor(white: 0.04, alpha: tint).cgColor
        }
    }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
        minSize = NSSize(width: 480, height: 320)
        tabbingMode = .disallowed

        let content = NSView(frame: contentRect)
        content.wantsLayer = true
        contentView = content

        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(visualEffectView)

        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor(white: 0.04, alpha: Theme.defaultTint).cgColor
        tintView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tintView)

        for view in [visualEffectView, tintView] {
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                view.topAnchor.constraint(equalTo: content.topAnchor),
                view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// The glass material tracks the active material by default, which dims the
    /// whole window when it loses focus. Keeping it `.active` means the editor
    /// looks the same whether or not it is frontmost.
    override func resignKey() {
        super.resignKey()
        visualEffectView.state = .active
    }
}
