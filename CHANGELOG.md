# Changelog

## Unreleased

### Polish pass: uniform transparency, redesigned cursor, real QoL features
- Gutter transparency was fixed at a constant alpha while the text panel
  scaled with the slider, so the two visibly diverged as you dragged.
  Gutter now tracks the same slider (`m_alpha + 55`, floored at 90 so it
  never drops below legible), so the whole window moves together.
- Cursor redesigned: was a flat pulsing rectangle, now a soft gradient glow
  behind a slim anti-aliased core beam (`QLinearGradient`, feathered edges).
- Added a real find/replace bar (`FindBar.cpp`) — `Ctrl+F` find, `Ctrl+H`
  replace, wraps around, Replace/Replace All, `Esc` to close.
- Added `Ln X, Col Y` to the status bar.
- Added standard text zoom (`Ctrl+=`/`Ctrl+-`/`Ctrl+0`); glass opacity moved
  to `[`/`]` to make room.
- Unsaved-file indicator changed from `*` to `●`.

### Rendering broke entirely (can't see or type anything), independent of glass
Persisted even after fixing the AppKit window-property conflict below, which
meant that fix wasn't the actual root cause of this one. The real problem:
`Editor` (and its viewport) had `Qt::WA_TranslucentBackground` set on
*themselves*, not just on the top-level `MainWindow`. That attribute is
meant for top-level windows — forcing it onto a child widget pushes Qt down
a much less common per-widget alpha-compositing path, which is a far more
likely explanation for text and the gutter failing to render at all. Removed
it from `Editor`, its viewport, and the central container widget; only
`MainWindow` itself has it now. Also flipped native glass from opt-out to
**opt-in** (`VITRUM_ENABLE_GLASS=1 ./Vitrum`).

### AppKit window-property conflict + ARC build errors
`MacVibrancy.mm` was calling `setOpaque:`/`setBackgroundColor:` directly on
the `NSWindow`, fighting Qt's own `WA_TranslucentBackground` handling of the
same window. Also fixed `-fobjc-arc` not being enabled (the `__bridge` casts
were no-ops without it) and an ARC-disallowed direct cast from `WId` to
`NSView*`.

### Hover bar vanishing instead of staying revealed
Used to rely on `mouseMoveEvent`/`enterEvent`/`leaveEvent` across a widget
that gets raised and re-stacked on top of the editor at runtime — Qt's
hover-event delivery doesn't reliably handle that. Replaced with a `QTimer`
(`MainWindow::pollHover`, every 80ms) that checks `QCursor::pos()` directly.

### Slider toward "solid" instead producing a wash of blur
Native `NSVisualEffectView.alphaValue` and Qt's own tint fill were both
driven by the same slider value and fighting each other. Decoupled: native
blur is now fixed at `alphaValue = 1.0`, slider only controls the Qt tint.

## 0.1.0 — Initial C++/Qt6 rewrite
Ground-up rewrite of the earlier Python/PySide6 prototype in C++ + Qt6
Widgets. Multi-language syntax highlighting, frameless rounded window,
hover-reveal top bar, native macOS vibrancy via Objective-C++, async
chunked file I/O.
