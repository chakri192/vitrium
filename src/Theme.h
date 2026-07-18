#pragma once

namespace Theme {
constexpr int kDefaultAlpha = 127;   // true midpoint of 0-255 -- this is what
constexpr int kMinAlpha = 0;         // "slider in the middle" now actually means
constexpr int kMaxAlpha = 255;       // full range: 0 = tint-free (blur only), 255 = solid

constexpr int kHoverPollMs = 80;     // cursor-position poll for the reveal bar

constexpr int kWindowRadius = 20;
constexpr int kBarHeight = 40;
constexpr int kRevealZonePx = 30;
constexpr int kHideDelayMs = 550;
}  // namespace Theme
