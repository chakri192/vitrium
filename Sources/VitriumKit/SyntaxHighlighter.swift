import AppKit

/// Applies syntax colouring to an `NSTextStorage` as it is edited.
///
/// All of a language's rules are compiled into a **single alternation regex**,
/// one named group per rule, in precedence order. ICU tries alternatives
/// left-to-right at each position, so the first rule that matches claims those
/// characters outright — which is what makes `for` inside a docstring stay a
/// string, and a `"` inside a comment stay a comment.
///
/// Only the edited lines are recoloured, so typing costs O(line) rather than
/// O(document).
final class SyntaxHighlighter: NSObject, NSTextStorageDelegate {

    var language: Language = .plain {
        didSet {
            guard language != oldValue else { return }
            rebuildRegex()
            rehighlightAll()
        }
    }

    var font: NSFont = Theme.editorFont(size: Theme.defaultFontSize) {
        didSet { rehighlightAll() }
    }

    private weak var textStorage: NSTextStorage?
    private var regex: NSRegularExpression?
    private var kinds: [TokenKind] = []
    private var groupNames: [String] = []

    init(textStorage: NSTextStorage) {
        self.textStorage = textStorage
        super.init()
        textStorage.delegate = self
        rebuildRegex()
    }

    // MARK: Rule compilation

    private func rebuildRegex() {
        let rules = language.rules
        kinds = rules.map(\.kind)
        groupNames = rules.indices.map { "v\($0)" }

        guard !rules.isEmpty else { regex = nil; return }
        let combined = zip(groupNames, rules)
            .map { "(?<\($0)>\($1.pattern))" }
            .joined(separator: "|")
        regex = try? NSRegularExpression(pattern: combined)
    }

    // MARK: Entry points

    func rehighlightAll() {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        highlight(range: NSRange(location: 0, length: storage.length), in: storage)
        storage.endEditing()
    }

    func textStorage(_ storage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        // Attribute-only changes are safe here; they don't re-enter this callback
        // the way a character edit would.
        highlight(range: recolourRange(for: editedRange, in: storage), in: storage)
    }

    // MARK: Range selection

    /// The span that has to be recoloured after an edit at `editedRange`.
    private func recolourRange(for editedRange: NSRange, in storage: NSTextStorage) -> NSRange {
        let text = storage.string as NSString
        let start = min(editedRange.location, text.length)
        let clamped = NSRange(location: start, length: min(editedRange.length, text.length - start))
        var range = text.lineRange(for: clamped)

        // Typing or deleting a block-comment delimiter can flip the colouring of
        // everything below it, so widen to the end of the document.
        if let block = language.blockComment {
            let touched = text.substring(with: range)
            if touched.contains(block.open) || touched.contains(block.close) {
                range = NSRange(location: range.location, length: text.length - range.location)
            }
        }
        return range
    }

    /// Where the scan has to *start* so that `range` is coloured correctly.
    ///
    /// A block comment covering `range` may have opened far above it, so for
    /// those languages the scan restarts at the last `*/` before the range —
    /// the nearest point that is definitely outside a comment. Everything else
    /// is line-bounded (no rule spans a newline), so the range start will do.
    private func scanStart(for range: NSRange, in text: NSString) -> Int {
        guard let block = language.blockComment, range.location > 0 else { return range.location }
        let searched = NSRange(location: 0, length: range.location)
        let found = text.range(of: block.close, options: .backwards, range: searched)
        return found.location == NSNotFound ? 0 : NSMaxRange(found)
    }

    // MARK: Highlighting

    private func highlight(range: NSRange, in storage: NSTextStorage) {
        let text = storage.string as NSString
        guard range.location >= 0, NSMaxRange(range) <= text.length else { return }

        storage.setAttributes([
            .font: font,
            .foregroundColor: Theme.foreground,
        ], range: range)

        guard let regex, range.length > 0 else { return }

        let start = scanStart(for: range, in: text)
        let limit = NSMaxRange(range)
        let scanRange = NSRange(location: start, length: limit - start)

        regex.enumerateMatches(in: storage.string, options: [], range: scanRange) { match, _, stop in
            guard let match else { return }
            if match.range.location >= limit {
                stop.pointee = true
                return
            }
            // Matches before `range` are only scanned to establish comment
            // state; only the part that overlaps the target gets painted.
            let overlap = NSIntersectionRange(match.range, range)
            guard overlap.length > 0, let kind = self.kind(of: match) else { return }
            self.apply(kind: kind, to: overlap, in: storage)
        }
    }

    /// Which rule claimed this match — the one named group that participated.
    private func kind(of match: NSTextCheckingResult) -> TokenKind? {
        for (index, name) in groupNames.enumerated()
        where match.range(withName: name).location != NSNotFound {
            return kinds[index]
        }
        return nil
    }

    private func apply(kind: TokenKind, to range: NSRange, in storage: NSTextStorage) {
        var traits: NSFontTraitMask = []
        if kind.isBold { traits.insert(.boldFontMask) }
        if kind.isItalic { traits.insert(.italicFontMask) }

        // The font is always set, never left to whatever was there before —
        // otherwise a keyword's bold face survives being recoloured as a string.
        let resolved = traits.isEmpty
            ? font
            : NSFontManager.shared.convert(font, toHaveTrait: traits)

        storage.addAttributes([
            .foregroundColor: kind.color,
            .font: resolved,
        ], range: range)
    }
}
