#pragma once

class QWindow;

// Real native macOS blur-behind-window via NSVisualEffectView, reached
// through QWindow::winId() (which is the NSView* on macOS). This header has
// no Objective-C in it so it's includable from plain C++ translation units;
// the .mm file is only compiled when APPLE is set in CMakeLists.txt.
namespace MacVibrancy {

// Returns an opaque handle to the installed NSVisualEffectView (really an
// NSVisualEffectView*, but kept as void* so this header stays framework-free),
// or nullptr if unavailable. `material` is one of "hud", "sidebar", "under_window".
void *installGlass(QWindow *window, double cornerRadius, const char *material);

void setGlassAlpha(void *effectView, double alpha0to1);
void setGlassCornerRadius(void *effectView, double radius);

}  // namespace MacVibrancy
