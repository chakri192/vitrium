import AppKit

/// The tab strip. Custom-drawn rather than `NSTabView` so it can sit flush in
/// the transparent titlebar and paint nothing but text.
final class TabBarView: NSView {

    struct Item {
        let title: String
        let isDirty: Bool
    }

    var items: [Item] = [] { didSet { rebuildLayout(); needsDisplay = true } }
    var selectedIndex = 0 { didSet { needsDisplay = true } }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNew: (() -> Void)?

    private struct TabFrame {
        let index: Int
        let rect: NSRect
        let closeRect: NSRect
    }

    private var frames: [TabFrame] = []
    private var newButtonRect: NSRect = .zero
    private var hoveredTab: Int?
    private var hoveredClose: Int?
    private var trackingArea: NSTrackingArea?

    private let minTabWidth: CGFloat = 84
    private let maxTabWidth: CGFloat = 190
    private let closeSize: CGFloat = 14
    private let newButtonWidth: CGFloat = 30

    private var titleFont: NSFont { Theme.uiFont(size: 11.5, weight: .medium) }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// The window is movable by its background, and AppKit treats a non-opaque
    /// view as background — which turned every tab click into a window drag.
    /// Dragging by the empty part of the strip is handled explicitly in
    /// `mouseDown` instead.
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: Layout

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        rebuildLayout()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        rebuildLayout()
    }

    private func rebuildLayout() {
        frames.removeAll()
        guard !items.isEmpty else {
            newButtonRect = NSRect(x: Theme.trafficLightInset, y: 0,
                                   width: newButtonWidth, height: bounds.height)
            return
        }

        let available = bounds.width - Theme.trafficLightInset - newButtonWidth - 8
        let naturalWidths = items.map { item -> CGFloat in
            let width = (item.title as NSString).size(withAttributes: [.font: titleFont]).width
            return min(maxTabWidth, max(minTabWidth, width + 44))
        }
        let naturalTotal = naturalWidths.reduce(0, +)
        let scale = naturalTotal > available && naturalTotal > 0 ? available / naturalTotal : 1

        var x = Theme.trafficLightInset
        for (index, natural) in naturalWidths.enumerated() {
            let width = max(48, natural * scale)
            let rect = NSRect(x: x, y: 0, width: width, height: bounds.height)
            let closeRect = NSRect(x: rect.maxX - closeSize - 8,
                                   y: (bounds.height - closeSize) / 2,
                                   width: closeSize, height: closeSize)
            frames.append(TabFrame(index: index, rect: rect, closeRect: closeRect))
            x = rect.maxX
        }
        newButtonRect = NSRect(x: x + 4, y: 0, width: newButtonWidth, height: bounds.height)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        for frame in frames {
            let item = items[frame.index]
            let isSelected = frame.index == selectedIndex

            if isSelected {
                NSColor(white: 1, alpha: 0.07).setFill()
                frame.rect.fill()
                Theme.accent.withAlphaComponent(0.9).setFill()
                NSRect(x: frame.rect.minX, y: frame.rect.maxY - 2,
                       width: frame.rect.width, height: 2).fill()
            } else if hoveredTab == frame.index {
                NSColor(white: 1, alpha: 0.035).setFill()
                frame.rect.fill()
            }

            // Separator between adjacent unselected tabs.
            if frame.index > 0 && !isSelected && frame.index - 1 != selectedIndex {
                Theme.hairline.setFill()
                NSRect(x: frame.rect.minX, y: 9, width: 1, height: frame.rect.height - 18).fill()
            }

            let showClose = hoveredTab == frame.index || isSelected
            let textRight = showClose ? frame.closeRect.minX - 4 : frame.rect.maxX - 10
            let textRect = NSRect(x: frame.rect.minX + 12, y: 0,
                                  width: max(0, textRight - frame.rect.minX - 12),
                                  height: frame.rect.height)

            var title = item.title
            if item.isDirty { title = "• " + title }

            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingMiddle
            let attributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: isSelected ? Theme.foreground : Theme.dimForeground,
                .paragraphStyle: style,
            ]
            let size = (title as NSString).size(withAttributes: attributes)
            (title as NSString).draw(
                in: NSRect(x: textRect.minX, y: (textRect.height - size.height) / 2,
                           width: textRect.width, height: size.height),
                withAttributes: attributes)

            if showClose { drawClose(in: frame.closeRect, hovered: hoveredClose == frame.index) }
        }

        drawPlus(in: newButtonRect)

        Theme.hairline.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    private func drawClose(in rect: NSRect, hovered: Bool) {
        if hovered {
            NSColor(white: 1, alpha: 0.14).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }
        let path = NSBezierPath()
        let inset = rect.insetBy(dx: 4.5, dy: 4.5)
        path.move(to: NSPoint(x: inset.minX, y: inset.minY))
        path.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
        path.move(to: NSPoint(x: inset.maxX, y: inset.minY))
        path.line(to: NSPoint(x: inset.minX, y: inset.maxY))
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        (hovered ? Theme.foreground : Theme.dimForeground).setStroke()
        path.stroke()
    }

    private func drawPlus(in rect: NSRect) {
        let path = NSBezierPath()
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let arm: CGFloat = 5
        path.move(to: NSPoint(x: center.x - arm, y: center.y))
        path.line(to: NSPoint(x: center.x + arm, y: center.y))
        path.move(to: NSPoint(x: center.x, y: center.y - arm))
        path.line(to: NSPoint(x: center.x, y: center.y + arm))
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        Theme.dimForeground.setStroke()
        path.stroke()
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let tab = frames.first { $0.rect.contains(point) }
        let close = frames.first { $0.closeRect.contains(point) }
        let newHoveredTab = tab?.index
        let newHoveredClose = close?.index
        if newHoveredTab != hoveredTab || newHoveredClose != hoveredClose {
            hoveredTab = newHoveredTab
            hoveredClose = newHoveredClose
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredTab = nil
        hoveredClose = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if newButtonRect.contains(point) { onNew?(); return }

        for frame in frames where frame.rect.contains(point) {
            let closeVisible = hoveredTab == frame.index || frame.index == selectedIndex
            if closeVisible && frame.closeRect.contains(point) {
                onClose?(frame.index)
            } else {
                onSelect?(frame.index)
            }
            return
        }

        // Empty strip acts as titlebar — let the window drag.
        window?.performDrag(with: event)
    }

    /// Middle-click closes, matching browser convention.
    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let frame = frames.first(where: { $0.rect.contains(point) }) {
            onClose?(frame.index)
        }
    }
}
