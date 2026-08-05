import AppKit

enum TokenKind {
    case keyword, string, comment, number, function, type

    var color: NSColor {
        switch self {
        case .keyword:  return Theme.keyword
        case .string:   return Theme.string
        case .comment:  return Theme.comment
        case .number:   return Theme.number
        case .function: return Theme.function
        case .type:     return Theme.type
        }
    }

    var isItalic: Bool { self == .comment }
    var isBold: Bool { self == .keyword }
}

struct SyntaxRule {
    let pattern: String
    let kind: TokenKind

    /// The rules get merged into one alternation, so per-rule options travel as
    /// inline ICU flags rather than as `NSRegularExpression.Options`.
    private static func inlineFlags(for options: NSRegularExpression.Options) -> String {
        var flags = ""
        if options.contains(.dotMatchesLineSeparators) { flags += "s" }
        if options.contains(.anchorsMatchLines) { flags += "m" }
        if options.contains(.caseInsensitive) { flags += "i" }
        return flags
    }

    init?(_ pattern: String, _ kind: TokenKind, options: NSRegularExpression.Options = []) {
        let flags = Self.inlineFlags(for: options)
        let wrapped = flags.isEmpty ? "(?:\(pattern))" : "(?\(flags):\(pattern))"

        // Compile once here purely to reject a malformed pattern up front — one
        // bad rule would otherwise take the whole combined regex down with it.
        guard (try? NSRegularExpression(pattern: wrapped)) != nil else {
            assertionFailure("bad syntax pattern: \(pattern)")
            return nil
        }
        self.pattern = wrapped
        self.kind = kind
    }
}

enum Language: String, CaseIterable {
    case plain, python, c, swift, javascript, shell, yaml, json, markdown

    // MARK: Detection

    private static let extensionMap: [String: Language] = [
        "py": .python, "pyw": .python,
        "c": .c, "h": .c, "cpp": .c, "hpp": .c, "cc": .c, "cxx": .c, "m": .c, "mm": .c,
        "swift": .swift,
        "js": .javascript, "jsx": .javascript, "ts": .javascript, "tsx": .javascript, "mjs": .javascript, "cjs": .javascript,
        "sh": .shell, "bash": .shell, "zsh": .shell, "fish": .shell,
        "yaml": .yaml, "yml": .yaml,
        "json": .json,
        "md": .markdown, "markdown": .markdown,
        "txt": .plain,
    ]

    /// Files that carry their language in the *name*, not an extension.
    private static let filenameMap: [String: Language] = [
        "makefile": .shell, "dockerfile": .shell, ".zshrc": .shell,
        ".bashrc": .shell, ".bash_profile": .shell, ".profile": .shell,
        "package.swift": .swift,
    ]

    static func detect(url: URL) -> Language {
        let name = url.lastPathComponent.lowercased()
        if let byName = filenameMap[name] { return byName }
        return extensionMap[url.pathExtension.lowercased()] ?? .plain
    }

    /// The extension the save dialog offers when the user types a bare name.
    /// Reverse of `extensionMap` — a new Python tab shouldn't save extensionless.
    var defaultExtension: String {
        switch self {
        case .plain:      return "txt"
        case .python:     return "py"
        case .c:          return "c"
        case .swift:      return "swift"
        case .javascript: return "js"
        case .shell:      return "sh"
        case .yaml:       return "yaml"
        case .json:       return "json"
        case .markdown:   return "md"
        }
    }

    var displayName: String {
        switch self {
        case .plain:      return "Plain Text"
        case .python:     return "Python"
        case .c:          return "C/C++"
        case .swift:      return "Swift"
        case .javascript: return "JavaScript"
        case .shell:      return "Shell"
        case .yaml:       return "YAML"
        case .json:       return "JSON"
        case .markdown:   return "Markdown"
        }
    }

    /// Line-comment prefix, or nil where the language has no single-line
    /// comment syntax at all (JSON, plain text) — comment-toggle is a no-op there.
    var lineCommentPrefix: String? {
        switch self {
        case .python, .shell, .yaml:  return "#"
        case .c, .swift, .javascript: return "//"
        case .json, .markdown, .plain: return nil
        }
    }

    var blockComment: (open: String, close: String)? {
        switch self {
        case .c, .swift, .javascript: return ("/*", "*/")
        default: return nil
        }
    }

    // MARK: Keywords

