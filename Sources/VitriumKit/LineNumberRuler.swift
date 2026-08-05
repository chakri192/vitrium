import AppKit

/// The gutter. Draws right-aligned line numbers beside the text view, with the
/// caret's own line brightened.
///
/// Line starts are cached in a sorted array and only rebuilt when the text
/// actually changes — recomputing them per scroll frame is what made the old
/// build's line numbers drift on large files.
final class LineNumberRuler: NSRulerView {

    private var lineIndex = LineIndex()
    private var lineIndexIsStale = true

    private var textView: NSTextView? { clientView as? NSTextView }

    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = Theme.gutterWidth

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(textDidChange),
                           name: NSText.didChangeNotification, object: textView)
        center.addObserver(self, selector: #selector(viewChanged),
                           name: NSView.boundsDidChangeNotification,
                           object: scrollView?.contentView)
        center.addObserver(self, selector: #selector(viewChanged),
                           name: NSView.frameDidChangeNotification, object: textView)
        center.addObserver(self, selector: #selector(viewChanged),
                           name: NSTextView.didChangeSelectionNotification, object: textView)
    }

    required init(coder: NSCoder) { fatalError("not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Invalidation

    @objc private func textDidChange() {
        lineIndexIsStale = true
        needsDisplay = true
    }

    @objc private func viewChanged() {
        needsDisplay = true
    }

    /// Called when the document is replaced wholesale (file load, tab switch).
    func reset() {
        lineIndexIsStale = true
        needsDisplay = true
    }

    var font: NSFont = Theme.editorFont(size: Theme.defaultFontSize) {
        didSet { needsDisplay = true }
    }

    // MARK: Line index

    private func lineIndexIfNeeded(_ text: NSString) -> LineIndex {
        guard lineIndexIsStale else { return lineIndex }
        lineIndex.rebuild(for: text)
        lineIndexIsStale = false
        return lineIndex
    }

    // MARK: Drawing

    // NSRulerView's own draw() paints an opaque ruler background, which would
    // punch a solid strip through the glass. Draw only the labels.
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              let clipView = scrollView?.contentView
        else { return }

        let text = textView.string as NSString
        let index = lineIndexIfNeeded(text)

        let visibleRect = clipView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let caretOffset = textView.selectedRange().location
        let caretLine = index.line(containing: min(caretOffset, text.length))

        let inset = textView.textContainerInset.height
        let numberFont = Theme.editorFont(size: max(9, font.pointSize - 1))

        var line = index.line(containing: charRange.location)
        let lastVisible = NSMaxRange(charRange)

        while line < index.count && index.start(of: line) <= lastVisible {
            let offset = index.start(of: line)
            var fragment: NSRect

            if offset >= text.length {
                // An empty document, or the empty line after a trailing newline.
                // There is no glyph here, and `lineFragmentRect` would hand back
                // a zero-height rect — which centred the label half a line above
                // the caret until the first character was typed.
                fragment = layoutManager.extraLineFragmentRect
            } else {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: offset)
                fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            }

            // Belt and braces: before the first layout pass even the extra line
            // fragment can come back empty.
            if fragment.height <= 0 {
                fragment.size.height = layoutManager.defaultLineHeight(for: textView.font ?? font)
            }

            // A soft-wrapped continuation shares its paragraph's number, so only
            // the fragment holding the paragraph start gets a label.
            fragment.origin.y += inset
            let y = fragment.origin.y - visibleRect.origin.y

            if y + fragment.height >= rect.minY && y <= rect.maxY {
                let isCaretLine = (line == caretLine)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: numberFont,
                    .foregroundColor: isCaretLine ? Theme.gutterCurrent : Theme.gutterText,
                ]
                let label = "\(line + 1)" as NSString
                let size = label.size(withAttributes: attributes)
                let point = NSPoint(
                    x: ruleThickness - size.width - 10,
                    y: y + (fragment.height - size.height) / 2
                )
                label.draw(at: point, withAttributes: attributes)
            }

            line += 1
        }

        // Hairline separating gutter from text.
        Theme.hairline.setFill()
        NSRect(x: ruleThickness - 1, y: rect.minY, width: 1, height: rect.height).fill()
    }
}
