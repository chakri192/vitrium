import AppKit

/// The hairline strip along the bottom: path on the left, caret position and
/// document facts on the right.
final class StatusBarView: NSView {

    private let leftLabel = NSTextField(labelWithString: "")
    private let rightLabel = NSTextField(labelWithString: "")

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        for label in [leftLabel, rightLabel] {
            label.font = Theme.uiFont(size: 10.5)
            label.textColor = Theme.dimForeground
            label.lineBreakMode = .byTruncatingHead
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        rightLabel.alignment = .right
        rightLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            leftLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            leftLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rightLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leftLabel.trailingAnchor, constant: 12),
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
        var right = "Ln \(line), Col \(column)   \(language.displayName)"
        if !wraps { right += "   No Wrap" }
        if abs(fontSize - Theme.defaultFontSize) > 0.5 { right += "   \(Int(fontSize))pt" }
        rightLabel.stringValue = right
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