    private var keywords: [String] {
        switch self {
        case .python: return [
            "and", "as", "assert", "async", "await", "break", "class", "continue",
            "def", "del", "elif", "else", "except", "finally", "for", "from",
            "global", "if", "import", "in", "is", "lambda", "nonlocal", "not",
            "or", "pass", "raise", "return", "try", "while", "with", "yield",
            "None", "True", "False", "self",
        ]
        case .c: return [
            "auto", "break", "case", "char", "const", "continue", "default", "do",
            "double", "else", "enum", "extern", "float", "for", "goto", "if",
            "inline", "int", "long", "namespace", "register", "restrict", "return",
            "short", "signed", "sizeof", "static", "struct", "switch", "template",
            "typedef", "typename", "union", "unsigned", "void", "volatile", "while",
            "class", "public", "private", "protected", "virtual", "override", "new",
            "delete", "nullptr", "true", "false", "using", "constexpr", "explicit",
            "include", "define", "ifndef", "ifdef", "endif", "pragma",
        ]
        case .swift: return [
            "associatedtype", "actor", "any", "as", "async", "await", "break",
            "case", "catch", "class", "continue", "default", "defer", "deinit",
            "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate",
            "for", "func", "guard", "if", "import", "in", "init", "inout",
            "internal", "is", "let", "nil", "open", "operator", "private",
            "protocol", "public", "repeat", "return", "self", "Self", "some",
            "static", "struct", "subscript", "super", "switch", "throw", "throws",
            "true", "try", "typealias", "var", "weak", "where", "while", "lazy",
            "mutating", "nonisolated", "override", "required", "final", "convenience",
        ]
        case .javascript: return [
            "async", "await", "break", "case", "catch", "class", "const", "continue",
            "debugger", "default", "delete", "do", "else", "export", "extends",
            "finally", "for", "function", "if", "import", "in", "instanceof", "let",
            "new", "of", "return", "static", "super", "switch", "this", "throw",
            "try", "typeof", "var", "void", "while", "yield", "true", "false",
            "null", "undefined", "interface", "type", "enum", "implements", "as",
        ]
        case .shell: return [
            "if", "then", "else", "elif", "fi", "for", "while", "until", "do",
            "done", "case", "esac", "function", "return", "local", "export",
            "readonly", "shift", "break", "continue", "in", "select", "time",
            "source", "alias", "unset", "echo", "cd",
        ]
        case .json: return ["true", "false", "null"]
        default: return []
        }
    }

    // MARK: Rules

