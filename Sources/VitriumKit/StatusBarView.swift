import AppKit

/// The hairline strip along the bottom: path on the left, caret position,
/// language and document facts on the right.
final class StatusBarView: NSView {

    private let leftLabel = NSTextField(labelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")
    private let extrasLabel = NSTextField(labelWithString: "")
    private let languageButton = NSButton(title: "", target: nil, action: nil)

    private var currentLanguage: Language = .plain

    /// Set when the user picks a language by hand. A new tab has no file
    /// extension to detect from, so without this nothing is ever highlighted
    /// until the tab is saved.
    var onSelectLanguage: ((Language) -> Void)?

    override var isOpaque: Bool { false }

    /// The window is movable by its background; without this, clicking the
    /// language button would drag the window instead. Same trap as the tab strip.
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        for label in [leftLabel, positionLabel, extrasLabel] {
            label.font = Theme.uiFont(size: 10.5)
            label.textColor = Theme.dimForeground
            label.lineBreakMode = .byTruncatingHead
        }
        leftLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftLabel)

        languageButton.font = Theme.uiFont(size: 10.5)
        languageButton.isBordered = false
        languageButton.bezelStyle = .inline
        languageButton.contentTintColor = Theme.dimForeground
        languageButton.toolTip = "Set the language for this tab"
        languageButton.target = self
        languageButton.action = #selector(pickLanguage)

        for view in [positionLabel, extrasLabel, languageButton] as [NSView] {
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        let right = NSStackView(views: [positionLabel, languageButton, extrasLabel])
        right.orientation = .horizontal
        right.spacing = 10
        right.alignment = .centerY
        right.translatesAutoresizingMaskIntoConstraints = false
        addSubview(right)

        NSLayoutConstraint.activate([
            leftLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            leftLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.leadingAnchor.constraint(greaterThanOrEqualTo: leftLabel.trailingAnchor, constant: 12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        Theme.hairline.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    func update(path: String, line: Int, column: Int, language: Language,
                wraps: Bool, fontSize: CGFloat) {
        leftLabel.stringValue = path
        positionLabel.stringValue = "Ln \(line), Col \(column)"

        currentLanguage = language
        languageButton.title = language.displayName

        var extras: [String] = []
        if !wraps { extras.append("No Wrap") }
        if abs(fontSize - Theme.defaultFontSize) > 0.5 { extras.append("\(Int(fontSize))pt") }
        extrasLabel.stringValue = extras.joined(separator: "   ")
        extrasLabel.isHidden = extras.isEmpty
    }

    // MARK: Language menu

    @objc private func pickLanguage() {
        let menu = NSMenu()
        for language in Language.allCases {
            let item = NSMenuItem(title: language.displayName,
                                  action: #selector(languageChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language
            item.state = language == currentLanguage ? .on : .off
            menu.addItem(item)
        }
        // Positioned against the current entry so the menu opens over the
        // button — the status bar is at the bottom of the window, and a menu
        // dropped downwards would run off the bottom of the screen.
        menu.popUp(positioning: menu.item(withTitle: currentLanguage.displayName),
                   at: NSPoint(x: 0, y: -4), in: languageButton)
    }

    @objc private func languageChosen(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? Language else { return }
        onSelectLanguage?(language)
    }

    /// Transient message (save confirmations, errors) shown on the left.
    func flash(_ message: String, revertingTo path: String) {
        leftLabel.stringValue = message
        leftLabel.textColor = Theme.accent
        let token = UUID()
        flashToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self, self.flashToken == token else { return }
            self.leftLabel.textColor = Theme.dimForeground
            self.leftLabel.stringValue = path
        }
    }

    private var flashToken: UUID?
}
