# minimal-notifications

Two lightweight macOS clipboard-change indicators, built as an exploration of notification design that stays out of the way entirely — no banners, no Notification Center clutter, no click required to dismiss.

---

## Overview

Most clipboard managers and copy confirmations interrupt you with a visible banner. These two tools take the opposite approach: **audio-whisper** gives you a quiet sound and nothing else, **transient-bezel** gives you a flash of the native macOS HUD style and nothing else. Pick one, or run both.

---

## Behavior

| Scenario | Behavior |
|---|---|
| Text copied to clipboard | Sound plays / bezel flashes within ~0.4s |
| Image or file copied | Detected via pasteboard change count — sound/bezel still fires, bezel shows generic "Copied" |
| Nothing copied yet (script just started) | No sound/bezel on startup — only fires on the *next* change |
| Clipboard unchanged | Silent — no repeated triggers on every poll |
| Fullscreen app active (bezel only) | Still renders above it — uses `.screenSaver` window level |
| Menu bar auto-hide enabled (bezel only) | Bezel position is fixed relative to actual menu bar thickness, not `visibleFrame`, so it doesn't jump when the menu bar auto-hides |

---

## Requirements

- macOS
- **audio-whisper**: no dependencies — pure Bash + `afplay` (built into macOS)
- **transient-bezel**: Xcode Command Line Tools (`xcode-select --install` if not already present) — no full Xcode required

---

## Installation

### 1. Clone

```bash
git clone https://github.com/chakri192/minimal-notifications.git
cd minimal-notifications
```

### 2. Audio Whisper

```bash
chmod +x audio-whisper/clipboard-audio-whisper.sh
./audio-whisper/clipboard-audio-whisper.sh &
```

### 3. Transient Bezel

```bash
cd transient-bezel
swiftc main.swift -o clipboard-bezel -O
./clipboard-bezel &
```

---

## Auto-start at login

Both ship with a `launchd` agent so they survive reboots without a login item.

### Audio Whisper

```bash
mkdir -p ~/scripts
cp audio-whisper/clipboard-audio-whisper.sh ~/scripts/
cp audio-whisper/com.user.clipboard-audio-whisper.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.clipboard-audio-whisper.plist
```

### Transient Bezel

```bash
mkdir -p ~/apps/clipboard-bezel
cp transient-bezel/clipboard-bezel ~/apps/clipboard-bezel/
cat > ~/Library/LaunchAgents/com.user.clipboard-bezel.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.clipboard-bezel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/YOUR_USERNAME/apps/clipboard-bezel/clipboard-bezel</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/clipboard-bezel.err</string>
</dict>
</plist>
EOF
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.clipboard-bezel.plist
```

---

## Configuration

### Audio Whisper — `audio-whisper/clipboard-audio-whisper.sh`

| Variable | Default | Description |
|---|---|---|
| `SOUND` | `Morse.aiff` | Any file under `/System/Library/Sounds/` — `Pop`, `Ping`, `Purr`, `Tink` also work well |
| `VOLUME` | `0.15` | `0.0` (silent) to `1.0` (full) |
| `POLL_INTERVAL` | `0.4` | Seconds between clipboard checks |

### Transient Bezel — `transient-bezel/main.swift`

| Constant | Default | Description |
|---|---|---|
| `bezelWidth` / `bezelHeight` | `260` / `56` | Size of the HUD |
| `marginFromCorner` | `16` | Distance from the screen's top-right corner |
| `cornerRadius` | `14` | Corner rounding |
| `displayDuration` | `1.0` | Seconds fully visible before fading |
| `fadeDuration` | `0.18` | Fade in/out speed |
| `pollInterval` | `0.35` | Seconds between pasteboard checks |
| `previewMaxLength` | `40` | Max characters of copied text shown |

---

## How it works

**Audio Whisper**
1. Polls `pbpaste` on a loop and hashes the output with `md5`
2. When the hash changes, plays the configured sound via `afplay -v` asynchronously so the loop never blocks

**Transient Bezel**
1. Polls `NSPasteboard.general.changeCount` on a timer (there's no push-based clipboard-change API on macOS, so both tools poll)
2. On change, positions an `NSPanel` in the top-right corner, offset below the menu bar using `NSStatusBar.system.thickness` rather than `visibleFrame` (which collapses to the full screen height when menu bar auto-hide is on)
3. Renders an `NSVisualEffectView` with `.hudWindow` material — the same blur material macOS uses for its own volume/brightness HUD — then fades in, holds, and fades out

---

## Troubleshooting

| Problem | Fix |
|---|---|
| No sound plays | Check `VOLUME` isn't `0`, and confirm the file exists: `ls /System/Library/Sounds/` |
| Bezel doesn't appear at all | Confirm the build succeeded: `swiftc main.swift -o clipboard-bezel -O && echo OK`. A stale binary from an earlier build is the most common cause |
| Bezel overlaps the menu bar | Increase the `+ 10` offset added to `menuBarHeight` in `main.swift` |
| launchd agent won't load | `launchctl bootstrap` fails silently if the same label is already loaded — run `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/<plist>` first, then bootstrap again |
| Multiple instances running | `pgrep -fl clipboard-bezel` / `pgrep -fl clipboard-audio-whisper` to check, `pkill -f <name>` to stop |

---

## Stopping

```bash
pkill -f clipboard-audio-whisper
pkill -f clipboard-bezel
```

Or, if installed via launchd:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.clipboard-audio-whisper.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.clipboard-bezel.plist
```

---

## License

MIT

## Author

Created by [chakri192](https://github.com/chakri192)

## Contributors

| Contributor | Role |
|---|---|
| [chakri192](https://github.com/chakri192) | Author |
| Claude (Anthropic) | AI pair programmer |
