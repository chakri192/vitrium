#pragma once

namespace Theme {
constexpr int kDefaultAlpha = 127;   // true midpoint of 0-255 -- this is what
constexpr int kMinAlpha = 0;         // "slider in the middle" now actually means
constexpr int kMaxAlpha = 255;       // full range: 0 = tint-free (blur only), 255 = solid

constexpr int kHoverPollMs = 80;     // cursor-position poll for the reveal bar

constexpr int kWindowRadius = 14;
constexpr int kBarHeight = 38;
constexpr int kTabHeight = 32;

// The hover-reveal bar never fully collapses to 0px -- it keeps this much
// height as a dedicated hit zone (shown as a subtle hairline via its
// existing border-bottom style) physically separate from the tab bar below
// it. kRevealZonePx matches it exactly, so hovering to reveal the bar and
// clicking a tab can never be the same gesture.
constexpr int kCollapsedBarHeight = 6;
constexpr int kRevealZonePx = kCollapsedBarHeight;
constexpr int kHideDelayMs = 550;

constexpr int kMaxRecentFiles = 8;
}  // namespace Theme
