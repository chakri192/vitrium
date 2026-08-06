<div align="center">

<img src="docs/icon.png" width="120" alt="Vitrium" />

# Vitrium

**A transparent text editor for macOS.**

Compositor-level blur, native AppKit, and no dependencies.

<p>
  <img alt="Platform" src="https://img.shields.io/badge/macOS-13%2B-1c1c1e?style=flat-square&logo=apple&logoColor=white" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-1c1c1e?style=flat-square&logo=swift&logoColor=F05138" />
  <img alt="Dependencies" src="https://img.shields.io/badge/dependencies-none-1c1c1e?style=flat-square" />
  <img alt="Tests" src="https://img.shields.io/badge/tests-53%20passing-1c1c1e?style=flat-square" />
  <img alt="License" src="https://img.shields.io/badge/license-MIT-1c1c1e?style=flat-square" />
</p>

<br />

<img src="docs/screenshot.png" width="820" alt="Vitrium editing its own source" />

<sub>Vitrium editing its own <code>GlassWindow.swift</code>. The desktop is visible through the window rather than composited behind it.</sub>

</div>

---

## Overview

Vitrium is a tabbed text editor whose window is genuinely transparent: the blur is an `NSVisualEffectView` in `.behindWindow` blending mode, so the compositor samples the actual desktop rather than content the application has drawn. Moving the window across the wallpaper changes the glass accordingly.

There is no Electron, no web view, and no HTML or CSS anywhere in the stack.

## Requirements

macOS 13 or later. Building requires the Xcode Command Line Tools (`xcode-select --install`); full Xcode is not required.

## Installation

```sh
git clone https://github.com/chakri192/vitrium.git
cd vitrium
./Scripts/bundle.sh
open build/Vitrium.app
```

## Features

| Area | Capability |
|---|---|
| **Transparency** | Compositor-level blur, enabled by default, with an adjustable tint ranging from unmodified blur to nearly opaque. The tab strip, gutter, editor, and status bar occupy a single pane |
| **Tabs** | Create, close, close others, close all, and switch by keyboard or pointer. Opening a file into an empty untitled tab reuses that tab |
| **Syntax highlighting** | Python, C and C++, Swift, JavaScript and TypeScript, Shell, YAML, JSON, and Markdown. Detected from the filename, or selected manually from the status bar for unsaved documents |
| **Find and replace** | Case-sensitive and whole-word options, live match count, wraparound, and Replace All recorded as a single undo operation |
| **Editing** | Comment toggle, line duplication, line movement, indent and outdent, automatic indentation, bracket and quote completion, bracket-match highlighting, and go-to-line |
| **Atomic saves** | Each write is made to a sibling temporary file and replaces the target only on completion. An interrupted save leaves the original intact |
| **Background I/O** | File loads and interactive saves execute off the main thread. Closing a modified tab is the sole blocking operation, since the result is required before the tab can close |
| **Drag and drop** | Files dropped anywhere on the window, including the editor body, open as tabs |
| **External change detection** | Prompts to reload when a file is modified on disk, and does not misidentify its own writes as external modifications |
| **Session restore** | Restores open documents, window geometry, zoom level, word wrap, and tint |

## Implementation

### Transparency

Three conditions must hold simultaneously for the effect to work.

**`.behindWindow` blending.** The compositor samples the desktop itself. This is the capability a CSS `backdrop-filter` cannot provide, as that can only blur content the page has already drawn.

**Every view must be non-opaque.** The scroll view, clip view, text view, and gutter all set `drawsBackground = false`. A single opaque view anywhere in the hierarchy renders a solid rectangle through the effect.

**A single tint layer.** One dark wash is applied over the blur, adjustable at runtime. Applying tint per view is what produces the uneven appearance common to layered transparent interfaces.

> A window configured as movable by its background causes AppKit to treat every non-opaque view as draggable chrome. The tab strip and status bar must opt out explicitly, or clicking a tab moves the window instead of switching tabs.

### Syntax highlighting

Each language's rules are compiled into a single alternation regex ordered by precedence: comments and strings first, then keywords, numbers, functions, and types. ICU evaluates alternatives left to right at each position, so the first matching rule claims those characters outright.

That ordering is the central design decision. The alternative — applying rules sequentially and allowing later rules to overwrite earlier ones — cannot satisfy both of the following simultaneously:

- a keyword inside a string is not a keyword
- a quotation mark inside a comment does not open a string

Whichever rule is applied last takes precedence in both directions, so one of the two outcomes is necessarily incorrect. An earlier Qt implementation exhibited this defect: `for` and `with` were highlighted as keywords inside Python docstrings.

Recolouring is incremental. Only the edited lines are reprocessed per keystroke, making typing O(line) rather than O(document). Block comments are the exception, since they span arbitrary distances: an edit touching `/*` or `*/` widens the recolour window to the end of the file, and the scan restarts from the last `*/` above the edit — the nearest position guaranteed to lie outside a comment.

