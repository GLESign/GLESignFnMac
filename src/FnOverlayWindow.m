#import "FnOverlayWindow.h"
#import <UIKit/UIKit.h>

@implementation FnOverlayWindow

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (BOOL)prefersPointerLocked {
    return NO;
}

- (void)becomeKeyWindow {

    UIWindowScene *scene = (UIWindowScene *)self.windowScene;
    if (!scene) return;

    UIWindow *gameWindow = nil;
    for (UIWindow *w in scene.windows) {
        if (w == self) continue;
        if (![w isKindOfClass:[FnOverlayWindow class]]) {
            if (!gameWindow || w.windowLevel < gameWindow.windowLevel) {
                gameWindow = w;
            }
        }
    }

    if (gameWindow) {

        if ([NSThread isMainThread]) {
            [gameWindow makeKeyWindow];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [gameWindow makeKeyWindow];
            });
        }
    }
}

- (void)resignKeyWindow {

}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];

    if (hit == self || hit == self.rootViewController.view) {
        return nil;
    }
    return hit;
}

@end
