import Foundation

enum TextSearcher {

    /// Every match of `query` in `text`, in document order.
    static func matches(of query: String, in text: String,
                        matchCase: Bool, wholeWord: Bool) -> [NSRange] {
        guard !query.isEmpty else { return [] }

        var pattern = NSRegularExpression.escapedPattern(for: query)
        if wholeWord {
            // \b only means anything next to a word character; wrapping a query
            // that starts or ends with punctuation in \b would match nothing.
            let leading = query.first.map(isWordCharacter) ?? false
            let trailing = query.last.map(isWordCharacter) ?? false
            if leading { pattern = "\\b" + pattern }
            if trailing { pattern += "\\b" }
        }

        let options: NSRegularExpression.Options = matchCase ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }

        let full = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, options: [], range: full).map(\.range)
    }

    /// Index of the match to jump to from `origin`, wrapping around the ends.
    static func nextIndex(in matches: [NSRange], from origin: Int, backwards: Bool) -> Int? {
        guard !matches.isEmpty else { return nil }
        if backwards {
            for (index, range) in matches.enumerated().reversed() where range.location < origin {
                return index
            }
            return matches.count - 1
        } else {
            for (index, range) in matches.enumerated() where range.location >= origin {
                return index
            }
            return 0
        }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}