### Tab isolation

**Each tab owns a complete `EditorPane`** rather than sharing one text view and exchanging its storage. This consumes marginally more memory, and in exchange scroll position, selection, and undo history survive a tab switch without any bookkeeping.

**Each tab owns its own `UndoManager`.** AppKit's default is the window's undo manager, which every tab would share — allowing an undo in one tab to reverse an edit made in another.

## Keyboard reference

| Shortcut | Action |
|---|---|
| <kbd>⌘O</kbd> <kbd>⌘S</kbd> <kbd>⌘⇧S</kbd> | Open · Save · Save As |
| <kbd>⌘⇧O</kbd> | Recent files |
| <kbd>⌘T</kbd> <kbd>⌘W</kbd> | New tab · Close tab |
| <kbd>⌘⌥W</kbd> <kbd>⌘⌥⇧W</kbd> | Close others · Close all |
| <kbd>⌘⇧]</kbd> <kbd>⌘⇧[</kbd> · <kbd>⌃⇥</kbd> <kbd>⌃⇧⇥</kbd> | Next · previous tab |
| <kbd>⌘F</kbd> <kbd>⌘⌥F</kbd> <kbd>⌘G</kbd> <kbd>⌘⇧G</kbd> | Find · Find and Replace · Next · Previous |
| <kbd>⌘L</kbd> | Go to line |
| <kbd>⌘/</kbd> | Toggle comment |
| <kbd>⌘D</kbd> | Duplicate line |
| <kbd>⌥↑</kbd> <kbd>⌥↓</kbd> | Move line up · down |
| <kbd>⌘]</kbd> <kbd>⌘[</kbd> | Indent · outdent |
| <kbd>⌥Z</kbd> | Toggle word wrap |
| <kbd>⌘=</kbd> <kbd>⌘-</kbd> <kbd>⌘0</kbd> | Zoom in · out · reset |
| <kbd>⌘⌥[</kbd> <kbd>⌘⌥]</kbd> | Increase · decrease transparency |
| <kbd>⌘⇧R</kbd> | Reveal in Finder |

<kbd>⌃⇥</kbd> is bound to the physical Control key, consistent with Safari, Xcode, and Terminal.

## Project structure

`Sources/VitriumKit` contains the implementation. `Sources/Vitrium` is a three-line executable and `Sources/VitriumTests` the test runner. The separation exists so that tests can reach the implementation through `@testable import`.

| Type | Responsibility |
|---|---|
| `GlassWindow` | Transparent window, blur, tint layer |
| `MainWindowController` | Window chrome, tab list, file operations, find |
| `Document` | Per-tab state: URL, modification status, load and save, external change tracking |
| `EditorPane` | Scroll view, text view, gutter, and highlighter — one per tab |
| `EditorTextView` | Automatic indentation, bracket completion, line operations, per-tab undo, file drops |
| `SyntaxHighlighter` | Incremental colouring over `NSTextStorage` |
| `Language` | Detection, keywords, comment syntax, rule precedence |
| `LineIndex` · `LineNumberRuler` | Line offsets and the gutter |
| `TabBarView` · `FindBarView` · `StatusBarView` | Interface components |
| `FileIO` · `Preferences` | Atomic saves, asynchronous loads, persisted settings |

## Testing

```sh
./Scripts/test.sh
```

53 tests covering highlighting precedence, agreement between incremental and full recolouring, line numbering, line-editing operations, search, modification tracking, and both save paths including the case where the document is edited during an asynchronous save.

`swift test` is deliberately not used. XCTest ships only with Xcode, and the Command Line Tools distribution of swift-testing lacks its Foundation overlay. The suite is a plain executable and therefore runs wherever Swift does — the same requirement the application itself is held to.

## Application icon

The icon is generated in code rather than exported from a design tool. `Scripts/make-icons.swift` renders it with CoreGraphics and `Scripts/make-icns.sh` assembles the `.icns`. Every size in the iconset is rendered natively rather than downscaled from a single master, which is what keeps the caret legible at 16 pixels.

```sh
./Scripts/make-icns.sh caret-mono
```

Six designs are available: `caret-mono`, `caret-accent`, `caret-green`, `monogram`, `window`, and `panes`.

## Limitations

No multiple cursors and no split view. No language server integration, autocompletion, or semantic analysis — highlighting is lexical. No plugin system. No printing, Save All, encoding selection, or regular-expression search. macOS only: the transparency, window conventions, and entire interface layer are AppKit.

## License

MIT © V Chakradhar

## Contributors

| | |
|---|---|
| [chakri192](https://github.com/chakri192) | Author |
| [aider](https://github.com/Aider-AI/aider) | AI pair programmer |
