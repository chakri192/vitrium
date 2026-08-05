import AppKit

/// The text surface. An `NSTextView` subclass carrying the editor behaviours:
/// auto-indent, bracket/quote auto-close, line manipulation, current-line
/// highlight and bracket-match highlight.
final class EditorTextView: NSTextView {

    var language: Language = .plain
    var indentWidth = 4

    private var indentString: String { String(repeating: " ", count: indentWidth) }

    private static let pairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`",
    ]
    private static let closers = Set<Character>([")", "]", "}", "\"", "'", "`"])

    // MARK: Undo

    /// Each tab gets its own undo stack.
    ///
    /// `NSTextView` otherwise falls back to the *window's* undo manager, which
    /// every tab in the window would share — so undoing in one tab could walk
    /// back an edit made in another.
    private let ownUndoManager = UndoManager()

    override var undoManager: UndoManager? { ownUndoManager }

    // The Edit menu's Undo/Redo reach the first responder, which is this view.
    // Handling them here keeps them bound to the per-tab manager above.
    @objc func undo(_ sender: Any?) { ownUndoManager.undo() }
    @objc func redo(_ sender: Any?) { ownUndoManager.redo() }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)): return ownUndoManager.canUndo
        case #selector(redo(_:)): return ownUndoManager.canRedo
        default: return super.validateMenuItem(menuItem)
        }
    }

    // MARK: Setup

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func configure() {
        drawsBackground = false
        backgroundColor = .clear
        isRichText = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        usesFindPanel = false
        textContainerInset = Theme.textInset
        insertionPointColor = Theme.cursor
        selectedTextAttributes = [.backgroundColor: Theme.selection]
        font = Theme.editorFont(size: Theme.defaultFontSize)
        textColor = Theme.foreground
        registerForDraggedTypes(registeredDraggedTypes + [.fileURL])

        NotificationCenter.default.addObserver(
            self, selector: #selector(selectionChanged),
            name: NSTextView.didChangeSelectionNotification, object: self)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Drag and drop

    /// Called with dropped files so the controller can open them as tabs.
    var onOpenFiles: (([URL]) -> Void)?

    /// Files dropped on the editor body have to be intercepted here.
    ///
    /// Registering the window for `.fileURL` isn't enough: `NSTextView` is a
    /// drag destination in its own right and sits deeper in the hierarchy, so it
    /// wins and inserts the path as text instead. Anything that isn't a file
    /// drag — dragging a selection around, for one — falls through to `super`.
    private func droppedFiles(_ sender: NSDraggingInfo) -> [URL] {
        let pasteboard = sender.draggingPasteboard
        guard pasteboard.availableType(from: [.fileURL]) != nil else { return [] }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFiles(sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFiles(sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        droppedFiles(sender).isEmpty ? super.prepareForDragOperation(sender) : true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = droppedFiles(sender)
        guard !files.isEmpty else { return super.performDragOperation(sender) }
        onOpenFiles?(files)
        return true
    }

    // MARK: Text helpers

    private var nsText: NSString { string as NSString }

    /// Undo-registering, delegate-notifying replacement. Every mutation below
    /// goes through here so `⌘Z` sees one coherent stream of edits.
    @discardableResult
    private func replace(_ range: NSRange, with replacement: String,
                         selecting newSelection: NSRange? = nil) -> Bool {
        guard shouldChangeText(in: range, replacementString: replacement) else { return false }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        if let newSelection { setSelectedRange(newSelection) }
        return true
    }

    /// The full-line range covering the current selection, including the
    /// trailing newline of the last line unless it is the final line.
    private func selectedLineRange() -> NSRange {
        nsText.lineRange(for: selectedRange())
    }

    private func character(at index: Int) -> Character? {
        guard index >= 0, index < nsText.length else { return nil }
        return Character(nsText.substring(with: NSRange(location: index, length: 1)))
    }

    // MARK: Auto-close

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let typed = insertString as? String, typed.count == 1,
              let char = typed.first else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let selection = selectedRange()

        // Wrap a selection in the pair rather than replacing it.
        if let closer = Self.pairs[char], selection.length > 0 {
            let selected = nsText.substring(with: selection)
            let wrapped = "\(char)\(selected)\(closer)"
            replace(selection, with: wrapped,
                    selecting: NSRange(location: selection.location + 1, length: selection.length))
            return
        }

        // Typing the closer that auto-close already put there — step over it.
        if Self.closers.contains(char), character(at: selection.location) == char {
            setSelectedRange(NSRange(location: selection.location + 1, length: 0))
            return
        }

        if let closer = Self.pairs[char], shouldAutoClose(char, at: selection.location) {
            replace(selection, with: "\(char)\(closer)",
                    selecting: NSRange(location: selection.location + 1, length: 0))
            return
        }

        super.insertText(insertString, replacementRange: replacementRange)
    }

    /// Auto-closing mid-word is more annoying than helpful — `don't` should not
    /// become `don''t`, and `foo(` before an identifier should not gain a `)`.
    private func shouldAutoClose(_ char: Character, at location: Int) -> Bool {
        let next = character(at: location)
        if let next, !next.isWhitespace, !Self.closers.contains(next) { return false }

        if char == "\"" || char == "'" || char == "`" {
            if let previous = character(at: location - 1),
               previous.isLetter || previous.isNumber || previous == char {
                return false
            }
        }
        return true
    }

    /// Escape closes the find bar from the editor as well as from the find
    /// field. The default here would be word completion, which this editor
    /// doesn't offer.
    override func cancelOperation(_ sender: Any?) {
        NSApp.sendAction(#selector(MainWindowController.dismissFindBar(_:)), to: nil, from: self)
    }

    override func complete(_ sender: Any?) {
        cancelOperation(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0, selection.location > 0,
           let previous = character(at: selection.location - 1),
           let closer = Self.pairs[previous],
           character(at: selection.location) == closer {
            replace(NSRange(location: selection.location - 1, length: 2), with: "",
                    selecting: NSRange(location: selection.location - 1, length: 0))
            return
        }
        super.deleteBackward(sender)
    }

    // MARK: Auto-indent

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        let line = nsText.lineRange(for: NSRange(location: selection.location, length: 0))
        let lineText = nsText.substring(with: line)
        let leading = String(lineText.prefix(while: { $0 == " " || $0 == "\t" }))

        var indent = leading
        // Opening a block indents one level further.
        if let previous = character(at: selection.location - 1),
           previous == "{" || previous == "[" || previous == "(" || previous == ":" {
            indent += indentString
        }

        // Landing between a freshly auto-closed pair puts the closer on its own
        // line at the original indent, caret on the blank line between.
        if let previous = character(at: selection.location - 1),
           let closer = Self.pairs[previous],
           character(at: selection.location) == closer,
           previous != "\"" , previous != "'", previous != "`" {
            let body = "\n\(indent)\n\(leading)"
            replace(selection, with: body,
                    selecting: NSRange(location: selection.location + 1 + indent.count, length: 0))
            return
        }

        replace(selection, with: "\n\(indent)",
                selecting: NSRange(location: selection.location + 1 + indent.count, length: 0))
    }

    // MARK: Indent / outdent

    override func insertTab(_ sender: Any?) {
        if selectedRange().length > 0 {
            indentSelection()
        } else {
            replace(selectedRange(), with: indentString,
                    selecting: NSRange(location: selectedRange().location + indentWidth, length: 0))
        }
    }

    override func insertBacktab(_ sender: Any?) {
        outdentSelection()
    }

    func indentSelection() {
        transformSelectedLines { lines in
            lines.map { self.indentString + $0 }
        }
    }

    func outdentSelection() {
        transformSelectedLines { lines in
            lines.map { line in
                if line.hasPrefix(self.indentString) { return String(line.dropFirst(self.indentWidth)) }
                if line.hasPrefix("\t") { return String(line.dropFirst()) }
                // Fewer leading spaces than a full indent — drop what's there.
                let leading = line.prefix(while: { $0 == " " })
                return String(line.dropFirst(leading.count))
            }
        }
    }

    // MARK: Comment toggle

    func toggleComment() {
        guard let prefix = language.lineCommentPrefix else { NSSound.beep(); return }

        transformSelectedLines { lines in
            // If every non-blank line is already commented, uncomment; otherwise
            // comment the lot. Matches the "all or nothing" behaviour of Xcode.
            let meaningful = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let allCommented = !meaningful.isEmpty && meaningful.allSatisfy {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
            }

            if allCommented {
                return lines.map { line in
                    guard let range = line.range(of: prefix) else { return line }
                    var stripped = line
                    stripped.removeSubrange(range)
                    // Also eat the single space conventionally inserted after it.
                    if stripped[range.lowerBound...].hasPrefix(" ") {
                        stripped.remove(at: range.lowerBound)
                    }
                    return stripped
                }
            }

            // Comment at the shallowest shared indent so the block stays aligned.
            let indent = meaningful
                .map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }
                .min() ?? 0
            return lines.map { line in
                if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
                let index = line.index(line.startIndex, offsetBy: min(indent, line.count))
                return String(line[..<index]) + prefix + " " + String(line[index...])
            }
        }
    }

    // MARK: Line operations

    func duplicateLine() {
        let range = selectedLineRange()
        var text = nsText.substring(with: range)
        let selection = selectedRange()
        if !text.hasSuffix("\n") { text = "\n" + text }

        guard shouldChangeText(in: NSRange(location: NSMaxRange(range), length: 0),
                               replacementString: text) else { return }
        textStorage?.replaceCharacters(in: NSRange(location: NSMaxRange(range), length: 0), with: text)
        didChangeText()
        setSelectedRange(NSRange(location: selection.location + text.count, length: selection.length))
    }

    func moveLine(up: Bool) {
        let range = selectedLineRange()
        let text = nsText

        if up {
            guard range.location > 0 else { return }
            let previous = text.lineRange(for: NSRange(location: range.location - 1, length: 0))
            swapLineRanges(previous, range, movingSelectionBy: -previous.length)
        } else {
            guard NSMaxRange(range) < text.length else { return }
            let next = text.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
            swapLineRanges(range, next, movingSelectionBy: next.length)
        }
    }

    /// `first` and `second` must be adjacent full-line ranges, in order.
    private func swapLineRanges(_ first: NSRange, _ second: NSRange, movingSelectionBy delta: Int) {
        let text = nsText
        var firstText = text.substring(with: first)
        var secondText = text.substring(with: second)
        let combined = NSRange(location: first.location, length: first.length + second.length)
        let selection = selectedRange()

        // The final line of a document has no trailing newline; moving it up
        // would otherwise glue two lines together.
        if !secondText.hasSuffix("\n") && firstText.hasSuffix("\n") {
            firstText.removeLast()
            secondText += "\n"
        }

        let replacement = secondText + firstText
        guard shouldChangeText(in: combined, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: combined, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(location: max(0, selection.location + delta), length: selection.length))
    }

    /// Applies `transform` to the selected lines and reselects the result, so a
    /// repeated indent/comment keeps operating on the same block.
    private func transformSelectedLines(_ transform: ([String]) -> [String]) {
        let range = selectedLineRange()
        guard range.length > 0 else { return }

        let original = nsText.substring(with: range)
        let hadTrailingNewline = original.hasSuffix("\n")
        var lines = original.components(separatedBy: "\n")
        if hadTrailingNewline { lines.removeLast() }

        var result = transform(lines).joined(separator: "\n")
        if hadTrailingNewline { result += "\n" }
        guard result != original else { return }

        guard shouldChangeText(in: range, replacementString: result) else { return }
        textStorage?.replaceCharacters(in: range, with: result)
        didChangeText()
        setSelectedRange(NSRange(location: range.location, length: (result as NSString).length))
    }

    func goToLine(_ number: Int) {
        let text = nsText
        var index = 0
        var line = 1
        while line < number && index < text.length {
            index = NSMaxRange(text.lineRange(for: NSRange(location: index, length: 0)))
            line += 1
        }
        let target = text.lineRange(for: NSRange(location: min(index, text.length), length: 0))
        setSelectedRange(NSRange(location: target.location, length: 0))
        scrollRangeToVisible(target)
    }

    /// 1-based caret position, for the status bar.
    var caretPosition: (line: Int, column: Int) {
        let text = nsText
        let offset = min(selectedRange().location, text.length)
        let line = text.lineRange(for: NSRange(location: offset, length: 0))
        var number = 1
        var index = 0
        while index < line.location {
            index = NSMaxRange(text.lineRange(for: NSRange(location: index, length: 0)))
            number += 1
        }
        return (number, offset - line.location + 1)
    }

    // MARK: Current line + bracket match

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard selectedRange().length == 0,
              let layoutManager, let container = textContainer else { return }

        let range = nsText.lineRange(for: NSRange(location: min(selectedRange().location, nsText.length), length: 0))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var bounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        bounds.origin.x = 0
        bounds.size.width = self.bounds.width
        bounds.origin.y += textContainerInset.height

        Theme.currentLine.setFill()
        bounds.intersection(rect).fill()
    }

    @objc private func selectionChanged() {
        highlightMatchingBracket()
    }

    /// Ranges this view tinted for bracket matching.
    ///
    /// Tracked precisely so clearing them doesn't wipe the find bar's match
    /// highlights — both use the layout manager's temporary background colour,
    /// and clearing the whole document would erase the other's work on every
    /// caret move.
    private var bracketRanges: [NSRange] = []

    private func highlightMatchingBracket() {
        guard let layoutManager else { return }
        for range in bracketRanges where NSMaxRange(range) <= nsText.length {
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
        }
        bracketRanges = []

        let selection = selectedRange()
        guard selection.length == 0 else { return }

        // Look at the character just typed (behind the caret) first, then ahead.
        for (index, forward) in [(selection.location - 1, true), (selection.location, false)] {
            guard let char = character(at: index) else { continue }
            let isOpener = Self.pairs[char] != nil && !Self.closers.contains(char)
            let isCloser = Self.closers.contains(char) && char != "\"" && char != "'" && char != "`"
            guard isOpener || isCloser else { continue }
            guard isOpener == forward else { continue }

            if let match = findMatchingBracket(from: index, char: char, searchingForward: isOpener) {
                for position in [index, match] {
                    let range = NSRange(location: position, length: 1)
                    layoutManager.addTemporaryAttributes(
                        [.backgroundColor: Theme.bracketMatch], forCharacterRange: range)
                    bracketRanges.append(range)
                }
            }
            return
        }
    }

    private func findMatchingBracket(from index: Int, char: Character, searchingForward: Bool) -> Int? {
        let openers: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
        let closers: [Character: Character] = [")": "(", "]": "[", "}": "{"]

        let partner: Character
        if searchingForward {
            guard let match = openers[char] else { return nil }
            partner = match
        } else {
            guard let match = closers[char] else { return nil }
            partner = match
        }

        var depth = 0
        var position = index
        let limit = nsText.length
        // Bail on pathological inputs rather than scanning a huge file per keystroke.
        var budget = 200_000

        while position >= 0 && position < limit && budget > 0 {
            budget -= 1
            if let current = character(at: position) {
                if current == char { depth += 1 }
                else if current == partner {
                    depth -= 1
                    if depth == 0 { return position }
                }
            }
            position += searchingForward ? 1 : -1
        }
        return nil
    }
}
