# Vitrium

A transparent text editor for macOS, written in Swift and AppKit. No Electron, no WebView, no HTML/CSS anywhere in the stack — the blur is a real `NSVisualEffectView` sampling what is actually behind the window, not a `backdrop-filter` approximation.

<div align="center">
  <img src="docs/screenshot.png" alt="Vitrium" width="700" />
</div>

---

## Features

- **Glass, on by default** — compositor-level blur with an adjustable tint, from a bare blur through to nearly solid. The tab strip, gutter, editor and status bar all sit on the same pane of glass.
- **Multi-document tabs** — new, close, close others/all, switch by keyboard or click. Opening a file into an empty untitled tab reuses it instead of piling up tabs.
- **Syntax highlighting** — Python, C/C++, Swift, JavaScript/TypeScript, Shell, YAML, JSON, Markdown.
- **Find & Replace** — case-sensitive and whole-word toggles, live match count, wraparound, Replace All as a single undo step.
- **Code editing** — comment toggle, duplicate line, move line up/down, indent/outdent, auto-indent, bracket/quote auto-close, bracket-match highlighting, go to line.
- **Atomic saves** — every write lands in a sibling temp file and only replaces the target once complete, so a crash mid-save leaves the original intact rather than truncated.
- **External change detection** — prompts to reload when a file changes on disk underneath you, and never mistakes your own save for someone else's edit.
- **Session restore** — reopens what was open last time, and remembers window geometry, zoom level, word wrap and glass tint.

---

## How it renders

The three details that make the transparency real rather than faked:

| Piece | What it does |
|---|---|
| `NSVisualEffectView`, `.behindWindow` blending | The compositor samples the actual desktop behind the window. Moving the window over different wallpaper changes what you see through it. |
| Every view non-opaque | The scroll view, clip view, text view and gutter all have `drawsBackground = false`. One opaque view anywhere in the chain punches a solid rectangle through the glass. |
| A single tint layer | One dark wash over the blur, adjustable with `⌘⌥[` / `⌘⌥]`. Tinting each view separately is what makes glass UIs look patchy. |

One consequence worth knowing: a window that is movable by its background makes AppKit treat every non-opaque view as draggable chrome. The tab strip has to opt out of that explicitly, or clicking a tab drags the window instead of switching tabs.

---

## Highlighting

Each language's rules compile into **one alternation regex, in precedence order** — comments and strings first, then keywords, numbers, functions and types. ICU tries alternatives left-to-right at each position, so the first rule that matches claims those characters outright.

That ordering is the whole design. The obvious alternative — apply rules in sequence and let later ones overwrite earlier ones — cannot express "a keyword inside a string is not a keyword" and "a quote inside a comment does not open a string" at the same time. Whichever of the two you apply last wins in *both* directions, and one of them is always wrong.

Only the edited lines are recoloured on each keystroke, so typing is O(line) rather than O(document). Block comments are the exception, since they can span any distance: the recolour window widens to the end of the file whenever an edit touches a `/*` or `*/`, and the scan restarts from the last `*/` above the edit — the nearest point guaranteed to be outside a comment.

---

## Requirements

- macOS 13 or later
- Swift 6 toolchain — **Xcode is not required**, Command Line Tools is enough (`xcode-select --install`)

---

## Build

```zsh
git clone https://github.com/chakri192/vitrium.git
cd vitrium
./Scripts/bundle.sh
```

That builds the app and assembles `build/Vitrium.app`. Then:

```zsh
open build/Vitrium.app
```

Or open files directly:

```zsh
./build/Vitrium.app/Contents/MacOS/Vitrium file.py other.swift
```

---

## Tests

```zsh
./Scripts/test.sh
```

43 tests covering highlighting precedence, incremental-vs-full colouring agreement, the line-editing operations, search, dirty tracking and atomic saves.

The suite is an ordinary executable rather than `swift test`, deliberately: XCTest ships only with Xcode, and the Command Line Tools' copy of swift-testing is missing its Foundation overlay. A plain executable runs anywhere Swift does, which is the same bar the app itself is held to.

---

## Keyboard shortcuts

| Key | Action |
|---|---|
| `⌘O` / `⌘S` / `⌘⇧S` | Open / Save / Save As |
| `⌘T` / `⌘W` | New tab / Close tab |
| `⌘⌥W` / `⌘⌥⇧W` | Close other tabs / Close all tabs |
| `⌘⇧]` `⌘⇧[`, `⌃⇥` `⌃⇧⇥` | Next / previous tab |
| `⌘F` / `⌘⌥F` / `⌘G` / `⌘⇧G` | Find / Find & Replace / Find Next / Find Previous |
| `⌘L` | Go to line |
| `⌘/` | Toggle comment |
| `⌘D` | Duplicate line |
| `⌥↑` / `⌥↓` | Move line up / down |
| `⌘]` / `⌘[` | Indent / outdent |
| `⌥Z` | Toggle word wrap |
| `⌘=` / `⌘-` / `⌘0` | Zoom in / out / reset |
| `⌘⌥[` / `⌘⌥]` | More / less transparent |
| `⌘⇧R` | Reveal in Finder |
| `⌘Q` | Quit |

`⌃⇥` is bound to the *physical* Control key, matching Safari, Xcode and Terminal.

---

## Architecture

`Sources/VitriumKit` holds everything; `Sources/Vitrium` is a three-line executable and `Sources/VitriumTests` is the test runner. The split exists so the tests can reach the real code through `@testable import`.

| File | Responsibility |
|---|---|
| `GlassWindow` | Transparent window, blur, tint layer |
| `MainWindowController` | Window chrome, tab list, file operations, find |
| `Document` | One tab: URL, dirty state, load/save, external-change tracking |
| `EditorPane` | Scroll view + text view + gutter + highlighter, one per tab |
| `EditorTextView` | Editing behaviour: auto-indent, auto-close, line operations, per-tab undo |
| `SyntaxHighlighter` | Incremental colouring over `NSTextStorage` |
| `Language` | Detection, keywords, comment syntax, rule precedence |
| `LineNumberRuler` | The gutter, with a cached line index |
| `TabBarView` / `FindBarView` / `StatusBarView` | The three chrome pieces |
| `FileIO` / `Preferences` | Atomic saves, async loads, persisted settings |

Each tab owns a complete `EditorPane` rather than sharing one text view. That costs a little more memory than swapping text storage around, but scroll position, selection and the undo stack survive a tab switch with no bookkeeping at all. Each tab also gets its own `UndoManager` — the AppKit default is the *window's*, which every tab would share, so undoing in one tab could walk back an edit made in another.

---

## What it doesn't do

- No multi-cursor editing or split view
- No LSP, autocomplete or semantic analysis — highlighting is lexical
- No plugin system
- macOS only. The glass, the window conventions and the whole UI layer are AppKit.

---

## License

MIT

## Contributors

| Contributor | Role |
|-------------|------|
| [chakri192](https://github.com/chakri192) | Author |

The Qt/C++ version this replaced was written with [aider](https://github.com/Aider-AI/aider) driving local models via [Ollama](https://ollama.com). The Swift rewrite was done with Claude Code.
