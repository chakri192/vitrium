import Foundation

/// A minimal assertion harness.
///
/// Deliberately dependency-free: XCTest needs Xcode and the Command Line Tools'
/// swift-testing is missing its Foundation overlay, so neither is available on a
/// plain CLT machine. This is small enough to be obviously correct.
final class TestRunner {

    private var passed = 0
    private var failed = 0
    private var currentFailures: [String] = []
    private var currentName = ""
    private var currentSuite = ""

    private enum Colour {
        static let reset = "\u{1B}[0m"
        static let green = "\u{1B}[32m"
        static let red = "\u{1B}[31m"
        static let dim = "\u{1B}[2m"
        static let bold = "\u{1B}[1m"
    }

    func suite(_ name: String, _ body: () -> Void) {
        currentSuite = name
        print("\n\(Colour.bold)\(name)\(Colour.reset)")
        body()
    }

    func test(_ name: String, _ body: () -> Void) {
        currentName = name
        currentFailures = []
        body()

        if currentFailures.isEmpty {
            passed += 1
            print("  \(Colour.green)✓\(Colour.reset) \(name)")
        } else {
            failed += 1
            print("  \(Colour.red)✗ \(name)\(Colour.reset)")
            for failure in currentFailures {
                print("      \(Colour.red)\(failure)\(Colour.reset)")
            }
        }
    }

    // MARK: Assertions

    func expect(_ condition: Bool, _ message: @autoclosure () -> String = "expected true",
                line: Int = #line) {
        guard !condition else { return }
        currentFailures.append("line \(line): \(message())")
    }

    func expectEqual<T: Equatable>(_ actual: T, _ expected: T,
                                   _ message: @autoclosure () -> String = "",
                                   line: Int = #line) {
        guard actual != expected else { return }
        let note = message().isEmpty ? "" : " — \(message())"
        currentFailures.append("""
        line \(line): expected \(describe(expected)), got \(describe(actual))\(note)
        """)
    }

    func expectNil<T>(_ value: T?, _ message: @autoclosure () -> String = "expected nil",
                      line: Int = #line) {
        guard value != nil else { return }
        currentFailures.append("line \(line): \(message()) — got \(describe(value!))")
    }

    /// Escapes newlines so a multi-line mismatch stays on one readable line.
    private func describe<T>(_ value: T) -> String {
        let text = String(describing: value)
        return "\"\(text.replacingOccurrences(of: "\n", with: "\\n"))\""
    }

    // MARK: Result

    func finish() -> Never {
        let total = passed + failed
        print("")
        if failed == 0 {
            print("\(Colour.green)\(Colour.bold)All \(total) tests passed.\(Colour.reset)")
            exit(0)
        } else {
            print("\(Colour.red)\(Colour.bold)\(failed) of \(total) tests failed.\(Colour.reset)")
            exit(1)
        }
    }
}
