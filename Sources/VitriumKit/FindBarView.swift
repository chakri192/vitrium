import AppKit

protocol FindBarDelegate: AnyObject {
    func findBarDidChangeQuery(_ bar: FindBarView)
    func findBarFindNext(_ bar: FindBarView, backwards: Bool)
    func findBarReplace(_ bar: FindBarView)
    func findBarReplaceAll(_ bar: FindBarView)
    func findBarDidDismiss(_ bar: FindBarView)
}

/// A slim glass find/replace strip that drops in above the editor.
final class FindBarView: NSView, NSTextFieldDelegate {

    weak var delegate: FindBarDelegate?

    private let findField = FindBarView.makeField(placeholder: "Find")
    private let replaceField = FindBarView.makeField(placeholder: "Replace")
    private let countLabel = NSTextField(labelWithString: "")
    private let caseButton = FindBarView.makeToggle(title: "Aa", tooltip: "Match case")
    private let wordButton = FindBarView.makeToggle(title: "W", tooltip: "Whole word")
    private let previousButton = FindBarView.makeIconButton(symbol: "chevron.up", tooltip: "Previous match")
    private let nextButton = FindBarView.makeIconButton(symbol: "chevron.down", tooltip: "Next match")
    private let replaceButton = FindBarView.makeTextButton(title: "Replace")
    private let replaceAllButton = FindBarView.makeTextButton(title: "All")
    private let closeButton = FindBarView.makeIconButton(symbol: "xmark", tooltip: "Close")

    private var replaceRow: NSStackView!
    private var stack: NSStackView!

    var query: String { findField.stringValue }
    var replacement: String { replaceField.stringValue }
    var matchesCase: Bool { caseButton.state == .on }
    var wholeWord: Bool { wordButton.state == .on }

    private(set) var showsReplace = false

    override var isOpaque: Bool { false }

    /// Otherwise clicks on the bar drag the window instead of reaching the
    /// controls — see the note in `TabBarView`.
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        build()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Build

    private func build() {
        findField.delegate = self
        replaceField.delegate = self

        countLabel.font = Theme.uiFont(size: 11)
        countLabel.textColor = Theme.dimForeground
        countLabel.alignment = .right
        countLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true

        caseButton.target = self; caseButton.action = #selector(optionChanged)
        wordButton.target = self; wordButton.action = #selector(optionChanged)
        previousButton.target = self; previousButton.action = #selector(findPrevious)
        nextButton.target = self; nextButton.action = #selector(findNext)
        replaceButton.target = self; replaceButton.action = #selector(replace)
        replaceAllButton.target = self; replaceAllButton.action = #selector(replaceAll)
        closeButton.target = self; closeButton.action = #selector(dismiss)

        let findRow = NSStackView(views: [
            findField, countLabel, caseButton, wordButton,
            previousButton, nextButton, closeButton,
        ])
        findRow.orientation = .horizontal
        findRow.spacing = 6
        findRow.alignment = .centerY
        findField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        replaceRow = NSStackView(views: [replaceField, replaceButton, replaceAllButton])
        replaceRow.orientation = .horizontal
        replaceRow.spacing = 6
        replaceRow.alignment = .centerY
        replaceRow.isHidden = true

        stack = NSStackView(views: [findRow, replaceRow])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            findRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            replaceRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Theme.hairline.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    // MARK: Presentation

    func present(showingReplace: Bool, seed: String?, in window: NSWindow?) {
        showsReplace = showingReplace
        replaceRow.isHidden = !showingReplace
        if let seed, !seed.isEmpty { findField.stringValue = seed }
        isHidden = false
        window?.makeFirstResponder(findField)
        findField.currentEditor()?.selectAll(nil)
        delegate?.findBarDidChangeQuery(self)
    }

    func updateMatchCount(current: Int, total: Int) {
        if query.isEmpty {
            countLabel.stringValue = ""
        } else if total == 0 {
            countLabel.stringValue = "No results"
            countLabel.textColor = Theme.number
        } else {
            countLabel.stringValue = "\(current) of \(total)"
            countLabel.textColor = Theme.dimForeground
        }
    }

    // MARK: Actions

    @objc private func optionChanged() {
        updateToggleAppearance()
        delegate?.findBarDidChangeQuery(self)
    }

    private func updateToggleAppearance() {
        for button in [caseButton, wordButton] {
            let on = button.state == .on
            button.contentTintColor = on ? Theme.accent : Theme.dimForeground
            button.layer?.backgroundColor = on
                ? NSColor(white: 1, alpha: 0.12).cgColor
                : NSColor.clear.cgColor
        }
    }

    @objc private func findNext() { delegate?.findBarFindNext(self, backwards: false) }
    @objc private func findPrevious() { delegate?.findBarFindNext(self, backwards: true) }
    @objc private func replace() { delegate?.findBarReplace(self) }
    @objc private func replaceAll() { delegate?.findBarReplaceAll(self) }
    @objc private func dismiss() { delegate?.findBarDidDismiss(self) }

    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextField) === findField else { return }
        delegate?.findBarDidChangeQuery(self)
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if control === replaceField {
                delegate?.findBarReplace(self)
            } else {
                let backwards = NSEvent.modifierFlags.contains(.shift)
                delegate?.findBarFindNext(self, backwards: backwards)
            }
            return true
        // Escape in a field editor is bound to `complete:` (word completion),
        // not `cancelOperation:` — handling only the latter meant Escape did
        // nothing at all. There is nothing to complete in a find field, so both
        // mean "close this".
        case #selector(NSResponder.cancelOperation(_:)),
             #selector(NSStandardKeyBindingResponding.complete(_:)):
            delegate?.findBarDidDismiss(self)
            return true
        default:
            return false
        }
    }

    // MARK: Factories

    private static func makeField(placeholder: String) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.font = Theme.uiFont(size: 12)
        field.textColor = Theme.foreground
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor(white: 1, alpha: 0.08)
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.cornerRadius = 5
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return field
    }

    private static func makeToggle(title: String, tooltip: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.setButtonType(.pushOnPushOff)
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = Theme.uiFont(size: 11, weight: .semibold)
        button.contentTintColor = Theme.dimForeground
        button.toolTip = tooltip
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return button
    }

    private static func makeIconButton(symbol: String, tooltip: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .inline
        button.contentTintColor = Theme.dimForeground
        button.toolTip = tooltip
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return button
    }

    private static func makeTextButton(title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = Theme.uiFont(size: 11.5)
        button.contentTintColor = Theme.foreground
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        button.layer?.cornerRadius = 5
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
        return button
    }
}
