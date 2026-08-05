import AppKit

/// A scroll view + text view + gutter + highlighter, wired together.
///
/// Each tab owns one of these outright. Keeping a whole view per document is a
/// little more memory than swapping one text view's storage around, but it means
/// scroll position, selection and the undo stack survive a tab switch with no
/// bookkeeping at all — which is exactly where the old build kept going wrong.
final class EditorPane: NSView {

    let textView: EditorTextView
    let scrollView: NSScrollView
    let highlighter: SyntaxHighlighter
    private let ruler: LineNumberRuler
    private let storage = NSTextStorage()

    var language: Language = .plain {
        didSet {
            textView.language = language
            highlighter.language = language
        }
    }

    var fontSize: CGFloat = Theme.defaultFontSize {
        didSet {
            let font = Theme.editorFont(size: fontSize)
            textView.font = font
            highlighter.font = font
            ruler.font = font
            ruler.reset()
        }
    }

    var wrapsLines = true {
        didSet { applyWrapping() }
    }

    override init(frame frameRect: NSRect) {
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        textView = EditorTextView(frame: .zero, textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        highlighter = SyntaxHighlighter(textStorage: storage)
        ruler = LineNumberRuler(textView: textView)

        super.init(frame: frameRect)

        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        applyWrapping()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Content

    /// O(1), unlike counting a `String`'s characters — used on every keystroke.
    var textLength: Int { storage.length }

    var text: String {
        get { storage.string }
        set {
            textView.undoManager?.removeAllActions()
            storage.setAttributedString(NSAttributedString(
                string: newValue,
                attributes: [.font: Theme.editorFont(size: fontSize), .foregroundColor: Theme.foreground]
            ))
            highlighter.rehighlightAll()
            ruler.reset()
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scroll(.zero)
        }
    }

    private func applyWrapping() {
        guard let container = textView.textContainer else { return }
        if wrapsLines {
            container.widthTracksTextView = true
            container.size = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            scrollView.hasHorizontalScroller = false
        } else {
            container.widthTracksTextView = false
            container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            scrollView.hasHorizontalScroller = true
        }
        textView.needsLayout = true
        textView.needsDisplay = true
        ruler.reset()
    }

    override func layout() {
        super.layout()
        if wrapsLines, let container = textView.textContainer {
            container.size = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    func focus() {
        window?.makeFirstResponder(textView)
    }
}
