import AppKit
@testable import VitriumKit

// NSTextView and friends need an application instance to exist, even headless.
_ = NSApplication.shared

let runner = TestRunner()

// MARK: - Helpers

/// Keeps the highlighter alive alongside the storage — the storage holds only a
/// weak delegate reference.
final class Sample {
    let storage = NSTextStorage()
    let highlighter: SyntaxHighlighter

    init(_ text: String, _ language: Language) {
        highlighter = SyntaxHighlighter(textStorage: storage)
        highlighter.language = language
        storage.setAttributedString(NSAttributedString(string: text))
        highlighter.rehighlightAll()
    }

    func colour(at location: Int) -> NSColor? {
        storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    func font(at location: Int) -> NSFont? {
        storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }
}

/// The colour applied to the first character of `needle`.
func colour(of needle: String, in text: String, _ language: Language) -> NSColor? {
    let range = (text as NSString).range(of: needle)
    guard range.location != NSNotFound else { return nil }
    return Sample(text, language).colour(at: range.location)
}

func font(of needle: String, in text: String, _ language: Language) -> NSFont? {
    let range = (text as NSString).range(of: needle)
    guard range.location != NSNotFound else { return nil }
    return Sample(text, language).font(at: range.location)
}

func editor(_ text: String, language: Language = .python,
            select: NSRange = NSRange(location: 0, length: 0)) -> EditorTextView {
    let pane = EditorPane(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    pane.language = language
    pane.text = text
    pane.textView.setSelectedRange(select)
    return pane.textView
}

func range(of needle: String, in text: String) -> NSRange {
    (text as NSString).range(of: needle)
}

// MARK: - Syntax highlighting

runner.suite("Syntax rules") {

    runner.test("every language's rules combine into a valid regex") {
        for language in Language.allCases {
            let rules = language.rules
            if language == .plain {
                runner.expect(rules.isEmpty, "plain text should have no rules")
                continue
            }
            runner.expect(!rules.isEmpty, "\(language) has no rules")

            let combined = rules.indices
                .map { "(?<v\($0)>\(rules[$0].pattern))" }
                .joined(separator: "|")
            let compiled = try? NSRegularExpression(pattern: combined)
            runner.expect(compiled != nil, "\(language)'s combined regex does not compile")
        }
    }

    runner.test("a keyword inside a string stays a string") {
        let source = "\"\"\"Sample file for checking things.\"\"\"\n"
        runner.expectEqual(colour(of: "for", in: source, .python), Theme.string)
    }

    // The original bug: the string rule recoloured the keyword but left its bold
    // face behind, so `for` came out green *and* bold inside a docstring.
    runner.test("a keyword inside a string loses its bold face") {
        let source = "\"\"\"A pane with an opacity.\"\"\"\n"
        let inString = font(of: "with", in: source, .python)
        let plain = font(of: "pane", in: source, .python)
        runner.expectEqual(inString?.fontName, plain?.fontName, "keyword styling leaked into a string")
    }

    runner.test("a quote inside a comment does not open a string") {
        let source = "# it's fine\nvalue = 1\n"
        runner.expectEqual(colour(of: "value", in: source, .python), Theme.foreground)
    }

    runner.test("a comment marker inside a string stays a string") {
        let source = "url = \"http://example.com/#anchor\"\n"
        runner.expectEqual(colour(of: "#anchor", in: source, .python), Theme.string)
    }

    runner.test("an unclosed quote does not colour the rest of the file") {
        let source = "a = 'unclosed\nb = 2\nc = 3\n"
        runner.expectEqual(colour(of: "b = 2", in: source, .python), Theme.foreground)
    }

    runner.test("a block comment spans lines") {
        let source = "int a;\n/* explanation\n   continues */\nint b;\n"
        runner.expectEqual(colour(of: "continues", in: source, .c), Theme.comment)
        runner.expectEqual(colour(of: "int b", in: source, .c), Theme.keyword)
    }

    runner.test("a block-comment opener inside a line comment does not run away") {
        let source = "// see /* below\nint after;\n"
        runner.expectEqual(colour(of: "int after", in: source, .c), Theme.keyword)
    }

    runner.test("an unterminated block comment runs to end of file") {
        let source = "int a;\n/* forgot to close\nint b;\n"
        runner.expectEqual(colour(of: "int b", in: source, .c), Theme.comment)
    }

    runner.test("JSON keys and values are distinguished") {
        let source = "{\n  \"name\": \"vitrium\",\n  \"count\": 3\n}\n"
        runner.expectEqual(colour(of: "\"name\"", in: source, .json), Theme.type)
        runner.expectEqual(colour(of: "\"vitrium\"", in: source, .json), Theme.string)
        runner.expectEqual(colour(of: "3", in: source, .json), Theme.number)
    }

    runner.test("C hex and binary literals are numbers") {
        let source = "int values[] = {0xFF, 0b1010, 42};\n"
        runner.expectEqual(colour(of: "0xFF", in: source, .c), Theme.number)
        runner.expectEqual(colour(of: "0b1010", in: source, .c), Theme.number)
        runner.expectEqual(colour(of: "42", in: source, .c), Theme.number)
    }

    // Colouring after an edit has to match colouring from scratch, or the
    // display drifts from the truth the longer a session runs.
    runner.test("an incremental edit matches a full rehighlight") {
        let sample = Sample("int a;\nint b;\n", .c)

        // Open a block comment on line 1; everything below must go comment-coloured.
        sample.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "/* ")

        let target = (sample.storage.string as NSString).range(of: "int b")
        let incremental = sample.colour(at: target.location)

        sample.highlighter.rehighlightAll()
        let fromScratch = sample.colour(at: target.location)

        runner.expectEqual(incremental, fromScratch, "incremental colouring drifted")
        runner.expectEqual(incremental, Theme.comment)
    }
}

// MARK: - Language metadata

runner.suite("Language detection") {

    runner.test("detects by extension and by filename") {
        runner.expectEqual(Language.detect(url: URL(fileURLWithPath: "/a/b.py")), .python)
        runner.expectEqual(Language.detect(url: URL(fileURLWithPath: "/a/b.tsx")), .javascript)
        runner.expectEqual(Language.detect(url: URL(fileURLWithPath: "/a/Makefile")), .shell)
        runner.expectEqual(Language.detect(url: URL(fileURLWithPath: "/a/Package.swift")), .swift)
        runner.expectEqual(Language.detect(url: URL(fileURLWithPath: "/a/notes")), .plain)
    }

    // Every language must round-trip through its own default extension, or
    // saving an untitled tab lands it in a different language than it started.
    runner.test("every default extension round-trips") {
        for language in Language.allCases {
            let url = URL(fileURLWithPath: "/tmp/sample.\(language.defaultExtension)")
            runner.expectEqual(Language.detect(url: url), language,
                               "does not round-trip via .\(language.defaultExtension)")
        }
    }
}

// MARK: - Editing

runner.suite("Comment toggle") {

    runner.test("adds and removes cleanly") {
        let source = "a = 1\nb = 2\n"
        let view = editor(source, select: NSRange(location: 0, length: 12))

        view.toggleComment()
        runner.expectEqual(view.string, "# a = 1\n# b = 2\n")

        view.toggleComment()
        runner.expectEqual(view.string, source, "comment toggle did not round-trip")
    }

    runner.test("aligns to the shallowest shared indent") {
        let source = "def f():\n    if x:\n        y()\n"
        let view = editor(source, select: range(of: "    if x:\n        y()\n", in: source))
        view.toggleComment()
        runner.expectEqual(view.string, "def f():\n    # if x:\n    #     y()\n")
    }

    runner.test("uncomments only when every line is commented") {
        let source = "# a = 1\nb = 2\n"
        let view = editor(source, select: NSRange(location: 0, length: 14))
        view.toggleComment()
        runner.expectEqual(view.string, "# # a = 1\n# b = 2\n",
                           "a partly-commented block should comment, not uncomment")
    }

    runner.test("uses the language's own prefix") {
        let view = editor("int a;\n", language: .c, select: NSRange(location: 0, length: 7))
        view.toggleComment()
        runner.expectEqual(view.string, "// int a;\n")
    }

    runner.test("is a no-op where there is no comment syntax") {
        let source = "{\"a\": 1}\n"
        let view = editor(source, language: .json, select: NSRange(location: 0, length: 9))
        view.toggleComment()
        runner.expectEqual(view.string, source)
    }

    runner.test("undoes in a single step") {
        let source = "a = 1\nb = 2\n"
        let view = editor(source, select: NSRange(location: 0, length: 12))
        view.toggleComment()
        runner.expect(view.string != source, "toggle did nothing")

        view.undoManager?.undo()
        runner.expectEqual(view.string, source, "one toggle should undo in one step")
    }
}

runner.suite("Undo isolation") {

    // Tabs must not share an undo stack, or undoing in one walks back an edit
    // made in another.
    runner.test("each tab has its own undo manager") {
        let first = editor("one\n", select: NSRange(location: 0, length: 4))
        let second = editor("two\n", select: NSRange(location: 0, length: 4))

        runner.expect(first.undoManager !== second.undoManager,
                      "two tabs are sharing one undo stack")

        first.toggleComment()
        runner.expectEqual(first.string, "# one\n")
        runner.expectEqual(second.string, "two\n")

        second.undoManager?.undo()
        runner.expectEqual(first.string, "# one\n", "undo in one tab reached into another")
        runner.expectEqual(second.string, "two\n")
    }
}

runner.suite("Indentation") {

    runner.test("indent and outdent round-trip") {
        let source = "a = 1\nb = 2\n"
        let view = editor(source, select: NSRange(location: 0, length: 12))

        view.indentSelection()
        runner.expectEqual(view.string, "    a = 1\n    b = 2\n")

        view.outdentSelection()
        runner.expectEqual(view.string, source)
    }

    runner.test("outdent handles a partial indent") {
        let view = editor("  a = 1\n", select: NSRange(location: 0, length: 8))
        view.outdentSelection()
        runner.expectEqual(view.string, "a = 1\n")
    }
}

runner.suite("Line operations") {

    runner.test("duplicate line") {
        let view = editor("a = 1\nb = 2\n", select: NSRange(location: 0, length: 0))
        view.duplicateLine()
        runner.expectEqual(view.string, "a = 1\na = 1\nb = 2\n")
    }

    runner.test("move down then up restores the original") {
        let source = "one\ntwo\nthree\n"
        let view = editor(source, select: NSRange(location: 0, length: 0))

        view.moveLine(up: false)
        runner.expectEqual(view.string, "two\none\nthree\n")

        view.moveLine(up: true)
        runner.expectEqual(view.string, source)
    }

    // The last line has no trailing newline, so a naive swap glues it to its
    // neighbour.
    runner.test("move up on the final unterminated line") {
        let view = editor("one\ntwo", select: NSRange(location: 5, length: 0))
        view.moveLine(up: true)
        runner.expectEqual(view.string, "two\none")
    }

    runner.test("move up at the top is a no-op") {
        let source = "one\ntwo\n"
        let view = editor(source, select: NSRange(location: 0, length: 0))
        view.moveLine(up: true)
        runner.expectEqual(view.string, source)
    }

    runner.test("go to line puts the caret at the line start") {
        let view = editor("one\ntwo\nthree\n")
        view.goToLine(3)
        runner.expectEqual(view.selectedRange().location, 8)
        runner.expectEqual(view.caretPosition.line, 3)
        runner.expectEqual(view.caretPosition.column, 1)
    }

    runner.test("go to line beyond the end clamps") {
        let view = editor("one\ntwo\n")
        view.goToLine(99)
        runner.expect(view.selectedRange().location <= (view.string as NSString).length)
    }
}

// MARK: - Line numbering

runner.suite("Line index") {

    func index(_ text: String) -> LineIndex {
        var index = LineIndex()
        index.rebuild(for: text as NSString)
        return index
    }

    runner.test("an empty document has exactly one line") {
        runner.expectEqual(index("").count, 1)
        runner.expectEqual(index("").line(containing: 0), 0)
    }

    runner.test("counts lines without a trailing newline") {
        let starts = index("one\ntwo\nthree")
        runner.expectEqual(starts.count, 3)
        runner.expectEqual(starts.start(of: 0), 0)
        runner.expectEqual(starts.start(of: 1), 4)
        runner.expectEqual(starts.start(of: 2), 8)
    }

    // A file ending in a newline has an empty final line the caret can sit on.
    // Leaving it out made the gutter stop one short of what the status bar said.
    runner.test("counts the empty line after a trailing newline") {
        let starts = index("one\ntwo\n")
        runner.expectEqual(starts.count, 3, "the empty final line should be numbered")
        runner.expectEqual(starts.start(of: 2), 8)
    }

    runner.test("maps offsets to the right line") {
        let starts = index("one\ntwo\nthree\n")
        runner.expectEqual(starts.line(containing: 0), 0)
        runner.expectEqual(starts.line(containing: 3), 0)
        runner.expectEqual(starts.line(containing: 4), 1)
        runner.expectEqual(starts.line(containing: 13), 2)
        runner.expectEqual(starts.line(containing: 14), 3, "end of file is on the empty last line")
    }

    // The gutter and the status bar have to agree about the last line, or the
    // caret sits on a line the gutter never numbers.
    runner.test("line count agrees with the caret's own line number") {
        for text in ["", "one", "one\n", "one\ntwo", "one\ntwo\n", "\n", "\n\n"] {
            let view = editor(text, language: .plain)
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            runner.expectEqual(index(text).count, view.caretPosition.line,
                               "disagreement for \(text.debugDescription)")
        }
    }
}

// MARK: - Dirty tracking

runner.suite("Dirty tracking") {

    runner.test("a fresh untitled document is clean") {
        let document = Document()
        runner.expect(!document.isDirty, "a new tab should not start dirty")
        runner.expect(document.isEmptyUntitled, "a new tab should be reusable")
    }

    runner.test("editing marks dirty and undoing back marks clean again") {
        let document = Document()
        document.language = .python
        document.pane.textView.setSelectedRange(NSRange(location: 0, length: 0))
        document.pane.textView.insertText("a = 1", replacementRange: NSRange(location: 0, length: 0))
        runner.expect(document.isDirty, "an edit should mark the tab dirty")

        document.pane.textView.undoManager?.undo()
        runner.expect(!document.isDirty, "undoing back to the saved state should clear the marker")
    }

    runner.test("an edit that preserves length is still dirty") {
        let document = Document()
        document.pane.textView.insertText("abc", replacementRange: NSRange(location: 0, length: 0))
        // Same length, different content — the length check alone would miss this.
        document.pane.textView.setSelectedRange(NSRange(location: 0, length: 3))
        document.pane.textView.insertText("xyz", replacementRange: NSRange(location: 0, length: 3))
        runner.expect(document.isDirty, "a same-length replacement should still count as an edit")
    }
}

// MARK: - Search

runner.suite("Find") {

    runner.test("respects case sensitivity") {
        let text = "Cat cat CAT"
        runner.expectEqual(TextSearcher.matches(of: "cat", in: text, matchCase: true, wholeWord: false).count, 1)
        runner.expectEqual(TextSearcher.matches(of: "cat", in: text, matchCase: false, wholeWord: false).count, 3)
    }

    runner.test("respects whole-word") {
        let text = "cat category cat"
        runner.expectEqual(TextSearcher.matches(of: "cat", in: text, matchCase: false, wholeWord: true).count, 2)
        runner.expectEqual(TextSearcher.matches(of: "cat", in: text, matchCase: false, wholeWord: false).count, 3)
    }

    // `\b` next to punctuation matches nothing, so a query like `()` would
    // silently return zero results if it were wrapped unconditionally.
    runner.test("whole-word with a punctuation query still matches") {
        let text = "call() and call()"
        runner.expectEqual(TextSearcher.matches(of: "()", in: text, matchCase: false, wholeWord: true).count, 2)
    }

    runner.test("treats the query as literal, not regex") {
        let text = "a.b axb a.b"
        runner.expectEqual(TextSearcher.matches(of: "a.b", in: text, matchCase: true, wholeWord: false).count, 2)
    }

    runner.test("an empty query finds nothing") {
        runner.expect(TextSearcher.matches(of: "", in: "abc", matchCase: false, wholeWord: false).isEmpty)
    }

    runner.test("next match wraps forward") {
        let matches = TextSearcher.matches(of: "x", in: "x_x_x", matchCase: true, wholeWord: false)
        runner.expectEqual(matches.count, 3)
        runner.expectEqual(TextSearcher.nextIndex(in: matches, from: 0, backwards: false), 0)
        runner.expectEqual(TextSearcher.nextIndex(in: matches, from: 1, backwards: false), 1)
        runner.expectEqual(TextSearcher.nextIndex(in: matches, from: 5, backwards: false), 0, "should wrap to the top")
    }

    runner.test("previous match wraps backward") {
        let matches = TextSearcher.matches(of: "x", in: "x_x_x", matchCase: true, wholeWord: false)
        runner.expectEqual(TextSearcher.nextIndex(in: matches, from: 4, backwards: true), 1)
        runner.expectEqual(TextSearcher.nextIndex(in: matches, from: 0, backwards: true), 2, "should wrap to the bottom")
    }

    runner.test("no matches yields no index") {
        runner.expectNil(TextSearcher.nextIndex(in: [], from: 0, backwards: false))
    }
}

// MARK: - File I/O

runner.suite("File I/O") {

    runner.test("saves atomically and reports the new modification date") {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrium-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("sample.py")
        let date = try? FileIO.save(text: "print('hi')\n", to: url)
        runner.expect(date != nil, "save returned no modification date")
        runner.expectEqual(try? String(contentsOf: url, encoding: .utf8), "print('hi')\n")
    }

    runner.test("overwriting leaves no temp files behind") {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrium-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("sample.txt")
        _ = try? FileIO.save(text: "first", to: url)
        _ = try? FileIO.save(text: "second", to: url)

        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        runner.expectEqual(contents.count, 1, "atomic save left a stray file: \(contents)")
        runner.expectEqual(try? String(contentsOf: url, encoding: .utf8), "second")
    }

    runner.test("rejects binary files") {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrium-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("blob.bin")
        try? Data([0x00, 0x01, 0x02]).write(to: url)

        var failure: Error?
        let done = DispatchSemaphore(value: 0)
        FileIO.load(url: url) { result in
            if case .failure(let error) = result { failure = error }
            done.signal()
        }
        // The completion hops to the main queue, which is this thread — pump it.
        while done.wait(timeout: .now()) == .timedOut {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        runner.expect(failure != nil, "a file with null bytes should not load as text")
    }
}

runner.finish()
