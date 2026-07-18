#include "MacVibrancy.h"

#import <Cocoa/Cocoa.h>
#include <QWindow>

namespace MacVibrancy {

void *installGlass(QWindow *window, double cornerRadius, const char *materialName) {
    if (!window) return nullptr;

    NSView *nsView = (__bridge NSView *)reinterpret_cast<void *>(window->winId());
    if (!nsView) return nullptr;
    NSWindow *nsWindow = [nsView window];
    if (!nsWindow) return nullptr;

    NSVisualEffectMaterial material = NSVisualEffectMaterialHUDWindow;
    const NSString *name = [NSString stringWithUTF8String:materialName];
    if ([name isEqualToString:@"sidebar"]) {
        material = NSVisualEffectMaterialSidebar;
    } else if ([name isEqualToString:@"under_window"]) {
        material = NSVisualEffectMaterialUnderWindowBackground;
    }

    NSView *contentView = [nsWindow contentView];
    NSVisualEffectView *effectView =
        [[NSVisualEffectView alloc] initWithFrame:[contentView bounds]];
    effectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effectView.material = material;
    effectView.state = NSVisualEffectStateActive;
    effectView.wantsLayer = YES;
    effectView.layer.cornerRadius = cornerRadius;
    effectView.layer.masksToBounds = YES;

    [contentView addSubview:effectView positioned:NSWindowBelow relativeTo:nil];

    // NOT setting opaque/backgroundColor here anymore -- Qt::WA_TranslucentBackground
    // (set on the QMainWindow itself, in MainWindow.cpp) already configures the
    // NSWindow for transparency through Qt's own Cocoa backend. Re-setting these
    // properties ourselves from outside Qt's control was fighting that setup and
    // is the likely cause of Qt's own content layer not compositing at all --
    // "just transparent, can't see or type anything" is exactly what you'd get
    // if Qt's content view lost its rendering, leaving only this raw blur view.
    [nsWindow setHasShadow:YES];

    // Inserting a sibling NSView can disturb the key-view / first-responder
    // chain Qt relies on for keyboard focus -- explicitly hand focus back to
    // Qt's own content view so typing still reaches it.
    [nsWindow makeFirstResponder:nsView];

    // Leak-on-purpose (retained by ARC via the extra __bridge_retained below,
    // for the app's lifetime, which is fine for a single top-level window);
    // returned as an opaque handle for alpha/radius control from C++.
    return (__bridge_retained void *)effectView;
}

void setGlassAlpha(void *effectView, double alpha0to1) {
    if (!effectView) return;
    NSVisualEffectView *view = (__bridge NSVisualEffectView *)effectView;
    view.alphaValue = alpha0to1 < 0 ? 0 : (alpha0to1 > 1 ? 1 : alpha0to1);
}

void setGlassCornerRadius(void *effectView, double radius) {
    if (!effectView) return;
    NSVisualEffectView *view = (__bridge NSVisualEffectView *)effectView;
    if (view.layer) view.layer.cornerRadius = radius;
}

}  // namespace MacVibrancy
