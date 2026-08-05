import Foundation

/// Offsets where each line begins, for mapping a character offset to a line
/// number without rescanning the text.
///
/// Rebuilt only when the text changes — recomputing this per scroll frame is
/// what made line numbers drift on large files.
struct LineIndex {

    private(set) var starts: [Int] = [0]

    /// Number of lines, counting the empty one after a trailing newline.
    var count: Int { starts.count }

    mutating func rebuild(for text: NSString) {
        var starts: [Int] = [0]
        var index = 0
        while index < text.length {
            let line = text.lineRange(for: NSRange(location: index, length: 0))
            let next = NSMaxRange(line)
            guard next > index else { break }
            if next < text.length { starts.append(next) }
            index = next
        }

        // A file ending in a line terminator has one more line after it — the
        // empty one the caret sits on. The caret's own line count includes it,
        // so the gutter has to number it too, or the status bar and the gutter
        // disagree about which line you are on at the end of a file.
        if text.length > 0 {
            var end = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &end, contentsEnd: &contentsEnd,
                              for: NSRange(location: text.length - 1, length: 0))
            if end > contentsEnd { starts.append(text.length) }
        }

        self.starts = starts
    }

    /// Zero-based index of the line containing `offset`.
    func line(containing offset: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Character offset where the given zero-based line begins.
    func start(of line: Int) -> Int {
        starts[min(max(0, line), starts.count - 1)]
    }
}
