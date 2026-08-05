import AppKit

/// Every colour and metric the chrome draws with, in one place.
///
/// The palette is the phosphor-green / amber / violet terminal scheme the Qt
/// build used, kept as-is — it was the one part of the old UI worth carrying
/// over verbatim.
enum Theme {

    // MARK: Syntax palette

    static let keyword  = NSColor(srgbRed: 185/255, green: 156/255, blue: 255/255, alpha: 1)  // soft violet
    static let string   = NSColor(srgbRed: 140/255, green: 255/255, blue: 160/255, alpha: 1)  // phosphor green
    static let comment  = NSColor(srgbRed:  90/255, green: 107/255, blue:  98/255, alpha: 1)  // muted moss
    static let number   = NSColor(srgbRed: 255/255, green: 176/255, blue: 103/255, alpha: 1)  // warm amber
    static let function = NSColor(srgbRed: 110/255, green: 231/255, blue: 183/255, alpha: 1)  // teal-green
    static let type     = NSColor(srgbRed: 255/255, green: 225/255, blue:  86/255, alpha: 1)  // neon yellow

    // MARK: Chrome

    static let foreground     = NSColor(srgbRed: 0.90, green: 0.93, blue: 0.91, alpha: 1)
    static let dimForeground  = NSColor(srgbRed: 0.90, green: 0.93, blue: 0.91, alpha: 0.45)
    static let accent         = function
    static let gutterText     = NSColor(srgbRed: 0.90, green: 0.93, blue: 0.91, alpha: 0.28)
    static let gutterCurrent  = NSColor(srgbRed: 0.90, green: 0.93, blue: 0.91, alpha: 0.85)
    static let currentLine    = NSColor(white: 1, alpha: 0.045)
    static let selection      = NSColor(srgbRed: 110/255, green: 231/255, blue: 183/255, alpha: 0.25)
    static let cursor         = function
    static let hairline       = NSColor(white: 1, alpha: 0.09)
    static let bracketMatch   = NSColor(srgbRed: 255/255, green: 225/255, blue: 86/255, alpha: 0.28)
    static let findHighlight  = NSColor(srgbRed: 255/255, green: 176/255, blue: 103/255, alpha: 0.30)
    static let findCurrent    = NSColor(srgbRed: 255/255, green: 176/255, blue: 103/255, alpha: 0.60)

    // MARK: Tint

    /// The dark wash layered over the compositor blur. 0 = pure blur, 1 = solid.
    /// The default sits low deliberately — this is a *transparent* editor, and
    /// anything above ~0.5 stops reading as glass.
    static let defaultTint: CGFloat = 0.28
    static let minTint: CGFloat = 0.0
    static let maxTint: CGFloat = 0.92
    static let tintStep: CGFloat = 0.04

    // MARK: Metrics

    static let cornerRadius: CGFloat = 14
    static let tabBarHeight: CGFloat = 34
    static let statusBarHeight: CGFloat = 22
    static let findBarHeight: CGFloat = 38
    static let gutterWidth: CGFloat = 52
    static let textInset = NSSize(width: 12, height: 10)

    /// Leaves room for the traffic lights so the tab strip can live in the
    /// titlebar without colliding with them.
    static let trafficLightInset: CGFloat = 78

    static let maxRecentFiles = 10

    // MARK: Type

    static let defaultFontSize: CGFloat = 13
    static let minFontSize: CGFloat = 8
    static let maxFontSize: CGFloat = 36

    static func editorFont(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func uiFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
}
