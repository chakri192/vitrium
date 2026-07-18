# Vitrum

A native, lightweight desktop text editor with a translucent "glass" look —
built in C++ and Qt6 Widgets, no Electron, no WebView, no HTML/CSS rendering
anywhere in the stack.

## Why

Editors that go for a frosted-glass aesthetic are almost always Electron
apps with a web-rendered UI sitting on top. Vitrum is native end to end:
`QPlainTextEdit` + `QSyntaxHighlighter` do the actual text editing, and on
macOS the blur itself is a real `NSVisualEffectView` reached directly
through Objective-C++ — not a CSS `backdrop-filter` fake.

## Features

- Multi-language syntax highlighting (`.py`, `.c/.h/.cpp/.hpp`, `.json`,
  `.md`, `.txt`, falls back to plain) with a phosphor-green/amber/violet
  palette.
- Native macOS blur (`NSVisualEffectView`, blend mode `BehindWindow`) —
  opt-in via `VITRUM_ENABLE_GLASS=1`; falls back to a translucent Qt palette
  tint everywhere else. Opacity slider (0–255) drives the whole window
  uniformly, gutter included.
- Frameless window with a real rounded per-pixel mask — no OS title bar.
- Hover-reveal top bar (Open / Save / Save As, opacity slider, traffic-light
  controls) that's also the window's drag handle.
- Find/Replace (`Ctrl+F` / `Ctrl+H`) with wraparound and Replace All.
- Standard text zoom (`Ctrl+=` / `Ctrl+-` / `Ctrl+0`).
- Gutter with a current-line accent tick; `Ln X, Col Y` in the status bar.
- Cursor rendered as a soft gradient glow behind a slim core beam, animated
  only while focused and editable.
- Async chunked file load/save (`QThread`, 512KB chunks) — large files never
  block the UI thread.

## Build

Requires Qt6 and CMake.

```
brew install qt cmake
git clone https://github.com/chakri192/VitrumCpp.git
cd VitrumCpp
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
open build/Vitrum.app
```

Open a file directly:
```
./build/Vitrum.app/Contents/MacOS/Vitrum path/to/file.py
```

Enable native macOS glass:
```
VITRUM_ENABLE_GLASS=1 ./build/Vitrum.app/Contents/MacOS/Vitrum
```

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌘O` | Open |
| `⌘S` | Save |
| `⌘⇧S` | Save As |
| `⌘F` | Find |
| `⌘H` | Find and Replace |
| `⌘G` | Find Next |
| `⌘=` / `⌘-` | Zoom in / out |
| `⌘0` | Reset zoom |
| `[` / `]` | Decrease / increase glass opacity |
| `⌘Q` | Quit |

## Architecture

```
src/
  main.cpp          entry point
  MainWindow.*       window chrome, file I/O orchestration, hover-reveal bar polling
  Editor.*           QPlainTextEdit subclass: gutter, cursor glow, glass palette
  Highlighter.*      QSyntaxHighlighter, per-language rule sets
  AutoHideBar.*       hover-reveal top bar (traffic dots, open/save, opacity slider)
  FindBar.*          find/replace overlay
  FileWorker.*       QThread-based chunked async load/save
  MacVibrancy.mm      Objective-C++, macOS-only, real NSVisualEffectView blur
```

`MacVibrancy.mm` is gated behind `if(APPLE)` in `CMakeLists.txt` and only
compiles on macOS; every other file is plain cross-platform Qt6.

See [CHANGELOG.md](CHANGELOG.md) for the fix/feature history.

## Packaging

```
cmake --build build            # already produces a .app bundle
macdeployqt build/Vitrum.app   # bundles Qt frameworks for distribution
```

## License

MIT
