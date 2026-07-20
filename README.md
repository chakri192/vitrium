# Vitrium

A native, lightweight desktop text editor with a translucent glass look, built in C++ and Qt6 for macOS. No Electron, no WebView, no HTML/CSS anywhere in the stack — on macOS the blur is a real `NSVisualEffectView` reached through Objective-C++, not a CSS `backdrop-filter` fake.

---

## Features

- **Multi-document tabs** — new, close, close others/all, switch by keyboard or click. Opening a file into an empty untitled tab reuses it instead of piling up tabs.
- **Syntax highlighting** — Python, C/C++, JavaScript/TypeScript, Shell, YAML, JSON, Markdown, plain text.
- **Find & Replace** — case-sensitive and whole-word toggles, live match count, wraparound, Replace All as a single undo step.
- **Code editing QoL** — comment toggle, duplicate line, move line up/down, indent/outdent selection, auto-indent, bracket/quote auto-close, bracket-match highlighting.
- **Atomic saves** — `QSaveFile` writes to a sibling temp file and only replaces the real target once every byte is confirmed flushed, so a crash or power loss mid-write can't corrupt an existing file.
- **Async everything** — chunked load/save on a background thread, multiple files open through a queue so opening several at once can't splice one file's content into another's document.
- **External change detection** — prompts to reload if a file changes on disk from outside the app; ignores the notification its own save triggers.
- **Native macOS glass** — real compositor-level blur, opt-in.
- **Session restore** — reopens what was open last time; remembers window geometry, zoom level, and glass opacity.

---

## Verified behavior

| Scenario | Behavior |
|---|---|
| Opening a file into a fresh empty tab | Reuses that tab instead of creating a new one |
| Opening several files at once (CLI args or drag-drop) | Queued and loaded one at a time, each written straight into its own tab's document — never through whatever tab happens to be on screen |
| App killed mid-save | Original file untouched — `QSaveFile` only replaces it after every byte is confirmed flushed |
| File edited by another program while open | Prompted to reload; declined if the tab has unsaved local edits instead of silently clobbering them |
| Closing a tab / quitting with unsaved changes | Blocking Save / Discard / Cancel confirmation, one dialog per dirty tab |
| Saving a new file without typing an extension | Defaults to the extension matching the tab's detected language (`.py`, `.js`, `.sh`, ...), not left extensionless |
| Multi-line comment toggle, indent/outdent, duplicate/move line | Exact output match, round-trips cleanly, verified against the compiled binary, not just compiled |
| Glass opacity slider | Editor, gutter, tab strip, and top bar all track it together, uniformly |

---

## Requirements

- macOS (native glass and window-control conventions are macOS-specific; the Qt-only rendering path also builds on Linux/Windows)
- Qt6 (Widgets)
- CMake 3.16+
- C++20 compiler

---

## Installation

### 1. Install dependencies

```zsh
brew install qt cmake
```

### 2. Clone and build

```zsh
git clone https://github.com/chakri192/vitrium.git
cd vitrium
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

### 3. Run

```zsh
open build/Vitrum.app
```

Or open a file (or several) directly:

```zsh
./build/Vitrum.app/Contents/MacOS/Vitrum path/to/file.py path/to/other.js
```

---

## Usage

Enable native macOS glass (off by default):

```zsh
VITRUM_ENABLE_GLASS=1 ./build/Vitrum.app/Contents/MacOS/Vitrum
```

Package as a distributable bundle:

```zsh
macdeployqt build/Vitrum.app
```

---

## Keyboard shortcuts

| Key | Action |
|---|---|
| `⌘O` / `⌘S` / `⌘⇧S` | Open / Save / Save As |
| `⌘T` / `⌘W` | New tab / Close tab |
| `⌘⌥W` / `⌘⌥⇧W` | Close other tabs / Close all tabs |
| `⌘⇧]` `⌘⇧[`, `⌃⇥` `⌃⇧⇥` | Next / previous tab |
| `⌘F` / `⌘⌥F` / `⌘G` | Find / Find & Replace / Find Next |
| `⌘L` | Go to line |
| `⌘/` | Toggle comment |
| `⌘D` | Duplicate line |
| `⌥↑` / `⌥↓` | Move line up / down |
| Tab / Shift+Tab (on selection) | Indent / outdent |
| `⌥Z` | Toggle word wrap |
| `⌘=` / `⌘-` / `⌘0` | Zoom in / out / reset |
| `[` / `]` | Decrease / increase glass opacity |
| `⌘⇧O` | Open recent |
| `⌘Q` | Quit |

---

## Architecture

**~10 files, one class per concern**

- `MainWindow` — window chrome, tab/document management, file I/O orchestration, settings persistence
- `Editor` — `QPlainTextEdit` subclass: gutter, cursor rendering, glass palette, line-level editing operations
- `Highlighter` — `QSyntaxHighlighter`, per-language rules, comment prefixes, default save extensions
- `AutoHideBar` / `TabBar` / `FindBar` — the three UI chrome pieces
- `FileWorker` — `QThread`-based chunked async load/save
- `MacVibrancy` — macOS-only native blur (Objective-C++)

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Window looks flat/opaque instead of glassy | Native glass is opt-in — run with `VITRUM_ENABLE_GLASS=1` |
| Saved file has no extension | Fixed in current version — save dialog defaults to the extension matching the tab's language; type your own to override |
| `Ctrl+Tab` doesn't switch tabs | Qt maps the `"Ctrl"` string to the physical Cmd key on macOS — this build binds tab-switching to the physical Control key specifically (`Qt::MetaModifier`), matching Safari/Xcode/Terminal convention |
| Build fails on `MacVibrancy.mm` | That file only compiles on macOS (`if(APPLE)` in `CMakeLists.txt`) — if you're seeing it fail on macOS itself, check `-fobjc-arc` is being passed (set in `CMakeLists.txt`) |
| Reload prompt appears on every save | `QFileSystemWatcher` should suppress its own writes automatically — if this happens, the file's path likely changed case/symlink between save and watch |

---

## What it doesn't do

- No multi-cursor editing or split view
- No LSP/autocomplete — syntax highlighting only, no semantic analysis
- No plugin system
- Native glass is macOS-only; other platforms get a translucent Qt palette tint instead

---

## License

MIT

## Contributors

| Contributor | Role |
|-------------|------|
| [chakri192](https://github.com/chakri192) | Author |
| [aider](https://github.com/Aider-AI/aider) | AI pair programmer |

### AI tooling

README and code contributions assisted by [aider](https://github.com/Aider-AI/aider) using local LLMs via [Ollama](https://ollama.com):

| Model | Used for |
|-------|----------|
| `qwen2.5-coder:7b` | Code suggestions, refactoring |
| `llama3.1:8b` | Prose, documentation, commit messages |