    /// Rules in **precedence order — the first one that matches at a given
    /// position wins**, and the rest are not consulted for those characters.
    ///
    /// That ordering is the whole point: comments and strings come first, so a
    /// keyword inside a docstring stays string-coloured and a quote inside a
    /// comment doesn't open a string. A "last rule overwrites" scheme can't
    /// express that — whichever of the two you put last wins in *both*
    /// directions, and one of them is always wrong.
    var rules: [SyntaxRule] {
        var rules: [SyntaxRule] = []

        func add(_ pattern: String, _ kind: TokenKind, _ options: NSRegularExpression.Options = []) {
            if let rule = SyntaxRule(pattern, kind, options: options) { rules.append(rule) }
        }

        // Single-line string literals must not swallow newlines, or one unclosed
        // quote paints the rest of the file green.
        let doubleQuoted = #""[^"\\\n]*(?:\\.[^"\\\n]*)*""#
        let singleQuoted = #"'[^'\\\n]*(?:\\.[^'\\\n]*)*'"#

        func addKeywords() {
            guard !keywords.isEmpty else { return }
            let alternation = keywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            add("\\b(?:\(alternation))\\b", .keyword)
        }

        if let block = blockComment {
            let open = NSRegularExpression.escapedPattern(for: block.open)
            let close = NSRegularExpression.escapedPattern(for: block.close)
            // Closed comment, or an unterminated one running to end of file.
            add("\(open)(?:[\\s\\S]*?\(close)|[\\s\\S]*)", .comment)
        }

        switch self {
        case .python:
            add("#[^\n]*", .comment)
            add(#"(?:[rRbBfFuU]{0,2})""".*?""""#, .string, [.dotMatchesLineSeparators])
            add(#"(?:[rRbBfFuU]{0,2})'''.*?'''"#, .string, [.dotMatchesLineSeparators])
            add("(?:[rRbBfFuU]{0,2})\(doubleQuoted)", .string)
            add("(?:[rRbBfFuU]{0,2})\(singleQuoted)", .string)
            add(#"@[A-Za-z_][A-Za-z0-9_.]*"#, .type)
            addKeywords()
            add(#"\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .number)
            add(#"\b[A-Za-z_][A-Za-z0-9_]*(?=\()"#, .function)

        case .c:
            add("//[^\n]*", .comment)
            add(doubleQuoted, .string)
            add(#"'(?:[^'\\\n]|\\.)'"#, .string)
            add("^\\s*#\\s*[a-z]+", .keyword, [.anchorsMatchLines])
            addKeywords()
            add(#"\b(?:0[xX][0-9a-fA-F']+|0[bB][01']+|\d[\d']*(?:\.\d+)?(?:[eE][+-]?\d+)?)[fFuUlL]*\b"#, .number)
            add(#"\b[A-Za-z_][A-Za-z0-9_]*(?=\()"#, .function)
            add(#"\b[A-Z][A-Za-z0-9_]*\b"#, .type)

        case .swift:
            add("//[^\n]*", .comment)
            add(##"#"""[\s\S]*?"""#"##, .string)
            add(#"""".*?""""#, .string, [.dotMatchesLineSeparators])
            add(##"#"[^"\n]*"#"##, .string)
            add(doubleQuoted, .string)
            add(#"@[A-Za-z_][A-Za-z0-9_]*"#, .type)
            addKeywords()
            add(#"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0o[0-7_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#, .number)
            add(#"\b[A-Za-z_][A-Za-z0-9_]*(?=\()"#, .function)
            add(#"\b[A-Z][A-Za-z0-9_]*\b"#, .type)

        case .javascript:
            add("//[^\n]*", .comment)
            add("`[^`\\\\]*(?:\\\\[\\s\\S][^`\\\\]*)*`", .string, [.dotMatchesLineSeparators])
            add(doubleQuoted, .string)
            add(singleQuoted, .string)
            addKeywords()
            add(#"\b(?:0[xX][0-9a-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)n?\b"#, .number)
            add(#"\b[A-Za-z_$][A-Za-z0-9_$]*(?=\()"#, .function)
            add(#"\b[A-Z][A-Za-z0-9_$]*\b"#, .type)

        case .shell:
            add("#[^\n]*", .comment)
            add(doubleQuoted, .string)
            add(#"'[^'\n]*'"#, .string)
            add(#"\$(?:[A-Za-z_][A-Za-z0-9_]*|\{[^}\n]*\}|\([^)\n]*\)|[0-9@*#?$!])"#, .type)
            add(#"^[ \t]*[A-Za-z_][A-Za-z0-9_]*(?=[ \t]*\([ \t]*\))"#, .function, [.anchorsMatchLines])
            addKeywords()
            add(#"\b\d+\b"#, .number)

        case .yaml:
            add("#[^\n]*", .comment)
            add(doubleQuoted, .string)
            add(#"'[^'\n]*'"#, .string)
            add(#"^[ \t]*-[ \t]"#, .function, [.anchorsMatchLines])
            add(#"^[ \t]*[^:#\n]+(?=[ \t]*:)"#, .type, [.anchorsMatchLines])
            add(#"\b(?:true|false|null|yes|no|~)\b"#, .keyword)
            add(#"[&*][A-Za-z0-9_-]+"#, .function)
            add(#"-?\b\d+(?:\.\d+)?\b"#, .number)

        case .json:
            // The key rule has to come first — both it and the plain string rule
            // match a quoted run, and only the lookahead tells them apart.
            add("\(doubleQuoted)(?=\\s*:)", .type)
            add(doubleQuoted, .string)
            add(#"\b(?:true|false|null)\b"#, .keyword)
            add(#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .number)

        case .markdown:
            add(#"^ {0,3}#{1,6}\s.*$"#, .keyword, [.anchorsMatchLines])
            add(#"^ {0,3}>.*$"#, .comment, [.anchorsMatchLines])
            add("```[\\s\\S]*?```", .string)
            add("`[^`\n]+`", .function)
            add(#"\[[^\]\n]*\]\([^)\n]*\)"#, .function)
            add(#"\*\*[^*\n]+\*\*"#, .type)
            add(#"(?<!\*)\*[^*\n]+\*(?!\*)"#, .string)
            add(#"^[ \t]*(?:[-*+]|\d+\.)\s"#, .number, [.anchorsMatchLines])

        case .plain:
            break
        }

        return rules
    }
}
