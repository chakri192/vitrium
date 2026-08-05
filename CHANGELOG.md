# Changelog

## 2.0.0 — Rewritten in Swift + AppKit

Complete rebuild. The Qt6/C++ implementation is gone; Vitrium is now a native
AppKit app with no third-party dependencies. Feature parity with 1.x, plus
Swift syntax highlighting, and several classes of bug that the old design made
possible are now structurally impossible.

### Stack
- Swift 6 + AppKit, built with SwiftPM. **Xcode is no longer required** —
  Command Line Tools is enough. No Qt, no CMake, no Objective-C++ shim.
- `./Scripts/bundle.sh` builds and assembles `Vitrium.app`; `./Scripts/test.sh`
  runs the suite.
- 53 tests, up from none.

### Highlighting rewritten around precedence
Rules used to be applied in sequence, each overwriting the last. That scheme
cannot express "a keyword inside a string is not a keyword" and "a quote inside
a comment does not open a string" at the same time — whichever rule you apply
last wins in both directions, and one of them is always wrong. Symptom in 1.x:
`for` and `with` rendered bold violet inside Python docstrings.

Now each language compiles to one alternation regex in precedence order, so the
first rule matching at a position claims those characters outright. Also fixed
along the way:
- Single-line string rules no longer match across newlines, so one unclosed
  quote can't colour the rest of the file.
- A `/*` inside a line comment no longer opens a block comment.
- JSON keys and string values are distinguished.
- Recolouring after an edit is asserted to match a full rehighlight.

### Bugs fixed that were inherent to the old structure
- **Undo crossed tabs.** `NSTextView` defaults to the *window's* undo manager,
  which every tab shares. Each tab now owns its own.
- **Tab clicks dragged the window.** A window movable by its background makes
  AppKit treat every non-opaque view as draggable chrome; the tab strip now
  opts out explicitly.
- **Find highlights stranded on the tab you left**, and were wiped wholesale by
  bracket matching. Both now track their own ranges and clear against the view
  they were applied to.
- **A tab stayed dirty after undoing back to the saved state.** Dirty state is
  now a comparison against a fingerprint of the last saved text, not a
  one-way flag.
- **Escape didn't close the find bar.** A field editor binds Escape to
  `complete:`, not `cancelOperation:`; both are handled now.

### Restored and added after the first pass
- Files dropped on the **editor body** open as tabs. Registering the window for
  file drags was not enough: `NSTextView` is a drag destination itself and sits
  deeper in the hierarchy, so it won and inserted the path as text.
- **`⌘⇧O`** posts the recent-files list, replacing the shortcut 1.x documented.
  A submenu cannot carry a useful key equivalent, so it opens as a popup.
- **Interactive saves run off the main thread.** Closing a dirty tab still
  blocks, which is correct — the tab cannot go away until the bytes are down.
  An async write works from a snapshot taken when it started, so text typed
  while it is in flight correctly leaves the tab dirty.
- **The language can be set by hand** from the status bar. An untitled tab has
  no extension to detect from, so nothing was highlighted until it was saved.

### Other changes
- Glass is on by default and adjustable with `⌘⌥[` / `⌘⌥]`, replacing the
  `VITRUM_ENABLE_GLASS=1` opt-in and the `[` / `]` bindings that collided with
  typing brackets.
- Bundle identifier and app name settled on **Vitrium** throughout — 1.x built
  a target called `Vitrum`, so this resets saved preferences once.
- Files are read in one pass rather than through a chunked worker queue; the
  queue existed to stop concurrent loads corrupting each other, and per-tab
  documents remove that possibility instead.
- External-change detection checks on app activation rather than watching file
  descriptors — that is when the user can act on the answer, and it can't
  misfire on the app's own writes.

---

## 1.x — Qt6 / C++

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
