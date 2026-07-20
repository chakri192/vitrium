# Vitrium

A modern, native C++/Qt6 text editor featuring a custom glass aesthetic, uniform bidirectional transparency, and a glowing cursor. Built for speed and visual polish.

## Overview

| Feature | Behavior |
|---|---|
| Native Glass UI | Window, editor, and gutter scale uniformly via an integrated alpha slider |
| Glowing Cursor | Custom-painted anti-aliased cursor beam with a soft gradient glow |
| Auto-hide Menus | Top menu and find/replace bars slide in seamlessly without overlapping active tabs |
| Find & Replace | Full native search with wrap-around, replace-all, and precise match highlighting |
| Dynamic Gutter | Line numbers scale perfectly with text zoom (`Ctrl+=` / `Ctrl+-`) |
| Unsaved Indicator | Native standard `●` dot indicator in the tab bar for dirty files |

---

## Requirements

- macOS
- **C++17** compatible compiler
- **Qt6** (Core, Gui, Widgets)
- **CMake** (3.16+)

---

## Installation

### 1. Clone

```bash
git clone https://github.com/chakri192/vitrium.git
cd vitrium
```

### 2. Build

```bash
mkdir -p build
cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
cmake --build . -j$(nproc)
```

### 3. Run

```bash
# macOS
./Vitrium.app/Contents/MacOS/Vitrium
```

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Ctrl + N` | New Tab |
| `Ctrl + W` | Close Current Tab |
| `Ctrl + Tab` | Next Tab |
| `Ctrl + Shift + Tab` | Previous Tab |
| `Ctrl + F` | Open Find Bar |
| `Ctrl + H` | Open Replace Bar |
| `Ctrl + = / - / 0` | Zoom In / Zoom Out / Reset Zoom |
| `[` / `]` | Decrease / Increase Glass Opacity |

---

## How It Works Internally

- **Transparency Engine:** Uses `Qt::WA_TranslucentBackground` exclusively on the top-level `MainWindow`. Child widgets inherit the palette dynamically, avoiding the heavy per-widget alpha-compositing path.
- **Tab Layout Thrashing Prevention:** The auto-hide top bar is positioned below the tab bar in the layout hierarchy, ensuring the tab targets remain static when the mouse approaches the top of the screen.
- **Gutter Sync:** The custom gutter overrides `paintEvent` to pull visible block metrics directly from the `QTextDocument` layout, ensuring pixel-perfect alignment regardless of font size or word wrap.
- **Targeted Height Animation:** Auto-hide bars drive `setFixedHeight()` directly every frame rather than relying on `maximumHeight`, ensuring the layout precisely tracks the animation target (38px) without overlap.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Gutter background doesn't match editor | Adjust the glass opacity slider; both now sync uniformly to the same alpha value |
| Menu bar covers tabs on hover | Fixed in recent build; ensure you are running the latest commit where layout constraints were updated |
| Files saving without extensions | Automatically appends `.txt` if no extension is provided in the save dialog |
| Text and line numbers drift | Reset zoom (`Ctrl+0`) or rebuild; line metrics now strictly pull from `QTextDocument` margins |

---

## Resource Usage

| Resource | Usage |
|---|---|
| CPU | Minimal — lightweight native event loop via Qt6 |
| RAM | Highly efficient — leverages line-based text buffering |
| Storage | ~15MB compiled binary |

---

## License

MIT


## Contributors

| Contributor | Role |
|---|---|
| chakri192 | Author |
| aider | AI pair programmer |

### AI Tooling

README and code contributions assisted by aider using local LLMs via Ollama:

| Model | Used for |
|---|---|
| qwen2.5-coder:7b | Code suggestions, refactoring |
| llama3.1:8b | Prose, documentation, commit messages |
