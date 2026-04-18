#import "./views/popupViewController.h"
#import "./views/welcomeViewController.h"
#import "./globals.h"

#import "../lib/fishhook.h"
#import "./ue_reflection.h"
#import "./FnSwizzle.h"
#import <sys/sysctl.h>

#import <GameController/GameController.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>
#import <dlfcn.h>
#import <os/log.h>

static os_log_t fn_oslog(void) {
    static os_log_t h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        h = os_log_create("com.glesign.fnmactweak", "default");
    });
    return h;
}

#define fnlog(fmt, ...) \
    os_log_with_type(fn_oslog(), OS_LOG_TYPE_DEFAULT, "%{public}@", \
        [NSString stringWithFormat:@fmt, ##__VA_ARGS__])

static void fnmac_install_swizzles(void);

static void _updateVStick(BOOL isRight);
static void resetControllerState();
static void dispatchControllerButton(NSInteger idx, BOOL pressed);
static void _setVirtualFaceButton(NSString *element, BOOL pressed);
static void _setVirtualNamedButton(SEL propSel, BOOL pressed);

static char kButtonCodeKey;

static void updateGCMouseDirectState(int code, BOOL pressed) {
    if (code != 0 && (GCKeyCode)code == GCMOUSE_DIRECT_KEY) {
        isGCMouseDirectActive = pressed;
    }
}

#ifndef kCGHIDEventTap
#define kCGHIDEventTap 0
#endif

typedef uint64_t CGEventFlags;
typedef struct __CGEvent *CGEventRef;

static CGEventRef (*_CGEventCreateKeyboardEvent)(void *source, uint16_t virtualKey, bool keyDown) = NULL;
static void (*_CGEventSetFlags)(CGEventRef event, CGEventFlags flags) = NULL;
static CGEventFlags (*_CGEventGetFlags)(CGEventRef event) = NULL;
static void (*_CGEventPost)(int tap, CGEventRef event) = NULL;

typedef uint16_t UniChar;
typedef unsigned long UniCharCount;
static void (*_CGEventKeyboardGetUnicodeString)(CGEventRef event, UniCharCount maxStringLength, UniCharCount *actualStringLength, UniChar unicodeString[]) = NULL;
static void (*_CGEventKeyboardSetUnicodeString)(CGEventRef event, UniCharCount stringLength, const UniChar unicodeString[]) = NULL;

#define kCGEventFlagMaskAlphaShift 0x00010000
#define kCGEventFlagMaskShift      0x00020000

typedef uint32_t CGEventTapProxy;
typedef uint32_t CGEventType;
typedef int CGEventTapPlacement;
typedef int CGEventTapOptions;
typedef CGEventRef (*CGEventTapCallBack)(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon);

static CFMachPortRef (*_CGEventTapCreate)(int tap, CGEventTapPlacement place, CGEventTapOptions options, uint64_t eventsOfInterest, CGEventTapCallBack callback, void *refcon) = NULL;
static void (*_CGEventTapEnable)(CFMachPortRef tap, bool enable) = NULL;

extern "C" {
    #define kCGEventLeftMouseDown 1
    #define kCGEventLeftMouseUp 2
    #define kCGEventLeftMouseDragged 3
    #define kCGEventRightMouseDown 5
    #define kCGEventRightMouseUp 6
    #define kCGEventRightMouseDragged 7
    #define kCGEventOtherMouseDown 25
    #define kCGEventOtherMouseUp 26
    #define kCGEventOtherMouseDragged 8
    #define kCGMouseEventButtonNumber 3
    #define kCGHeadInsertEventTap 0
    #define kCGEventTapOptionDefault 0
}
static void (*_CGEventSetIntegerValueField)(CGEventRef event, int field, int64_t value) = NULL;
static int64_t (*_CGEventGetIntegerValueField)(CGEventRef event, int field) = NULL;

static CGEventRef mouseButtonTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon);
static BOOL _isMouseButtonSuppressed(int code);

#define kCGEventSourceUserData 42

@interface UITouch (Private)
- (void)_setType:(int)type;
- (void)setType:(int)type;
- (void)_setPathIndex:(int)index;
- (void)_setPathIdentity:(int)identity;
- (void)setWindow:(UIWindow *)window;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)reset;
- (void)setView:(UIView *)view;
- (void)setTapCount:(NSUInteger)count;
- (void)setIsTap:(BOOL)isTap;
- (void)_setIsFirstTouchForView:(BOOL)firstTouch;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setPhase:(UITouchPhase)phase;
@end

@interface UITouchesEvent : UIEvent
- (id)_init;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayedDelivery;
@property (nonatomic, assign) int singleAllowableExternalTouchPathIndex;
@end

@interface GCPhysicalInputProfile (FnTweak)
- (id)elementForName:(NSString *)name;
@end

static const uint16_t nsVKToGC[128] = {
    [0]=4,  [1]=22, [2]=7,  [3]=9,  [4]=11, [5]=10, [6]=29, [7]=27,
    [8]=6,  [9]=25, [10]=0, [11]=5, [12]=20,[13]=26,[14]=8, [15]=21,
    [16]=28,[17]=23,
    [18]=30,[19]=31,[20]=32,[21]=33,[22]=35,[23]=34,
    [24]=46,[25]=38,[26]=36,[27]=45,[28]=37,[29]=39,
    [30]=48,[31]=18,[32]=24,[33]=47,[34]=12,[35]=19,
    [36]=40,[37]=15,[38]=13,[39]=52,[40]=14,[41]=51,
    [42]=49,[43]=54,[44]=56,[45]=17,[46]=16,[47]=55,
    [48]=43,[49]=44,[50]=53,[51]=42,[52]=0, [53]=41,
    [54]=231,[55]=227,[56]=225,[57]=57,
    [58]=226,[59]=224,[60]=229,[61]=230,[62]=228,[63]=0,[64]=0,
    [65]=99,[66]=0, [67]=85,[69]=83,[70]=0, [71]=71,[72]=0,
    [75]=84,[76]=88,[77]=0, [78]=87,[79]=79,[80]=80,[81]=81,
    [82]=82,[83]=98,[84]=89,[85]=90,[86]=91,[87]=92,[88]=93,
    [89]=94,[90]=95,[91]=96,[92]=97,[96]=62,[97]=63,[98]=64,
    [99]=65,[100]=66,[101]=67,[102]=68,[103]=69,[104]=70,
    [105]=71,[106]=77,[107]=86,[108]=0, [109]=78,[110]=76,
    [111]=69,[112]=0, [113]=0, [114]=73,[115]=74,[116]=75,
    [117]=76,[118]=61,[119]=77,[120]=59,[121]=78,[122]=58,
    [123]=80,[124]=79,[125]=81,[126]=82,
};
static uint16_t gcToNSVK[256];

void updateBorderlessMode() {

    @try {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"

        Class nsAppClass = NSClassFromString(@"NSApplication");
        if (!nsAppClass) { return; }

        id sharedApp = [nsAppClass performSelector:NSSelectorFromString(@"sharedApplication")];
        NSArray *windows = [sharedApp performSelector:NSSelectorFromString(@"windows")];
        Class nsWindowClass = NSClassFromString(@"NSWindow");

        for (id window in windows) {

            if (!nsWindowClass || ![window isKindOfClass:nsWindowClass]) continue;

            NSUInteger currentMask = [[window valueForKey:@"styleMask"] unsignedIntegerValue];
            NSUInteger fullSizeMask = (1ULL << 15);
            NSUInteger newMask = isBorderlessModeEnabled ? (currentMask | fullSizeMask) : (currentMask & ~fullSizeMask);

            if (currentMask != newMask) {
                [window setValue:@(newMask) forKey:@"styleMask"];
            }

            if ([window respondsToSelector:NSSelectorFromString(@"setTitlebarAppearsTransparent:")]) {
                [window setValue:@(isBorderlessModeEnabled) forKey:@"titlebarAppearsTransparent"];
            }
            if ([window respondsToSelector:NSSelectorFromString(@"setTitleVisibility:")]) {
                [window setValue:@(isBorderlessModeEnabled ? 1 : 0) forKey:@"titleVisibility"];
            }

            SEL buttonSel = NSSelectorFromString(@"standardWindowButton:");
            if ([window respondsToSelector:buttonSel]) {
                for (NSInteger i = 0; i <= 2; i++) {

                    typedef id (*ButtonFunc)(id, SEL, NSInteger);
                    ButtonFunc getButton = (ButtonFunc)objc_msgSend;
                    id btn = getButton(window, buttonSel, i);

                    if (btn && [btn respondsToSelector:NSSelectorFromString(@"setHidden:")]) {
                        [btn setValue:@(isBorderlessModeEnabled) forKey:@"hidden"];
                    }
                }

                typedef id (*ButtonFunc)(id, SEL, NSInteger);
                id closeBtn = ((ButtonFunc)objc_msgSend)(window, buttonSel, 0);
                if (closeBtn) {
                    id container = [closeBtn valueForKey:@"superview"];
                    if (container && [container respondsToSelector:NSSelectorFromString(@"setHidden:")]) {
                        [container setValue:@(isBorderlessModeEnabled) forKey:@"hidden"];
                    }
                }
            }

                if (isBorderlessModeEnabled) {

                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        id screen = [window valueForKey:@"screen"];
                        if (screen) {
                            NSValue *visibleFrameVal = [screen valueForKey:@"visibleFrame"];
                            CGRect visibleFrame = visibleFrameVal ? [visibleFrameVal CGRectValue] : CGRectZero;
                            CGRect windowFrame = [[window valueForKey:@"frame"] CGRectValue];

                            if (!CGRectIsEmpty(visibleFrame) && !CGRectIsEmpty(windowFrame)) {
                                CGRect targetFrame = windowFrame;
                                targetFrame.origin.x = visibleFrame.origin.x + (visibleFrame.size.width  - windowFrame.size.width)  / 2.0;
                                targetFrame.origin.y = visibleFrame.origin.y + (visibleFrame.size.height - windowFrame.size.height) / 2.0;

                                NSMethodSignature *sig = [window methodSignatureForSelector:NSSelectorFromString(@"setFrame:display:")];
                                if (sig) {
                                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                                    [inv setSelector:NSSelectorFromString(@"setFrame:display:")];
                                    [inv setTarget:window];
                                    [inv setArgument:&targetFrame atIndex:2];
                                    BOOL display = YES;
                                    [inv setArgument:&display atIndex:3];
                                    [inv invoke];
                                }
                            }
                        }
                    });
                } else {

                    id screen = [window valueForKey:@"screen"];
                    if (screen) {
                        CGRect screenFrame = [[screen valueForKey:@"frame"] CGRectValue];
                        CGRect windowFrame = [[window valueForKey:@"frame"] CGRectValue];

                        CGRect targetFrame = windowFrame;
                        targetFrame.origin.x = screenFrame.origin.x + (screenFrame.size.width - windowFrame.size.width) / 2.0;
                        targetFrame.origin.y = screenFrame.origin.y + screenFrame.size.height - windowFrame.size.height;

                        NSMethodSignature *sig = [window methodSignatureForSelector:NSSelectorFromString(@"setFrame:display:")];
                        if (sig) {
                            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                            [inv setSelector:NSSelectorFromString(@"setFrame:display:")];
                            [inv setTarget:window];
                            [inv setArgument:&targetFrame atIndex:2];
                            BOOL display = YES;
                            [inv setArgument:&display atIndex:3];
                            [inv invoke];
                        }
                    }
                }

            if ([window respondsToSelector:NSSelectorFromString(@"setMovableByWindowBackground:")]) {
                [window setValue:@YES forKey:@"movableByWindowBackground"];
            }
        }

        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *uiWin in [[UIApplication sharedApplication] windows]) {
        #pragma clang diagnostic pop
            UIView *rootView = uiWin.rootViewController.view;
            if (rootView && [rootView respondsToSelector:@selector(setInsetsLayoutMarginsFromSafeArea:)]) {
                typedef void (*SetInsetsFunc)(id, SEL, BOOL);
                ((SetInsetsFunc)objc_msgSend)(rootView, @selector(setInsetsLayoutMarginsFromSafeArea:), !isBorderlessModeEnabled);
            }
        }
        #pragma clang diagnostic pop
    } @catch (NSException *exception) {
    }
}

static GCMouseMoved g_originalMouseHandler = nil;

static BOOL isTriggerHeld        = NO;
static BOOL remappedKeysState[512] = {NO};
static BOOL remappedMouseButtonsState[MOUSE_REMAP_COUNT] = {NO};
static void createPopup(void);
static void updateMouseLock(BOOL value, CGPoint warpPos);

@interface FnInputPulse : NSObject
- (void)onDisplayTick:(CADisplayLink *)sender;
@end

static BOOL wasLocked = YES;
static id g_virtualGamepad = nil;
static id g_vctrl_cached_ls = nil;
static id g_vctrl_cached_rs = nil;

static BOOL g_vctrlButtonTargetStates[FnCtrlButtonCount] = {NO};

@implementation FnInputPulse
- (void)onDisplayTick:(CADisplayLink *)sender {

    if (!isPopupVisible && blueDotIndicator && !blueDotIndicator.hidden) {
        blueDotIndicator.hidden = YES;
    }

    if ((!isMouseLocked && !isTriggerHeld) || isPopupVisible) {

        ue_apply_gyro_velocity(0, 0);
        if (wasLocked) { resetControllerState(); wasLocked = NO; }
        return;
    }
    wasLocked = YES;

    if (!g_virtualGamepad && g_virtualController) {
        g_virtualGamepad   = ue_get_extended_gamepad(g_virtualController);
        g_vctrl_cached_ls  = (g_virtualGamepad) ? [g_virtualGamepad leftThumbstick] : nil;
        g_vctrl_cached_rs  = (g_virtualGamepad) ? [g_virtualGamepad rightThumbstick] : nil;
    }

    if (isGCMouseDirectActive) {
        ue_apply_gyro_velocity(0, 0);
    }

    if (isTriggerHeld) {
        for (int i = 0; i < FnCtrlButtonCount; i++) {
            if (g_vctrlButtonTargetStates[i]) {
                dispatchControllerButton(i, YES);
            }
        }
    }

    _updateVStick(NO);
    _updateVStick(YES);
}
@end

static FnInputPulse *g_inputPulseHelper = nil;

static BOOL dpadState[4]   = {};
static BOOL lstickState[4] = {};
static BOOL rstickState[4] = {};

static void _setVirtualFaceButton(NSString *element, BOOL pressed) {
    float val = pressed ? 1.0f : 0.0f;
    for (GCController *ctrl in GCController.controllers) {
        GCExtendedGamepad *eg = ctrl.extendedGamepad;
        if (!eg) continue;

        GCControllerButtonInput *btn = nil;

        if (element && [eg respondsToSelector:@selector(elementForName:)]) {
            btn = (GCControllerButtonInput *)[(id)eg elementForName:element];
        }

        if (!btn || ![btn isKindOfClass:GCControllerButtonInput.class]) {
            SEL propSel = nil;
            if      ([element isEqualToString:@"Button A"])       propSel = @selector(buttonA);
            else if ([element isEqualToString:@"Button B"])       propSel = @selector(buttonB);
            else if ([element isEqualToString:@"Button X"])       propSel = @selector(buttonX);
            else if ([element isEqualToString:@"Button Y"])       propSel = @selector(buttonY);
            else if ([element isEqualToString:@"Menu"])           propSel = @selector(buttonMenu);
            else if ([element isEqualToString:@"Options"])        propSel = @selector(buttonOptions);
            else if ([element isEqualToString:@"Home"])           propSel = @selector(buttonHome);

            if (!propSel) {
                if ([element isEqualToString:@"Button A"]) propSel = @selector(buttonA);

            }

            if (propSel && [eg respondsToSelector:propSel]) {
                btn = ((id(*)(id,SEL))objc_msgSend)(eg, propSel);
            }
        }

        if (!btn || ![btn isKindOfClass:GCControllerButtonInput.class]) continue;

        if (btn.valueChangedHandler)   btn.valueChangedHandler(btn, val, pressed);
        if (btn.pressedChangedHandler) btn.pressedChangedHandler(btn, val, pressed);
        if ([btn respondsToSelector:@selector(_setValue:)]) {
            NSMethodSignature *sig = [btn methodSignatureForSelector:@selector(_setValue:)];
            if (sig && strcmp([sig getArgumentTypeAtIndex:2], "f") == 0) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setSelector:@selector(_setValue:)];
                [inv setTarget:btn];
                [inv setArgument:&val atIndex:2];
                [inv invoke];
            }
        }
    }
}

static void _updateVStick(BOOL isRight) {
    id dpad = isRight ? g_vctrl_cached_rs : g_vctrl_cached_ls;
    if (!dpad) {

        if (!g_virtualGamepad && g_virtualController) {
            g_virtualGamepad = ue_get_extended_gamepad(g_virtualController);
            g_vctrl_cached_ls = [g_virtualGamepad leftThumbstick];
            g_vctrl_cached_rs = [g_virtualGamepad rightThumbstick];
        }
        dpad = isRight ? g_vctrl_cached_rs : g_vctrl_cached_ls;
        if (!dpad) return;
    }

    BOOL *state = isRight ? rstickState : lstickState;
    float dx = 0, dy = 0;
    if (state[0]) dy += 1.0f;
    if (state[1]) dy -= 1.0f;
    if (state[2]) dx -= 1.0f;
    if (state[3]) dx += 1.0f;

    float len = sqrtf(dx*dx + dy*dy);
    if (len > 1.0f) { dx /= len; dy /= len; }

    ue_reflect_thumbstick(dpad, dx, dy);
}

static void reassertAllInputs() {
    for (int i = 0; i < FnCtrlButtonCount; i++) {
        if (g_vctrlButtonTargetStates[i]) {
            dispatchControllerButton(i, YES);
        }
    }
    _updateVStick(NO);
    _updateVStick(YES);
}

static void resetControllerState() {

    for (int i=0; i<4; i++) {
        dpadState[i] = NO;
        lstickState[i] = NO;
        rstickState[i] = NO;
    }

    _updateVStick(NO);
    _updateVStick(YES);

    _setVirtualFaceButton((NSString *)GCInputButtonA, NO);
    _setVirtualFaceButton((NSString *)GCInputButtonB, NO);
    _setVirtualFaceButton((NSString *)GCInputButtonX, NO);
    _setVirtualFaceButton((NSString *)GCInputButtonY, NO);

    _setVirtualNamedButton(NSSelectorFromString(@"leftShoulder"), NO);
    _setVirtualNamedButton(NSSelectorFromString(@"rightShoulder"), NO);
    _setVirtualNamedButton(NSSelectorFromString(@"leftTrigger"), NO);
    _setVirtualNamedButton(NSSelectorFromString(@"rightTrigger"), NO);
    _setVirtualFaceButton(@"Options", NO);
    _setVirtualFaceButton(@"Menu", NO);
    _setVirtualFaceButton(@"Home", NO);

    dispatchControllerButton(FnCtrlL3, NO);
    dispatchControllerButton(FnCtrlR3, NO);
}

static void _setVirtualNamedButton(SEL propSel, BOOL pressed) {
    float val = pressed ? 1.0f : 0.0f;
    for (GCController *ctrl in GCController.controllers) {
        GCExtendedGamepad *eg = ctrl.extendedGamepad;
        if (!eg) continue;

        GCControllerButtonInput *btn = nil;

        if (propSel && [eg respondsToSelector:propSel]) {
            btn = ((id(*)(id,SEL))objc_msgSend)(eg, propSel);
        }

        if (!btn && [eg respondsToSelector:@selector(elementForName:)]) {
            NSString *selStr = NSStringFromSelector(propSel);
            if ([selStr isEqualToString:@"leftShoulder"])  btn = (GCControllerButtonInput *)[(id)eg elementForName:@"Left Shoulder"];
            if ([selStr isEqualToString:@"rightShoulder"]) btn = (GCControllerButtonInput *)[(id)eg elementForName:@"Right Shoulder"];
            if ([selStr isEqualToString:@"leftTrigger"])   btn = (GCControllerButtonInput *)[(id)eg elementForName:@"Left Trigger"];
            if ([selStr isEqualToString:@"rightTrigger"])  btn = (GCControllerButtonInput *)[(id)eg elementForName:@"Right Trigger"];
        }

        if (!btn || ![btn isKindOfClass:GCControllerButtonInput.class]) continue;

        if (btn.valueChangedHandler)   btn.valueChangedHandler(btn, val, pressed);
        if (btn.pressedChangedHandler) btn.pressedChangedHandler(btn, val, pressed);
        if ([btn respondsToSelector:@selector(_setValue:)]) {
            NSMethodSignature *sig = [btn methodSignatureForSelector:@selector(_setValue:)];
            if (sig && strcmp([sig getArgumentTypeAtIndex:2], "f") == 0) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setSelector:@selector(_setValue:)];
                [inv setTarget:btn];
                [inv setArgument:&val atIndex:2];
                [inv invoke];
            }
        }
    }
}

static void _sendKeyEvent(GCKeyCode kc, BOOL pressed) {
    if (!storedKeyboardHandler) return;

    if (!storedKeyboardInput) {
        if (@available(iOS 14, *)) {
            GCKeyboard *kb = [GCKeyboard coalescedKeyboard];
            if (kb) storedKeyboardInput = kb.keyboardInput;
        }
    }

    if (!storedKeyboardInput) return;

    GCControllerButtonInput *btn = nil;
    if ([storedKeyboardInput respondsToSelector:@selector(buttonForKeyCode:)]) {
        btn = [storedKeyboardInput buttonForKeyCode:kc];
    }

    if (!btn) {

        btn = [storedKeyboardInput buttonForKeyCode:GCKeyCodeKeyA];
    }

    if (btn) {
        storedKeyboardHandler(storedKeyboardInput, btn, kc, pressed);
    }
}

static void _sendDualKeyEvent(GCKeyCode kc, BOOL pressed) {

    if (kc != 0 && kc == GCMOUSE_DIRECT_KEY) {
        updateGCMouseDirectState((int)kc, pressed);

    }

    _sendKeyEvent(kc, pressed);

    if ((int)kc < 256) {
        uint16_t rv = gcToNSVK[(uint8_t)kc];
        if (rv > 0 || (int)kc == 4) {
            if (_CGEventCreateKeyboardEvent && _CGEventPost) {
                CGEventRef ev = _CGEventCreateKeyboardEvent(NULL, rv, pressed);
                if (ev) {
                    _CGEventSetIntegerValueField(ev, kCGEventSourceUserData, 0x1337);
                    _CGEventPost(kCGHIDEventTap, ev);
                    CFRelease(ev);
                }
            }
        }
    }
}

static id getInjectedButton(GCExtendedGamepad *gamepad, NSString *key) {
    if (!gamepad) return nil;
    static char const * const kInjectedButtonsKey = "kInjectedButtonsKey";
    NSMutableDictionary *dict = objc_getAssociatedObject(gamepad, kInjectedButtonsKey);
    if (!dict) {
        dict = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(gamepad, kInjectedButtonsKey, dict, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    id btn = dict[key];
    if (!btn) {

        btn = [[NSClassFromString(@"FnInjectedButton") alloc] init];
        if (btn) dict[key] = btn;
    }
    return btn;
}

@interface FnInjectedButton : GCControllerButtonInput
- (BOOL)isPressed;
- (BOOL)pressed;
- (float)value;
- (void)_setValue:(float)v;
@end

@implementation FnInjectedButton

- (BOOL)isPressed {
    return [objc_getAssociatedObject(self, @selector(isPressed)) boolValue];
}

- (BOOL)pressed { return [self isPressed]; }

- (float)value {
    return [objc_getAssociatedObject(self, @selector(value)) floatValue];
}

- (void)_setValue:(float)v {
    BOOL pressed = (v > 0.5);

    [self willChangeValueForKey:@"value"];
    [self willChangeValueForKey:@"isPressed"];
    [self willChangeValueForKey:@"pressed"];

    objc_setAssociatedObject(self, @selector(value), @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, @selector(isPressed), @(pressed), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [self didChangeValueForKey:@"value"];
    [self didChangeValueForKey:@"isPressed"];
    [self didChangeValueForKey:@"pressed"];

    if (self.valueChangedHandler)   self.valueChangedHandler(self, v, pressed);
    if (self.pressedChangedHandler) self.pressedChangedHandler(self, v, pressed);
}

@end

static void dispatchControllerButton(NSInteger idx, BOOL pressed) {

    if (idx >= 0 && idx < FnCtrlButtonCount) g_vctrlButtonTargetStates[idx] = pressed;

    if (!g_virtualGamepad) {
        if (g_virtualController) g_virtualGamepad = ue_get_extended_gamepad(g_virtualController);
        if (!g_virtualGamepad) return;
    }

    switch (idx) {

        case FnCtrlLeftStickUp:    lstickState[0] = pressed; _updateVStick(NO);  break;
        case FnCtrlLeftStickDown:  lstickState[1] = pressed; _updateVStick(NO);  break;
        case FnCtrlLeftStickLeft:  lstickState[2] = pressed; _updateVStick(NO);  break;
        case FnCtrlLeftStickRight: lstickState[3] = pressed; _updateVStick(NO);  break;

        case FnCtrlRightStickUp:    rstickState[0] = pressed; _updateVStick(YES); break;
        case FnCtrlRightStickDown:  rstickState[1] = pressed; _updateVStick(YES); break;
        case FnCtrlRightStickLeft:  rstickState[2] = pressed; _updateVStick(YES); break;
        case FnCtrlRightStickRight: rstickState[3] = pressed; _updateVStick(YES); break;

        case FnCtrlDpadUp:    dpadState[0] = pressed; break;
        case FnCtrlDpadDown:  dpadState[1] = pressed; break;
        case FnCtrlDpadLeft:  dpadState[2] = pressed; break;
        case FnCtrlDpadRight: dpadState[3] = pressed; break;

        case FnCtrlL3:
        case FnCtrlR3: {

            GCControllerButtonInput *btn = (idx == FnCtrlL3) ? [g_virtualGamepad leftThumbstickButton] : [g_virtualGamepad rightThumbstickButton];
            if (btn) {
                float val = pressed ? 1.0f : 0.0f;
                static SEL setValueSel = NULL;
                if (!setValueSel) setValueSel = NSSelectorFromString(@"_setValue:");

                if ([btn respondsToSelector:setValueSel]) {
                    typedef void (*SetValueFunc)(id, SEL, float);
                    ((SetValueFunc)objc_msgSend)(btn, setValueSel, val);
                } else {
                    if (btn.valueChangedHandler)   btn.valueChangedHandler(btn, val, pressed);
                    if (btn.pressedChangedHandler) btn.pressedChangedHandler(btn, val, pressed);
                }
            }
            break;
        }
        case FnCtrlOptions: {
            _setVirtualFaceButton(@"Menu", pressed); break;
        }
        case FnCtrlShare: {
            _setVirtualFaceButton(@"Options", pressed); break;
        }
        case FnCtrlHome: {
            _setVirtualFaceButton(@"Home", pressed); break;
        }
        default: break;
    }

    switch (idx) {
        case FnCtrlButtonA: _setVirtualFaceButton(GCInputButtonA, pressed); break;
        case FnCtrlButtonB: _setVirtualFaceButton(GCInputButtonB, pressed); break;
        case FnCtrlButtonX: _setVirtualFaceButton(GCInputButtonX, pressed); break;
        case FnCtrlButtonY: _setVirtualFaceButton(GCInputButtonY, pressed); break;
        case FnCtrlL1: {
            static SEL s = NULL; if (!s) s = NSSelectorFromString(@"leftShoulder");
            _setVirtualNamedButton(s, pressed); break;
        }
        case FnCtrlR1: {
            static SEL s = NULL; if (!s) s = NSSelectorFromString(@"rightShoulder");
            _setVirtualNamedButton(s, pressed); break;
        }
        case FnCtrlL2: {
            static SEL s = NULL; if (!s) s = NSSelectorFromString(@"leftTrigger");
            _setVirtualNamedButton(s, pressed); break;
        }
        case FnCtrlR2: {
            static SEL s = NULL; if (!s) s = NSSelectorFromString(@"rightTrigger");
            _setVirtualNamedButton(s, pressed); break;
        }
        default: break;
    }

    if (idx >= FnCtrlDpadUp && idx <= FnCtrlDpadRight) {
        float dx = 0, dy = 0;
        if (dpadState[0]) dy += 1.0f;
        if (dpadState[1]) dy -= 1.0f;
        if (dpadState[2]) dx -= 1.0f;
        if (dpadState[3]) dx += 1.0f;
        for (GCController *ctrl in GCController.controllers) {
            GCExtendedGamepad *eg = ctrl.extendedGamepad;
            if (eg) ue_reflect_thumbstick(eg.dpad, dx, dy);
        }
    }
}

typedef struct {
    uint32_t platform;
    uint32_t version;
} dyld_build_version_t;

#define PLATFORM_IOS       2
#define PACK_VER(M,m,p)    (((uint32_t)(M)<<16)|((uint32_t)(m)<<8)|(uint32_t)(p))
#define BLOCKED_VERSION    PACK_VER(17, 4, 0)

static bool (*orig_availability_version_check)(uint32_t, dyld_build_version_t []);

static bool hooked_availability_version_check(uint32_t count,
                                               dyld_build_version_t versions[]) {
    for (uint32_t i = 0; i < count; i++) {
        if (versions[i].platform == PLATFORM_IOS &&
            versions[i].version  == BLOCKED_VERSION) {
            return false;
        }
    }
    return orig_availability_version_check(count, versions);
}

static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t) = NULL;
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t) = NULL;

static int pt_sysctl(int *name, u_int namelen, void *buf, size_t *size, void *arg0, size_t arg1) {
    if (name[0] == CTL_HW && (name[1] == HW_MACHINE || name[1] == HW_PRODUCT)) {
        if (buf == NULL) {
            *size = strlen(DEVICE_MODEL) + 1;
        } else {
            if (*size > strlen(DEVICE_MODEL)) {
                strcpy((char *)buf, DEVICE_MODEL);
            } else {
                return ENOMEM;
            }
        }
        return 0;
    } else if (name[0] == CTL_HW && name[1] == HW_TARGET) {
        if (buf == NULL) {
            *size = strlen(OEM_ID) + 1;
        } else {
            if (*size > strlen(OEM_ID)) {
                strcpy((char *)buf, OEM_ID);
            } else {
                return ENOMEM;
            }
        }
        return 0;
    }
    return orig_sysctl(name, namelen, buf, size, arg0, arg1);
}

static int pt_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if ((strcmp(name, "hw.machine") == 0) || (strcmp(name, "hw.product") == 0) || (strcmp(name, "hw.model") == 0)) {
        if (oldp == NULL) {
            int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
            if (oldlenp && *oldlenp < strlen(DEVICE_MODEL) + 1) {
                *oldlenp = strlen(DEVICE_MODEL) + 1;
            }
            return ret;
        } else if (oldp != NULL) {
            int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
            const char *machine = DEVICE_MODEL;
            strncpy((char *)oldp, machine, strlen(machine));
            ((char *)oldp)[strlen(machine)] = '\0';
            if (oldlenp) *oldlenp = strlen(machine) + 1;
            return ret;
        }
    } else if (strcmp(name, "hw.target") == 0) {
        if (oldp == NULL) {
            int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
            if (oldlenp && *oldlenp < strlen(OEM_ID) + 1) {
                *oldlenp = strlen(OEM_ID) + 1;
            }
            return ret;
        } else if (oldp != NULL) {
            int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
            const char *machine = OEM_ID;
            strncpy((char *)oldp, machine, strlen(machine));
            ((char *)oldp)[strlen(machine)] = '\0';
            if (oldlenp) *oldlenp = strlen(machine) + 1;
            return ret;
        }
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

@interface UIView (BlueDotDragging)
- (void)handleBluePan:(UIPanGestureRecognizer *)gesture;
@end

@implementation UIView (BlueDotDragging)
- (void)handleBluePan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:self.superview];
        CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
        CGRect bounds = self.superview.bounds;
        newCenter.x = MAX(10, MIN(bounds.size.width  - 10, newCenter.x));
        newCenter.y = MAX(10, MIN(bounds.size.height - 10, newCenter.y));
        self.center = newCenter;
        blueDotPosition = newCenter;
        [gesture setTranslation:CGPointZero inView:self.superview];
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled) {
        NSDictionary *posDict = @{@"x": @(blueDotPosition.x), @"y": @(blueDotPosition.y)};
        [[NSUserDefaults standardUserDefaults] setObject:posDict forKey:kBlueDotPositionKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}
@end

__attribute__((constructor))
static void fnmac_init(void) {
    fnlog("init begin  pid=%d  bundle=%@",
          getpid(),
          [[NSBundle mainBundle] bundleIdentifier] ?: @"?");

    fnmac_install_swizzles();

    ue_init_gyro_hooks();
    fnlog("gyro proxy hooks installed");

    struct rebinding rebindings[] = {
        {"sysctl", (void *)pt_sysctl, (void **)&orig_sysctl},
        {"sysctlbyname", (void *)pt_sysctlbyname, (void **)&orig_sysctlbyname},
        {"_availability_version_check", (void *)hooked_availability_version_check, (void **)&orig_availability_version_check}
    };
    int rb_rc = rebind_symbols(rebindings, 3);
    fnlog("fishhook rebind rc=%d  (sysctl, sysctlbyname, _availability_version_check)", rb_rc);

    NSString* currentVersion = @"4.0.0";
    NSString* lastVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"fnmactweak.lastSeenVersion"];

    if (!lastVersion || ![lastVersion isEqualToString:currentVersion]) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kKeyRemapKey];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"fnmactweak.welcomeSeenVersion"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"fnmactweak.welcomeSuppressed"];
        [[NSUserDefaults standardUserDefaults] setObject:currentVersion forKey:@"fnmactweak.lastSeenVersion"];
        fnlog("first-run after upgrade: version %@ -> %@  (cleared remaps+welcome flags)",
              lastVersion ?: @"(none)", currentVersion);
    }
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSData *bookmark = [[NSUserDefaults standardUserDefaults] dataForKey:@"fnmactweak.datafolder"];
    if (bookmark) {
        BOOL stale = NO;
        NSError *error = nil;
        NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark
                                               options:NSURLBookmarkResolutionWithoutUI
                                         relativeToURL:nil
                                   bookmarkDataIsStale:&stale
                                                 error:&error];
        if (url) {
            [url startAccessingSecurityScopedResource];
        }
    }

    TRIGGER_KEY = GCKeyCodeLeftAlt;

    NSDictionary *savedSettings = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSettingsKey];
    if (savedSettings) {
        float v;
        v = [savedSettings[kBaseXYKey] floatValue]; if (v > 0) BASE_XY_SENSITIVITY = v;
        v = [savedSettings[kScaleKey]  floatValue]; if (v > 0) MACOS_TO_PC_SCALE   = v;
        v = [savedSettings[kGyroMultiplierKey] floatValue]; if (v > 0) GYRO_MULTIPLIER = v;
        GCMOUSE_DIRECT_KEY = (GCKeyCode)[savedSettings[kGCMouseDirectKey] intValue];
    }

    recalculateSensitivities();
    fnlog("sensitivities: base_xy=%.2f  scale=%.2f  gyro=%.2f  direct_key=%d",
          BASE_XY_SENSITIVITY, MACOS_TO_PC_SCALE, GYRO_MULTIPLIER, (int)GCMOUSE_DIRECT_KEY);

    loadKeyRemappings();
    loadFortniteKeybinds();
    loadControllerMappings();
    fnlog("keybinds loaded  (custom remaps + fortnite defaults + controller map)");

    void *cgHandle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW);
    if (cgHandle) {
        _CGEventTapCreate = (CFMachPortRef (*)(int, int, int, uint64_t, CGEventTapCallBack, void *))dlsym(cgHandle, "CGEventTapCreate");
        _CGEventTapEnable = (void (*)(CFMachPortRef, bool))dlsym(cgHandle, "CGEventTapEnable");
    }

    if (_CGEventTapCreate && _CGEventTapEnable) {
        uint64_t keyboardMask = (1ULL << 10) | (1ULL << 11) | (1ULL << 12);
        uint64_t mouseMask = (1ULL << kCGEventOtherMouseDown) | (1ULL << kCGEventOtherMouseUp) | (1ULL << kCGEventOtherMouseDragged);
        CFMachPortRef eventTap = _CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                                                  keyboardMask | mouseMask,
                                                  mouseButtonTapCallback, NULL);
        if (eventTap) {
            CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
            _CGEventTapEnable(eventTap, true);
            fnlog("CGEventTap installed  (keyboard + other-mouse events)");
        } else {
            fnlog("CGEventTap create FAILED (keyboard + mouse events will not route through tap)");
        }
    } else {
        fnlog("CoreGraphics CGEventTap* unavailable  (CG dlsym failed)");
    }

    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (@available(iOS 15, *)) {
                GCVirtualControllerConfiguration *cfg =
                    [[GCVirtualControllerConfiguration alloc] init];

                cfg.elements = [NSSet setWithObjects:
                    GCInputLeftThumbstick,
                    GCInputRightThumbstick,
                    GCInputButtonA, GCInputButtonB,
                    GCInputButtonX, GCInputButtonY,
                    GCInputLeftShoulder,
                    GCInputRightShoulder,
                    GCInputLeftTrigger,
                    GCInputRightTrigger,
                    nil];
                if ([cfg respondsToSelector:@selector(setHidden:)]) cfg.hidden = YES;
                g_virtualController = [GCVirtualController virtualControllerWithConfiguration:cfg];

                g_inputPulseHelper = [[FnInputPulse alloc] init];
                CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:g_inputPulseHelper selector:@selector(onDisplayTick:)];
                [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

                SEL connectSel = NSSelectorFromString(@"connectWithReplyHandler:");
                void (^reply)(NSError *) = ^(NSError *error) {
                    if (error) {
                        fnlog("virtual controller connect FAILED: %@", error.localizedDescription);
                    } else {
                        fnlog("virtual controller connected  (DualSense spoof active)");
                    }
                };
                if ([g_virtualController respondsToSelector:connectSel])
                    ((void(*)(id,SEL,id))objc_msgSend)(g_virtualController, connectSel, reply);
                else
                    fnlog("virtual controller: connectWithReplyHandler: not available on this iOS");
            } else {
                fnlog("virtual controller: iOS < 15, skipping");
            }
        });
    }];

    showWelcomePopupIfNeeded();

    isBorderlessModeEnabled = [tweakDefaults() boolForKey:kBorderlessWindowKey];
    fnlog("borderless mode: %s", isBorderlessModeEnabled ? "ON" : "OFF");

    if (isBorderlessModeEnabled) {
        id __block observer = [[NSNotificationCenter defaultCenter]
            addObserverForName:NSNotificationName(@"NSWindowDidBecomeKeyNotification")
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        [[NSNotificationCenter defaultCenter] removeObserver:observer];
                        observer = nil;
                        updateBorderlessMode();
                    }];
    }

    Class nsEventClass = NSClassFromString(@"NSEvent");
    if (nsEventClass) {

        if (!_CGEventPost) {
            void *cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW);
            if (cg) {
                _CGEventCreateKeyboardEvent = (CGEventRef(*)(void*,uint16_t,bool))dlsym(cg, "CGEventCreateKeyboardEvent");
                _CGEventSetFlags = (void(*)(CGEventRef,CGEventFlags))dlsym(cg, "CGEventSetFlags");
                _CGEventGetFlags = (CGEventFlags(*)(CGEventRef))dlsym(cg, "CGEventGetFlags");
                _CGEventPost = (void(*)(int,CGEventRef))dlsym(cg, "CGEventPost");
                _CGEventSetIntegerValueField = (void(*)(CGEventRef,int,int64_t))dlsym(cg, "CGEventSetIntegerValueField");
                _CGEventGetIntegerValueField = (int64_t(*)(CGEventRef,int))dlsym(cg, "CGEventGetIntegerValueField");
                _CGEventKeyboardGetUnicodeString = (void(*)(CGEventRef,UniCharCount,UniCharCount*,UniChar[]))dlsym(cg, "CGEventKeyboardGetUnicodeString");
                _CGEventKeyboardSetUnicodeString = (void(*)(CGEventRef,UniCharCount,const UniChar[]))dlsym(cg, "CGEventKeyboardSetUnicodeString");
            }
        }

        static BOOL gcToNSVKInitialized = NO;
        if (!gcToNSVKInitialized) {
            memset(gcToNSVK, 0, sizeof(gcToNSVK));
            for (int i = 0; i < 128; i++) {
                if (nsVKToGC[i] != 0 && nsVKToGC[i] < 256) gcToNSVK[nsVKToGC[i]] = (uint16_t)i;
            }
            gcToNSVKInitialized = YES;
        }

        static SEL keyCodeSel2  = NULL;
        static SEL modFlagsSel2 = NULL;
        static SEL typeSel3     = NULL;
        if (!keyCodeSel2)  keyCodeSel2  = NSSelectorFromString(@"keyCode");
        if (!modFlagsSel2) modFlagsSel2 = NSSelectorFromString(@"modifierFlags");
        if (!typeSel3)     typeSel3     = NSSelectorFromString(@"type");

        unsigned long long keyMask = (1ULL << 1) | (1ULL << 2) | (1ULL << 3) | (1ULL << 4) | (1ULL << 5) | (1ULL << 6) | (1ULL << 7) | (1ULL << 8) | (1ULL << 10) | (1ULL << 11) | (1ULL << 12) | (1ULL << 25) | (1ULL << 26);

        unsigned long long scrollMask = 1ULL << 22;

        static SEL scrollingDeltaYSel = NULL;
        if (!scrollingDeltaYSel) scrollingDeltaYSel = NSSelectorFromString(@"scrollingDeltaY");

        id (^handlerBlock)(id) = ^id (id event) {

            if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return event;

            if (![event respondsToSelector:scrollingDeltaYSel]) return event;
            CGFloat deltaY = ((CGFloat(*)(id, SEL))objc_msgSend)(event, scrollingDeltaYSel);

            if (deltaY == 0) return event;

            int scrollCode = (deltaY > 0) ? MOUSE_SCROLL_UP : MOUSE_SCROLL_DOWN;
            int idx = scrollCode - MOUSE_SCROLL_UP;

            GCKeyCode kc = (idx >= 0 && idx < MOUSE_SCROLL_COUNT) ? mouseScrollRemapArray[idx] : 0;

            if (kc == 0 && idx >= 0 && idx < MOUSE_SCROLL_COUNT)
                kc = mouseScrollFortniteArray[idx];

            if (kc == 0 && scrollCode < 10200)
                kc = fortniteRemapArray[scrollCode];

            if (mouseButtonCaptureCallback != nil || keyCaptureCallback != nil) {
              if (mouseButtonCaptureCallback) mouseButtonCaptureCallback(scrollCode);
              else if (keyCaptureCallback) keyCaptureCallback((GCKeyCode)scrollCode);
              return nil;
            }

            if (isTypingModeEnabled) return event;

            if (isControllerModeEnabled && !isPopupVisible) {
                BOOL isMappedToController = NO;

                NSSet *tgts = vctrlCookedRemappings[@(scrollCode)];
                for (NSNumber *tgt in tgts) {
                    int vbtn = [tgt intValue];
                    isMappedToController = YES;
                    if (isMouseLocked || isTriggerHeld) {
                        dispatchControllerButton(vbtn, YES);
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.015 * NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{
                            dispatchControllerButton(vbtn, NO);
                        });
                    }
                }

                for (int i = 0; i < FnCtrlButtonCount; i++) {
                    if (controllerMappingArray[i] == scrollCode) {
                        isMappedToController = YES;
                        if (isMouseLocked || isTriggerHeld) {
                            dispatchControllerButton(i, YES);
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.015 * NSEC_PER_SEC)),
                                           dispatch_get_main_queue(), ^{
                                dispatchControllerButton(i, NO);
                            });
                        }
                    }
                }

                if (isMappedToController) return nil;
            }

            if (kc != 0 && !isPopupVisible) {
                if (isMouseLocked) {

                    _sendDualKeyEvent(kc, YES);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        _sendDualKeyEvent(kc, NO);
                    });
                }
                return nil;
            }

            if (!isMouseLocked) return event;

            if (idx >= 0 && idx < MOUSE_SCROLL_COUNT) {
                if (mouseScrollRemapArray[idx] != 0 || mouseScrollFortniteArray[idx] != 0) return nil;
            }

            GCMouse *currentMouse = GCMouse.current;
            if (currentMouse && currentMouse.mouseInput) {
                GCControllerDirectionPad *scrollPad = currentMouse.mouseInput.scroll;
                if (scrollPad && scrollPad.valueChangedHandler) {
                    float yVal = (deltaY > 0) ? 1.0f : -1.0f;

                    scrollPad.valueChangedHandler(scrollPad, 0.0f, yVal);

                    if ([scrollPad.yAxis respondsToSelector:@selector(setValue:)]) {
                        [scrollPad.yAxis setValue:0.0f];
                    }

                    scrollPad.valueChangedHandler(scrollPad, 0.0f, 0.0f);
                }
            }

            return nil;
        };

        SEL addMonitorSel = NSSelectorFromString(@"addLocalMonitorForEventsMatchingMask:handler:");
        if ([nsEventClass respondsToSelector:addMonitorSel]) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[nsEventClass methodSignatureForSelector:addMonitorSel]];
            [inv setSelector:addMonitorSel];
            [inv setTarget:nsEventClass];

            [inv setArgument:&scrollMask atIndex:2];

            id blockArg = [handlerBlock copy];
            [inv setArgument:&blockArg atIndex:3];

            [inv invoke];
        }

        static BOOL prevOptionHeld2 = NO;

        id (^kbMonitor)(id) = ^id(id event) {

            if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return event;

            static SEL cgEventSel = NULL;
            if (!cgEventSel) cgEventSel = NSSelectorFromString(@"CGEvent");
            CGEventRef cgEv = ((CGEventRef(*)(id,SEL))objc_msgSend)(event, cgEventSel);
            if (cgEv && _CGEventGetIntegerValueField(cgEv, kCGEventSourceUserData) == 0x1337) return event;
            NSUInteger evType = ((NSUInteger(*)(id,SEL))objc_msgSend)(event, typeSel3);

            if (isTypingModeEnabled) return event;

            if (evType >= 5 && evType <= 8) {
                if (isMouseLocked || isGCMouseDirectActive) {
                    static SEL dxSel = NULL, dySel = NULL;
                    if (!dxSel) dxSel = NSSelectorFromString(@"deltaX");
                    if (!dySel) dySel = NSSelectorFromString(@"deltaY");

                    CGFloat dx = ((CGFloat(*)(id,SEL))objc_msgSend)(event, dxSel);
                    CGFloat dy = -((CGFloat(*)(id,SEL))objc_msgSend)(event, dySel);

                    mouseAccumX += (double)dx;
                    mouseAccumY += (double)dy;

                    return nil;
                }
                return event;
            }

            if ((evType >= 1 && evType <= 4) || evType == 25 || evType == 26 || (evType >= 6 && evType <= 8)) {
                int currentBtnCode = 0;

                BOOL isPressed = (evType == 1 || evType == 3 || evType == 25 || (evType >= 6 && evType <= 8));

                if (evType == 1 || evType == 2 || evType == 6) currentBtnCode = MOUSE_BUTTON_LEFT;
                else if (evType == 3 || evType == 4 || evType == 7) currentBtnCode = MOUSE_BUTTON_RIGHT;
                else if (evType == 25 || evType == 26 || evType == 8) {
                    static SEL btnNumSel = NULL;
                    if (!btnNumSel) btnNumSel = NSSelectorFromString(@"buttonNumber");
                    NSInteger btnNum = ((NSInteger(*)(id,SEL))objc_msgSend)(event, btnNumSel);
                    if (btnNum == 2) currentBtnCode = MOUSE_BUTTON_MIDDLE;
                    else if (btnNum >= 3) currentBtnCode = (int)(MOUSE_BUTTON_AUX_BASE + (btnNum - 3));
                }

                if (isPressed) {
                    if (mouseButtonCaptureCallback != nil || keyCaptureCallback != nil) {
                        if (isPopupVisible) {

                            if (currentBtnCode == MOUSE_BUTTON_LEFT && ignoreNextLeftClickCount > 0) {
                                ignoreNextLeftClickCount--;
                                return event;
                            }

                            typedef CGPoint (*LocationFunc)(id, SEL);
                            LocationFunc getLoc = (LocationFunc)objc_msgSend;
                            CGPoint pt = getLoc(event, NSSelectorFromString(@"locationInWindow"));

                            pt.y = popupWindow.bounds.size.height - pt.y;

                            UIViewController *vc = popupWindow.rootViewController;
                            if (vc) {
                                UIViewController *presented = vc.presentedViewController;
                                if (presented) {
                                    CGPoint alertPt = [popupWindow convertPoint:pt toView:presented.view];
                                    UIView *aHit = [presented.view hitTest:alertPt withEvent:nil];

                                    if (aHit && aHit != presented.view) {
                                        return event;
                                    }
                                }
                            }

                            if (mouseButtonCaptureCallback != nil) {
                                mouseButtonCaptureCallback(currentBtnCode);
                                return nil;
                            }
                            if (keyCaptureCallback != nil) {
                                keyCaptureCallback(currentBtnCode);
                                return nil;
                            }
                        }
                    }
                }

                if (isPopupVisible) return event;

                if (isMouseLocked || isGCMouseDirectActive) {
                    if (evType == 1) leftButtonIsPressed = YES;
                    if (evType == 2) leftButtonIsPressed = NO;
                    if (evType == 3) rightButtonIsPressed = YES;
                    if (evType == 4) rightButtonIsPressed = NO;
                    if (evType == 25) middleButtonIsPressed = YES;
                    if (evType == 26) middleButtonIsPressed = NO;
                } else if (!isMouseLocked && !isTriggerHeld) {

                    return event;
                }

                if (isControllerModeEnabled && !isPopupVisible) {
                    if (currentBtnCode != 0) {
                    updateGCMouseDirectState(currentBtnCode, isPressed);

                        if (isMouseLocked || isTriggerHeld || !isPressed) {
                            for (int i = 0; i < FnCtrlButtonCount; i++) {
                                if (controllerMappingArray[i] == currentBtnCode) {
                                    dispatchControllerButton(i, isPressed);
                                }
                            }
                        }

                        if (isMouseLocked || isTriggerHeld || !isPressed) {
                            NSSet *tgts = vctrlCookedRemappings[@(currentBtnCode)];
                            for (NSNumber *tgt in tgts) {
                                dispatchControllerButton([tgt intValue], isPressed);
                            }
                        }
                    }
                }

                int mbIdx = currentBtnCode - MOUSE_BUTTON_MIDDLE;
                if (!isPopupVisible && currentBtnCode != 0) {
                    GCKeyCode mbTarget = 0;

                    if (currentBtnCode >= 0 && currentBtnCode < 10200) {
                        mbTarget = fortniteRemapArray[currentBtnCode];
                    }

                    if (mbTarget == 0 && mbIdx >= 0 && mbIdx < MOUSE_REMAP_COUNT) {
                        GCKeyCode custom = mouseButtonRemapArray[mbIdx];
                        if (custom == (GCKeyCode)-1) return nil;
                        if (custom != 0) mbTarget = custom;
                        else mbTarget = mouseFortniteArray[mbIdx];
                    }

                    if (mbTarget != 0) {
                        if (isPressed) {
                            if (isMouseLocked) {
                                _sendDualKeyEvent(mbTarget, YES);
                                remappedMouseButtonsState[mbIdx] = YES;
                            }
                        } else {
                            if (remappedMouseButtonsState[mbIdx]) {
                                _sendDualKeyEvent(mbTarget, NO);
                                remappedMouseButtonsState[mbIdx] = NO;
                            }
                        }
                        return nil;
                    }
                }

                if (_isMouseButtonSuppressed(currentBtnCode) && !isPopupVisible) {

                    if (isTriggerHeld) {
                        static SEL setFlagsSel = NULL;
                        if (!setFlagsSel) setFlagsSel = NSSelectorFromString(@"_setModifierFlags:");
                        if (!setFlagsSel) setFlagsSel = NSSelectorFromString(@"setModifierFlags:");
                        NSUInteger currentFlags = ((NSUInteger(*)(id,SEL))objc_msgSend)(event, modFlagsSel2);
                        NSUInteger clearFlags = currentFlags & ~0x80000;
                        if ([event respondsToSelector:setFlagsSel]) {
                            ((void(*)(id,SEL,NSUInteger))objc_msgSend)(event, setFlagsSel, clearFlags);
                        }
                        return event;
                    }
                    return nil;
                }

                return event;
            }

            if (evType == 12) {

                unsigned short modVK = ((unsigned short(*)(id,SEL))objc_msgSend)(event, keyCodeSel2);
                GCKeyCode modGC = 0;
                if (modVK == 56) modGC = 225;
                else if (modVK == 60) modGC = 229;
                else if (modVK == 55) modGC = 227;
                else if (modVK == 54) modGC = 231;
                else if (modVK == 57) modGC = 57;
                else if (modVK == 59) modGC = 224;
                else if (modVK == 62) modGC = 228;
                else if (modVK == 58) modGC = 226;
                else if (modVK == 61) modGC = 230;

                if (keyCaptureCallback != nil && modGC != 0) {
                    keyCaptureCallback(modGC);
                    return nil;
                }

                NSUInteger modFlags = ((NSUInteger(*)(id,SEL))objc_msgSend)(event, modFlagsSel2);
                BOOL modPressed = NO;

                static NSUInteger prevModFlags = 0;
                NSUInteger relevantBit = 0;
                if (modVK == 56 || modVK == 60) relevantBit = 0x20000;
                else if (modVK == 55 || modVK == 54) relevantBit = 0x100000;
                else if (modVK == 59 || modVK == 62) relevantBit = 0x40000;
                else if (modVK == 57) relevantBit = 0x10000;
                else if (modVK == 58 || modVK == 61) relevantBit = 0x80000;
                if (relevantBit != 0) {
                    BOOL wasPressed = (prevModFlags & relevantBit) != 0;
                    modPressed = (modFlags & relevantBit) != 0;
                    prevModFlags = (modFlags & ~0x80000);
                    if (modPressed == wasPressed && modGC != 57) {

                        goto fnm_option_check;
                    }
                }

                if (modGC != 0 && !isPopupVisible) {

                    if (isControllerModeEnabled && (isMouseLocked || isTriggerHeld || !modPressed)) {
                        BOOL handled = NO;
                        for (int i = 0; i < FnCtrlButtonCount; i++) {
                            if (controllerMappingArray[i] == (int)modGC) {
                                dispatchControllerButton(i, modPressed);
                                handled = YES;
                            }
                        }
                        NSSet *tgts = vctrlCookedRemappings[@((int)modGC)];
                        for (NSNumber *tgt in tgts) {
                            dispatchControllerButton([tgt intValue], modPressed);
                            handled = YES;
                        }
                        if (handled) return nil;
                    }

                    if (modGC < 512) {

                        GCKeyCode customTarget = keyRemapArray[modGC];
                        GCKeyCode fnTarget = (modGC < 512) ? fortniteRemapArray[modGC] : 0;
                        GCKeyCode target = (customTarget != 0 && customTarget != (GCKeyCode)-1) ? customTarget
                                         : (fnTarget != 0) ? fnTarget : 0;

                        if (target > 0 && target < 256) {
                            if (modGC == 57) {

                                _sendDualKeyEvent(target, YES);
                                _sendDualKeyEvent(target, NO);
                                return nil;
                            }

                            uint16_t remappedVK = gcToNSVK[(uint8_t)target];

                            if ((remappedVK > 0 || target == 4) && _CGEventCreateKeyboardEvent && _CGEventPost) {
                                CGEventRef ev = _CGEventCreateKeyboardEvent(NULL, remappedVK, (bool)modPressed);
                                if (ev) {
                                    _CGEventSetIntegerValueField(ev, kCGEventSourceUserData, 0x1337);
                                    _CGEventPost(kCGHIDEventTap, ev);
                                    CFRelease(ev);
                                }
                            }
                            if (storedKeyboardHandler && storedKeyboardInput) {
                                GCControllerButtonInput *b = [storedKeyboardInput buttonForKeyCode:target];
                                if (b) storedKeyboardHandler(storedKeyboardInput, b, target, modPressed);
                            }
                            return nil;
                        }
                    }
                }

                fnm_option_check:;
                NSUInteger flags = modFlags;
                BOOL optNow = (flags & 0x80000) != 0;
                if (optNow == prevOptionHeld2) return event;
                prevOptionHeld2 = optNow;

                if (isPopupVisible) return event;

                if (optNow) {
                    isTriggerHeld = YES;
                    if (isMouseLocked) {

                        if (!blueDotIndicator) createBlueDotIndicator();
                        UIWindowScene *_wsc = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
                        UIWindow *_kw = _wsc ? (_wsc.keyWindow ?: _wsc.windows.firstObject) : nil;
                        CGFloat _winX = _kw ? _kw.frame.origin.x : 0;
                        CGFloat _winY = _kw ? _kw.frame.origin.y : 0;
                        CGPoint warpPt = CGPointMake(blueDotPosition.x + _winX, blueDotPosition.y + _winY);
                        isMouseLocked = NO;
                        updateMouseLock(NO, warpPt);

                        reassertAllInputs();
                    }
                } else {
                    isTriggerHeld = NO;
                    if (!isMouseLocked) {

                        isMouseLocked = YES;
                        updateMouseLock(YES, CGPointZero);
                    }
                }
                return event;
            }

            BOOL pressed = (evType == 10);

            if (pressed) {
                SEL repeatSel = NSSelectorFromString(@"isARepeat");
                if ([event respondsToSelector:repeatSel]) {

                }
            }

            unsigned short nsVK = ((unsigned short(*)(id,SEL))objc_msgSend)(event, keyCodeSel2);
            if (nsVK >= 128) return event;

            GCKeyCode gck = nsVKToGC[nsVK];
            if (gck != 0 && gck == GCMOUSE_DIRECT_KEY) {
                updateGCMouseDirectState((int)gck, pressed);

            }

            if (pressed && nsVK == 37) {
                if (isPopupVisible) return event;
                isMouseLocked = !isMouseLocked;
                if (!isMouseLocked) {
                    UIWindowScene *_sc = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
                    CGRect _sb = _sc ? _sc.screen.bounds : CGRectMake(0, 0, 1920, 1080);
                    CGPoint _center = CGPointMake(_sb.size.width / 2.0, _sb.size.height / 2.0);
                    updateMouseLock(NO, _center);
                    resetControllerState();
                } else {
                    updateMouseLock(YES, CGPointZero);
                }
                return nil;
            }

            if (nsVK == 35) {
                if (pressed) {
                    if (!popupWindow) createPopup();
                    if (isPopupVisible) {
                        popupViewController *vc = (popupViewController *)popupWindow.rootViewController;
                        if ([vc respondsToSelector:@selector(closeButtonTapped)])
                            [vc performSelector:@selector(closeButtonTapped)];
                        else { isPopupVisible = NO; popupWindow.hidden = YES; updateBlueDotVisibility(); }
                    } else {
                        isPopupVisible = YES;
                        popupWindow.hidden = NO;
                        [popupWindow makeKeyAndVisible];
                    }
                    isMouseLocked = NO;
                    updateMouseLock(NO, CGPointZero);
                    resetControllerState();
                }
                return nil;
            }

            GCKeyCode keyCode = nsVKToGC[nsVK];
            if (keyCode == 0) return event;

            BOOL isRemappedElsewhere = NO;
            for (int i = 0; i < FnCtrlButtonCount; i++) {
                if (controllerMappingArray[i] == (int)keyCode) {
                    isRemappedElsewhere = YES;
                    break;
                }
            }

            if (isControllerModeEnabled && (isMouseLocked || isTriggerHeld || !pressed) && !isPopupVisible && keyCaptureCallback == nil) {
                BOOL handled = NO;
                for (int i = 0; i < FnCtrlButtonCount; i++) {
                    if (controllerMappingArray[i] == (int)keyCode) {
                        dispatchControllerButton(i, pressed);
                        handled = YES;
                    }
                }
                NSSet *tgts = vctrlCookedRemappings[@((int)keyCode)];
                for (NSNumber *tgt in tgts) {
                    dispatchControllerButton([tgt intValue], pressed);
                    handled = YES;
                }
                if (handled) return nil;
            }

            if (!isPopupVisible && keyCaptureCallback == nil) {
                GCKeyCode target = 0;
                GCKeyCode customTarget = (keyCode < 512) ? keyRemapArray[keyCode] : 0;
                if (customTarget == (GCKeyCode)-1) return nil;
                if (customTarget != 0) {
                    target = customTarget;
                } else if (keyCode < 512) {
                    GCKeyCode fnTarget = fortniteRemapArray[keyCode];
                    if (fnTarget != 0) {
                        target = fnTarget;
                    } else if (fortniteBlockedDefaults[keyCode] != 0 || isRemappedElsewhere) {
                        return nil;
                    }
                }

                if (target > 0 && target < 256) {
                    if (pressed) {
                        if (isMouseLocked) {
                            _sendDualKeyEvent(target, YES);
                            remappedKeysState[keyCode] = YES;
                            return nil;
                        }
                    } else {

                        if (remappedKeysState[keyCode]) {
                            _sendDualKeyEvent(target, NO);
                            remappedKeysState[keyCode] = NO;
                            return nil;
                        }
                    }
                }
            }

            if (keyCode == TRIGGER_KEY) {
                if (keyCaptureCallback != nil && pressed) {
                    keyCaptureCallback(keyCode);
                    return nil;
                }
                if (keyCaptureCallback == nil) {

                    if (keyRemapArray[keyCode] == 0 && fortniteRemapArray[keyCode] == 0) return event;
                    return nil;
                }
            }

            if (keyCaptureCallback != nil && pressed) {
                keyCaptureCallback(keyCode);
                return nil;
            }

            if (keyCaptureCallback != nil && !pressed) {
                return nil;
            }

            return event;
        };

        if ([nsEventClass respondsToSelector:addMonitorSel]) {
            NSInvocation *kbInv = [NSInvocation invocationWithMethodSignature:
                [nsEventClass methodSignatureForSelector:addMonitorSel]];
            [kbInv setSelector:addMonitorSel];
            [kbInv setTarget:nsEventClass];
            [kbInv setArgument:&keyMask atIndex:2];
            id kbBlock = [kbMonitor copy];
            [kbInv setArgument:&kbBlock atIndex:3];
            [kbInv invoke];
            fnlog("NSEvent local monitor installed  (keyboard + scroll taps)");
        }
    }

    fnlog("init done");
}

static inline CGFloat PixelAlign(CGFloat value) {
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
    CGFloat scale = scene.screen.scale ?: 2.0;
    return round(value * scale) / scale;
}

static void createPopup() {
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication] connectedScenes].anyObject;
    popupWindow = [[UIWindow alloc] initWithWindowScene:scene];

    CGFloat popupW = PixelAlign(330.0);
    CGFloat popupH = PixelAlign(600.0);
    CGRect screen = scene ? scene.screen.bounds : CGRectMake(0, 0, 390, 844);
    CGFloat centeredY = PixelAlign((screen.size.height - popupH) / 2.0);

    popupWindow.frame = CGRectMake(PixelAlign(100.0), centeredY, popupW, popupH);
    popupWindow.windowLevel = UIWindowLevelAlert + 1;
    popupWindow.backgroundColor = [UIColor clearColor];

    popupViewController *popupVC = [popupViewController new];
    popupWindow.rootViewController = popupVC;
}

void showPopupOnQuickStartTab(void) {
    if (!popupWindow) createPopup();
    isPopupVisible = YES;
    popupWindow.hidden = NO;
    popupViewController *vc = (popupViewController *)popupWindow.rootViewController;
    if ([vc respondsToSelector:@selector(switchToQuickStartTab)]) {
        [vc switchToQuickStartTab];
    }
}

void createBlueDotIndicator() {
    if (blueDotIndicator) return;

    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication] connectedScenes].anyObject;
    if (!scene) return;

    blueDotIndicator = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
    blueDotIndicator.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.9];
    blueDotIndicator.layer.cornerRadius = 10;
    blueDotIndicator.layer.borderWidth = 2;
    blueDotIndicator.layer.borderColor = [UIColor whiteColor].CGColor;
    blueDotIndicator.hidden = YES;
    blueDotIndicator.userInteractionEnabled = YES;

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:blueDotIndicator action:nil];
    __weak UIView *weakDot = blueDotIndicator;
    [panGesture addTarget:weakDot action:@selector(handleBluePan:)];
    [blueDotIndicator addGestureRecognizer:panGesture];

    UIWindow *gameWindow = nil;
    for (UIWindow *w in scene.windows) {
        if (w != popupWindow) { gameWindow = w; break; }
    }

    if (gameWindow) {
        [gameWindow addSubview:blueDotIndicator];

        CGRect screenBounds = gameWindow.bounds;
        NSDictionary *savedPosition = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kBlueDotPositionKey];

        if (savedPosition) {
            CGFloat x = [savedPosition[@"x"] floatValue];
            CGFloat y = [savedPosition[@"y"] floatValue];
            x = MAX(10, MIN(screenBounds.size.width - 10, x));
            y = MAX(10, MIN(screenBounds.size.height - 10, y));
            blueDotPosition = CGPointMake(x, y);
        } else {

            blueDotPosition = CGPointMake(screenBounds.size.width * 0.875, screenBounds.size.height * 0.875);
        }

        blueDotIndicator.center = blueDotPosition;
    }
}

void resetBlueDotPosition(void) {
    if (!blueDotIndicator) createBlueDotIndicator();

    if (blueDotIndicator && blueDotIndicator.superview) {
        CGRect screenBounds = blueDotIndicator.superview.bounds;
        CGPoint defaultPosition = CGPointMake(screenBounds.size.width * 0.875, screenBounds.size.height * 0.875);
        blueDotPosition = defaultPosition;
        blueDotIndicator.center = defaultPosition;

        NSDictionary *positionDict = @{@"x": @(defaultPosition.x), @"y": @(defaultPosition.y)};
        [[NSUserDefaults standardUserDefaults] setObject:positionDict forKey:kBlueDotPositionKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

void updateBlueDotVisibility(void) {
    if (!blueDotIndicator) createBlueDotIndicator();
    blueDotIndicator.hidden = !isPopupVisible;
}

static BOOL leftClickSentToGame  = NO;
static GCControllerButtonValueChangedHandler leftButtonGameHandler = nil;
static GCControllerButtonValueChangedHandler leftButtonRawHandler  = nil;
static GCControllerButtonInput *leftButtonInput = nil;

static UIView  *lastCheckedView     = nil;
static BOOL     lastViewWasUIElement = NO;
static UIWindow *cachedKeyWindow    = nil;

typedef CGError (*CGAssociateMouseAndMouseCursorPosition_t)(boolean_t connected);
static CGAssociateMouseAndMouseCursorPosition_t fnCGAssociateMouse = NULL;

typedef CGError (*CGWarpMouseCursorPosition_t)(CGPoint newCursorPosition);
static CGWarpMouseCursorPosition_t fnCGWarpMouse = NULL;

void clearAllControllerButtons() {

    for (int i = 0; i < FnCtrlButtonCount; i++) {
        dispatchControllerButton(i, NO);
    }
}

static void updateMouseLock(BOOL value, CGPoint warpPos) {
    UIWindowScene *scene = (UIWindowScene *)[[[UIApplication sharedApplication].connectedScenes allObjects] firstObject];
    if (!scene) return;

    for (UIWindow *window in scene.windows) {
        UIViewController *root = window.rootViewController;
        if ([root respondsToSelector:NSSelectorFromString(@"setNeedsUpdateOfPrefersPointerLocked")]) {
            ((void (*)(id, SEL))objc_msgSend)(root, NSSelectorFromString(@"setNeedsUpdateOfPrefersPointerLocked"));
        }
    }

    if (value) {
        Class nsCursorClass = NSClassFromString(@"NSCursor");
        if (nsCursorClass) {
            ((void(*)(Class,SEL))objc_msgSend)(nsCursorClass, NSSelectorFromString(@"hide"));
        }

        if (!fnCGAssociateMouse)
            fnCGAssociateMouse = (CGAssociateMouseAndMouseCursorPosition_t)dlsym(RTLD_DEFAULT, "CGAssociateMouseAndMouseCursorPosition");
        if (fnCGAssociateMouse) fnCGAssociateMouse(0);

        BOOL hadGCPress = leftClickSentToGame;
        GCControllerButtonValueChangedHandler gcHandler = leftButtonGameHandler;
        GCControllerButtonInput *gcInput = leftButtonInput;

        leftButtonIsPressed  = NO;
        leftClickSentToGame  = NO;
        lastCheckedView      = nil;
        lastViewWasUIElement = NO;

        void (^cancelBlock)(void) = ^{
            UIApplication *app = [UIApplication sharedApplication];
            static IMP cancelAllTouchesIMP = NULL;
            if (!cancelAllTouchesIMP)
                cancelAllTouchesIMP = [app methodForSelector:@selector(_cancelAllTouches)];
            if (cancelAllTouchesIMP)
                ((void (*)(id, SEL))cancelAllTouchesIMP)(app, @selector(_cancelAllTouches));
            if (hadGCPress && gcHandler && gcInput)
                gcHandler(gcInput, 0.0, NO);
        };
        if ([NSThread isMainThread]) cancelBlock();
        else dispatch_sync(dispatch_get_main_queue(), cancelBlock);
    } else {

        if (!fnCGAssociateMouse)
            fnCGAssociateMouse = (CGAssociateMouseAndMouseCursorPosition_t)dlsym(RTLD_DEFAULT, "CGAssociateMouseAndMouseCursorPosition");
        if (fnCGAssociateMouse) fnCGAssociateMouse(1);

        if (warpPos.x > 0 || warpPos.y > 0) {
            if (fnCGAssociateMouse) fnCGAssociateMouse(0);
            if (!fnCGWarpMouse)
                fnCGWarpMouse = (CGWarpMouseCursorPosition_t)dlsym(RTLD_DEFAULT, "CGWarpMouseCursorPosition");
            if (fnCGWarpMouse) fnCGWarpMouse(warpPos);
            if (fnCGAssociateMouse) fnCGAssociateMouse(1);
        }

        Class nsCursorClass = NSClassFromString(@"NSCursor");
        if (nsCursorClass) {
            ((void(*)(Class,SEL))objc_msgSend)(nsCursorClass, NSSelectorFromString(@"unhide"));
        }

        if (!isTriggerHeld) {
            for (int i = 0; i < 512; i++) {
                if (remappedKeysState[i]) {
                    GCKeyCode target = 0;
                    GCKeyCode customTarget = keyRemapArray[i];
                    if (customTarget != 0 && customTarget != (GCKeyCode)-1) {
                        target = customTarget;
                    } else {
                        target = fortniteRemapArray[i];
                    }

                    if (target > 0 && target < 256) {
                        uint16_t remappedVK = gcToNSVK[(uint8_t)target];
                        if ((remappedVK > 0 || target == 4) && _CGEventCreateKeyboardEvent && _CGEventPost) {
                            CGEventRef ev = _CGEventCreateKeyboardEvent(NULL, remappedVK, false);
                            if (ev) {
                                _CGEventSetIntegerValueField(ev, kCGEventSourceUserData, 0x1337);
                                _CGEventPost(kCGHIDEventTap, ev);
                                CFRelease(ev);
                            }
                        }
                    }
                    remappedKeysState[i] = NO;
                }
            }
            for (int i = 0; i < FnCtrlButtonCount; i++) {
                dispatchControllerButton(i, NO);
            }
        }

        if (isPopupVisible) {
            clearAllControllerButtons();
            wasADSInitialized = NO;

            GCControllerButtonValueChangedHandler gcHandler = leftButtonGameHandler;
            GCControllerButtonInput *gcInput = leftButtonInput;
            BOOL hadUITouch = leftButtonIsPressed;
            BOOL hadGCPress = leftClickSentToGame;

            leftButtonIsPressed  = NO;
            rightButtonIsPressed = NO;
            leftClickSentToGame  = NO;
            leftButtonRawHandler = nil;
            cachedKeyWindow      = nil;
            lastCheckedView      = nil;
            lastViewWasUIElement = NO;

            if (hadUITouch || hadGCPress) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIApplication *app = [UIApplication sharedApplication];
                    static IMP cancelAllTouchesIMP = NULL;
                    if (!cancelAllTouchesIMP)
                        cancelAllTouchesIMP = [app methodForSelector:@selector(_cancelAllTouches)];
                    if (cancelAllTouchesIMP)
                        ((void (*)(id, SEL))cancelAllTouchesIMP)(app, @selector(_cancelAllTouches));
                    if (hadGCPress && gcHandler && gcInput)
                        gcHandler(gcInput, 0.0, NO);
                });
            }
        }
    }

    if (!value) isGCMouseDirectActive = NO;
    updateBlueDotVisibility();
}

typedef id (*GCExtGP_stick_IMP)(id, SEL);
static GCExtGP_stick_IMP orig_GCExtGP_leftThumbstickButton;
static GCExtGP_stick_IMP orig_GCExtGP__leftThumbstickButton;
static GCExtGP_stick_IMP orig_GCExtGP_rightThumbstickButton;
static GCExtGP_stick_IMP orig_GCExtGP__rightThumbstickButton;

static id swz_GCExtGP_leftThumbstickButton(id self, SEL _cmd) {
    id val = orig_GCExtGP_leftThumbstickButton
        ? orig_GCExtGP_leftThumbstickButton(self, _cmd) : nil;
    if (val) return val;
    return getInjectedButton(self, @"leftThumbstickButton");
}
static id swz_GCExtGP__leftThumbstickButton(id self, SEL _cmd) {
    if ([self respondsToSelector:@selector(leftThumbstickButton)])
        return [self leftThumbstickButton];
    return getInjectedButton(self, @"leftThumbstickButton");
}
static id swz_GCExtGP_rightThumbstickButton(id self, SEL _cmd) {
    id val = orig_GCExtGP_rightThumbstickButton
        ? orig_GCExtGP_rightThumbstickButton(self, _cmd) : nil;
    if (val) return val;
    return getInjectedButton(self, @"rightThumbstickButton");
}
static id swz_GCExtGP__rightThumbstickButton(id self, SEL _cmd) {
    if ([self respondsToSelector:@selector(rightThumbstickButton)])
        return [self rightThumbstickButton];
    return getInjectedButton(self, @"rightThumbstickButton");
}

typedef NSString *(*GCCtrl_string_IMP)(id, SEL);
static GCCtrl_string_IMP orig_GCCtrl_productCategory;
static GCCtrl_string_IMP orig_GCCtrl_vendorName;

static NSString *swz_GCCtrl_productCategory(id self, SEL _cmd) {
    GCVirtualController *vc = (GCVirtualController *)g_virtualController;
    if (vc && self == vc.controller) return @"DualSense";
    return orig_GCCtrl_productCategory
        ? orig_GCCtrl_productCategory(self, _cmd) : nil;
}
static NSString *swz_GCCtrl_vendorName(id self, SEL _cmd) {
    GCVirtualController *vc = (GCVirtualController *)g_virtualController;
    if (vc && self == vc.controller) return @"DualSense Wireless Controller";
    return orig_GCCtrl_vendorName
        ? orig_GCCtrl_vendorName(self, _cmd) : nil;
}

typedef void (*NSWindow_makeKey_IMP)(id, SEL, id);
static NSWindow_makeKey_IMP orig_NSWindow_makeKeyAndOrderFront;

static void swz_NSWindow_makeKeyAndOrderFront(id self, SEL _cmd, id sender) {
    if (isBorderlessModeEnabled) {
        id win = self;
        NSUInteger currentMask = [[win valueForKey:@"styleMask"] unsignedIntegerValue];
        NSUInteger fullSizeMask = (1ULL << 15);
        [win setValue:@(currentMask | fullSizeMask) forKey:@"styleMask"];
        [win setValue:@YES forKey:@"titlebarAppearsTransparent"];
        [win setValue:@(1) forKey:@"titleVisibility"];

        SEL buttonSel = NSSelectorFromString(@"standardWindowButton:");
        typedef id (*ButtonFunc)(id, SEL, NSInteger);
        for (NSInteger i = 0; i <= 2; i++) {
            id btn = ((ButtonFunc)objc_msgSend)(win, buttonSel, i);
            if (btn) [btn setValue:@YES forKey:@"hidden"];
        }
        id closeBtn = ((ButtonFunc)objc_msgSend)(win, buttonSel, 0);
        if (closeBtn) {
            id container = [closeBtn valueForKey:@"superview"];
            if (container) [container setValue:@YES forKey:@"hidden"];
        }
    }
    if (orig_NSWindow_makeKeyAndOrderFront)
        orig_NSWindow_makeKeyAndOrderFront(self, _cmd, sender);
}

typedef void (*GCMouseInput_setMoved_IMP)(id, SEL, GCMouseMoved);
static GCMouseInput_setMoved_IMP orig_GCMouseInput_setMouseMovedHandler;

static void swz_GCMouseInput_setMouseMovedHandler(id self, SEL _cmd, GCMouseMoved handler) {
    GCMouseInput *mouseSelf = (GCMouseInput *)self;
    if (!handler) {
        if (orig_GCMouseInput_setMouseMovedHandler)
            orig_GCMouseInput_setMouseMovedHandler(self, _cmd, handler);
        return;
    }
    g_originalMouseHandler = [handler copy];
    g_capturedMouseInput = mouseSelf;
    if (mouseSelf.leftButton) objc_setAssociatedObject(mouseSelf.leftButton, &kButtonCodeKey, @(MOUSE_BUTTON_LEFT), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (mouseSelf.rightButton) objc_setAssociatedObject(mouseSelf.rightButton, &kButtonCodeKey, @(MOUSE_BUTTON_RIGHT), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (mouseSelf.middleButton) objc_setAssociatedObject(mouseSelf.middleButton, &kButtonCodeKey, @(MOUSE_BUTTON_MIDDLE), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSArray<GCControllerButtonInput *> *aux = mouseSelf.auxiliaryButtons;
    for (NSInteger i = 0; i < (NSInteger)aux.count; i++) {
        if (aux[i]) objc_setAssociatedObject(aux[i], &kButtonCodeKey, @(MOUSE_BUTTON_AUX_BASE + i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    GCMouse *currentMouse = GCMouse.current;
    if (currentMouse && currentMouse.handlerQueue != dispatch_get_main_queue())
        currentMouse.handlerQueue = dispatch_get_main_queue();
    GCMouseMoved customHandler = [^(GCMouseInput *eventMouse, float deltaX, float deltaY) {
        if (isMouseLocked) {
            mouseAccumX += (double)deltaX;
            mouseAccumY += (double)deltaY;
        }
        if (isGCMouseDirectActive) {
            handler(eventMouse, deltaX, deltaY);
        }
    } copy];
    if (orig_GCMouseInput_setMouseMovedHandler)
        orig_GCMouseInput_setMouseMovedHandler(self, _cmd, customHandler);
}

typedef void (*DPad_setHandler_IMP)(id, SEL, void (^)(GCControllerDirectionPad *, float, float));
static DPad_setHandler_IMP orig_DPad_setValueChangedHandler;

static void swz_DPad_setValueChangedHandler(id self, SEL _cmd,
    void (^handler)(GCControllerDirectionPad *, float, float)) {
    GCControllerDirectionPad *dpadSelf = (GCControllerDirectionPad *)self;
    GCMouse *currentMouse = GCMouse.current;
    BOOL isScrollPad = NO;
    if (currentMouse && currentMouse.mouseInput) {
        GCMouseInput *mouseInput = currentMouse.mouseInput;
        if ([mouseInput respondsToSelector:@selector(scroll)]) {
            isScrollPad = ([mouseInput scroll] == dpadSelf);
        } else {
            isScrollPad = (dpadSelf.xAxis != nil && dpadSelf.yAxis != nil &&
                           dpadSelf.up == nil && dpadSelf.down == nil &&
                           dpadSelf.left == nil && dpadSelf.right == nil);
        }
    }

    if (!isScrollPad || !handler) {
        if (orig_DPad_setValueChangedHandler)
            orig_DPad_setValueChangedHandler(self, _cmd, handler);
        return;
    }

    void (^wrappedHandler)(GCControllerDirectionPad *, float, float) =
        ^(GCControllerDirectionPad *pad, float xValue, float yValue) {

            if (!isMouseLocked) return;

            int scrollCode = (yValue > 0) ? MOUSE_SCROLL_UP : (yValue < 0 ? MOUSE_SCROLL_DOWN : 0);
            if (scrollCode != 0) {
                int idx = scrollCode - MOUSE_SCROLL_UP;

                if (mouseScrollRemapArray[idx] != 0 ||
                    mouseScrollFortniteArray[idx] != 0 ||
                    fortniteRemapArray[scrollCode] != 0) return;

                if (isControllerModeEnabled) {
                    for (int i = 0; i < FnCtrlButtonCount; i++) {
                        if (controllerMappingArray[i] == scrollCode) return;
                    }
                }
            }

            handler(pad, xValue, yValue);
        };
    if (orig_DPad_setValueChangedHandler)
        orig_DPad_setValueChangedHandler(self, _cmd, wrappedHandler);

    if ([dpadSelf.yAxis respondsToSelector:@selector(setValue:)]) {
        [dpadSelf.yAxis setValue:0.0f];
    }
}

static BOOL _isMouseButtonSuppressed(int code) {

    if (code >= 0 && code < 10200 && fortniteRemapArray[code] != 0) return YES;

    if (code >= 0 && code < 512 && keyRemapArray[code] != 0) return YES;

    if (code >= 0 && code < 10200 && keyRemapArray[code % 512] != 0) {

    }

    int mbIdx = code - MOUSE_BUTTON_MIDDLE;
    if (mbIdx >= 0 && mbIdx < MOUSE_REMAP_COUNT) {
        if (mouseButtonRemapArray[mbIdx] != 0) return YES;
        if (mouseFortniteArray[mbIdx] != 0) return YES;
    }

    if (isControllerModeEnabled) {

        for (int i = 0; i < FnCtrlButtonCount; i++) {
            if (controllerMappingArray[i] == code) return YES;
        }
    }

    if (code == MOUSE_BUTTON_LEFT || code == MOUSE_BUTTON_RIGHT || code == MOUSE_BUTTON_MIDDLE) {
        if (isGCMouseDirectActive) return YES;
    }

    if (code != 0 && (GCKeyCode)code == GCMOUSE_DIRECT_KEY) return YES;

    return NO;
}

static CGEventRef mouseButtonTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {

    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        return event;
    }

    if (type == 10 || type == 11 || type == 12) {
        if (_CGEventGetFlags && _CGEventSetFlags) {
            CGEventFlags flags = _CGEventGetFlags(event);

            if (keyCaptureCallback != nil) {
                int64_t vk = _CGEventGetIntegerValueField ? _CGEventGetIntegerValueField(event, 9) : 0;
                if (type == 10) {
                    keyCaptureCallback(nsVKToGC[vk]);
                }
                return NULL;
            }

            int64_t vk = _CGEventGetIntegerValueField ? _CGEventGetIntegerValueField(event, 9) : 0;
            if (type == 12 && vk == 57) {
                isTypingModeEnabled = (flags & kCGEventFlagMaskAlphaShift) != 0;
                return NULL;
            }

            if (flags & kCGEventFlagMaskAlphaShift) {
                _CGEventSetFlags(event, flags & ~kCGEventFlagMaskAlphaShift);

                if (type == 10 && !(flags & kCGEventFlagMaskShift) && _CGEventKeyboardGetUnicodeString && _CGEventKeyboardSetUnicodeString) {
                    UniChar unicodeChars[4];
                    UniCharCount actualLen = 0;
                    _CGEventKeyboardGetUnicodeString(event, 4, &actualLen, unicodeChars);
                    if (actualLen > 0) {
                        BOOL changed = NO;
                        for (int i = 0; i < (int)actualLen; i++) {
                            if (unicodeChars[i] >= 'A' && unicodeChars[i] <= 'Z') {
                                unicodeChars[i] += ('a' - 'A');
                                changed = YES;
                            }
                        }
                        if (changed) {
                            _CGEventKeyboardSetUnicodeString(event, actualLen, unicodeChars);
                        }
                    }
                }
            }
        }
    }

    if (isTypingModeEnabled) return event;

    if (type == kCGEventLeftMouseDown || type == kCGEventLeftMouseUp || type == kCGEventLeftMouseDragged ||
        type == kCGEventRightMouseDown || type == kCGEventRightMouseUp || type == kCGEventRightMouseDragged ||
        type == kCGEventOtherMouseDown || type == kCGEventOtherMouseUp || type == kCGEventOtherMouseDragged) {

        int currentBtnCode = 0;
        if (type == kCGEventLeftMouseDown || type == kCGEventLeftMouseUp || type == kCGEventLeftMouseDragged) {
            currentBtnCode = MOUSE_BUTTON_LEFT;
        } else if (type == kCGEventRightMouseDown || type == kCGEventRightMouseUp || type == kCGEventRightMouseDragged) {
            currentBtnCode = MOUSE_BUTTON_RIGHT;
        } else {
            int64_t btnNum = _CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
            currentBtnCode = (int)(MOUSE_BUTTON_AUX_BASE + (btnNum - 3));
        }

        BOOL isPressed = (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown || type == kCGEventOtherMouseDown ||
                          type == kCGEventLeftMouseDragged || type == kCGEventRightMouseDragged || type == kCGEventOtherMouseDragged);

        if (!isPopupVisible) {

            if (currentBtnCode != 0 && (GCKeyCode)currentBtnCode == GCMOUSE_DIRECT_KEY) {
                updateGCMouseDirectState(currentBtnCode, isPressed);
            }

            int mbIdx = currentBtnCode - MOUSE_BUTTON_MIDDLE;
            GCKeyCode mbTarget = 0;
            if (currentBtnCode >= 0 && currentBtnCode < 10200) {
                 mbTarget = fortniteRemapArray[currentBtnCode];
            }
            if (mbTarget == 0 && mbIdx >= 0 && mbIdx < MOUSE_REMAP_COUNT) {
                 mbTarget = mouseButtonRemapArray[mbIdx];
                 if (mbTarget == 0) mbTarget = mouseFortniteArray[mbIdx];
            }
            if (mbTarget == 0 && currentBtnCode >= 0 && currentBtnCode < 512) {
                 mbTarget = keyRemapArray[currentBtnCode];
            }

            if (mbTarget == 0 && currentBtnCode >= 0 && currentBtnCode < 10200) {
                 mbTarget = keyRemapArray[currentBtnCode % 512];
            }

            if (mbTarget != 0) {
                static BOOL tapRemapState[64] = {NO};
                int tapIdx = (currentBtnCode == MOUSE_BUTTON_LEFT) ? 60 :
                             (currentBtnCode == MOUSE_BUTTON_RIGHT) ? 61 :
                             (int)(currentBtnCode - MOUSE_BUTTON_MIDDLE);

                if (tapIdx >= 0 && tapIdx < 64) {
                    if (isPressed) {
                        if (isMouseLocked && !tapRemapState[tapIdx]) {
                            _sendDualKeyEvent(mbTarget, YES);
                            tapRemapState[tapIdx] = YES;
                        }
                    } else if (type == kCGEventLeftMouseUp || type == kCGEventRightMouseUp || type == kCGEventOtherMouseUp) {
                        if (tapRemapState[tapIdx]) {
                            _sendDualKeyEvent(mbTarget, NO);
                            tapRemapState[tapIdx] = NO;
                        }
                    }
                }
            }

            if (isControllerModeEnabled) {
                for (int i = 0; i < FnCtrlButtonCount; i++) {
                    if (controllerMappingArray[i] == currentBtnCode) {
                        if (isMouseLocked || !isPressed) {
                            dispatchControllerButton(i, isPressed);
                        }
                    }
                }
            }

            if (_isMouseButtonSuppressed(currentBtnCode)) {
                return NULL;
            }
        }
    }
    return event;
}

typedef void (*GCKbd_setHandler_IMP)(id, SEL, GCKeyboardValueChangedHandler);
static GCKbd_setHandler_IMP orig_GCKbd_setKeyChangedHandler;

static void swz_GCKbd_setKeyChangedHandler(id self, SEL _cmd, GCKeyboardValueChangedHandler handler) {
    if (!handler) {
        if (orig_GCKbd_setKeyChangedHandler)
            orig_GCKbd_setKeyChangedHandler(self, _cmd, handler);
        return;
    }

    storedKeyboardInput = (GCKeyboardInput *)self;
    storedKeyboardHandler = handler;

    GCKeyboardValueChangedHandler customHandler = ^(GCKeyboardInput * _Nonnull keyboard, GCControllerButtonInput * _Nonnull key, GCKeyCode keyCode, BOOL pressed) {

        if (keyCaptureCallback != nil && pressed) {
            keyCaptureCallback(keyCode);
            return;
        }

        if (isControllerModeEnabled && !isPopupVisible) {
            for (int i = 0; i < FnCtrlButtonCount; i++) {
                if (controllerMappingArray[i] == (int)keyCode) {
                    return;
                }
            }
        }

        GCKeyCode finalKey = keyCode;
        BOOL wasRemapped = NO;

        if (keyCode >= 0 && keyCode < 512) {

            GCKeyCode customRemap = keyRemapArray[keyCode];
            if (customRemap == (GCKeyCode)-1) {

                return;
            } else if (customRemap != 0) {

                finalKey = customRemap;
                wasRemapped = YES;
            } else {

                GCKeyCode fortniteRemap = fortniteRemapArray[keyCode];
                if (fortniteRemap != 0) {

                    finalKey = fortniteRemap;
                    wasRemapped = YES;
                } else {

                    if (fortniteBlockedDefaults[keyCode] != 0) {

                        return;
                    }
                }
            }
        }

        if (wasRemapped) {
            BOOL injected = NO;

            GCControllerButtonInput* remappedBtn = [keyboard buttonForKeyCode:finalKey];
            if (remappedBtn) {
                handler(keyboard, remappedBtn, finalKey, pressed);
                injected = YES;
            }

            if (!injected && finalKey < 256 && _CGEventCreateKeyboardEvent && _CGEventPost) {
                uint16_t targetVK = gcToNSVK[(uint8_t)finalKey];

                if (targetVK > 0 || finalKey == 4) {
                    CGEventRef ev = _CGEventCreateKeyboardEvent(NULL, targetVK, (bool)pressed);
                    if (ev) {
                        _CGEventSetIntegerValueField(ev, kCGEventSourceUserData, 0x1337); _CGEventPost(kCGHIDEventTap, ev);
                        CFRelease(ev);
                        injected = YES;
                    }
                }
            }

            return;
        }

        handler(keyboard, key, keyCode, pressed);
    };

    if (orig_GCKbd_setKeyChangedHandler)
        orig_GCKbd_setKeyChangedHandler(self, _cmd, customHandler);
}

typedef BOOL (*BoolGetter_IMP)(id, SEL);
static BoolGetter_IMP orig_IOSViewController_prefersPointerLocked;

static BOOL swz_IOSViewController_prefersPointerLocked(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return isMouseLocked;
}

typedef NSInteger (*NSIntegerGetter_IMP)(id, SEL);
static NSIntegerGetter_IMP orig_UIScreen_maximumFramesPerSecond;

static NSInteger swz_UIScreen_maximumFramesPerSecond(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return 120;
}

typedef UITouchType (*UITouch_type_IMP)(id, SEL);
static UITouch_type_IMP orig_UITouch_type;

static UITouchType swz_UITouch_type(id self, SEL _cmd) {
    UITouchType _original = orig_UITouch_type
        ? orig_UITouch_type(self, _cmd) : UITouchTypeDirect;

    if (_original != UITouchTypeIndirectPointer) return _original;

    if (!isMouseLocked) return UITouchTypeDirect;
    return _original;
}

typedef void (*UIWindow_sendEvent_IMP)(id, SEL, UIEvent *);
static UIWindow_sendEvent_IMP orig_UIWindow_sendEvent;

static void swz_UIWindow_sendEvent(id self, SEL _cmd, UIEvent *event) {
    if (isMouseLocked && event.type == 0) {
        NSSet *touches = [event allTouches];
        for (UITouch *touch in touches) {

            if ((int)touch.type == 3) {
                return;
            }
        }
    }
    if (orig_UIWindow_sendEvent)
        orig_UIWindow_sendEvent(self, _cmd, event);
}

typedef void  (*Btn_setBlockHandler_IMP)(id, SEL, GCControllerButtonValueChangedHandler);
typedef BOOL  (*Btn_BoolGetter_IMP)(id, SEL);
typedef float (*Btn_FloatGetter_IMP)(id, SEL);
typedef void  (*Btn_setFloat_IMP)(id, SEL, float);
typedef void  (*Btn_setBool_IMP)(id, SEL, BOOL);

static Btn_setBlockHandler_IMP orig_Btn_setPressedChangedHandler;
static Btn_setBlockHandler_IMP orig_Btn_setValueChangedHandler;
static Btn_BoolGetter_IMP      orig_Btn_isPressed;
static Btn_FloatGetter_IMP     orig_Btn_value;
static Btn_setFloat_IMP        orig_Btn_setValue;
static Btn_setBool_IMP         orig_Btn_setPressed;

static void swz_Btn_setPressedChangedHandler(id self, SEL _cmd,
        GCControllerButtonValueChangedHandler handler) {
    if (!handler) {
        if (orig_Btn_setPressedChangedHandler)
            orig_Btn_setPressedChangedHandler(self, _cmd, handler);
        return;
    }
    GCControllerButtonValueChangedHandler wrapper =
        ^(GCControllerButtonInput *btn, float val, BOOL pressed) {
            NSNumber *codeNum = objc_getAssociatedObject(btn, &kButtonCodeKey);
            if (codeNum && _isMouseButtonSuppressed([codeNum intValue])) return;
            handler(btn, val, pressed);
        };
    if (orig_Btn_setPressedChangedHandler)
        orig_Btn_setPressedChangedHandler(self, _cmd, wrapper);
}

static void swz_Btn_setValueChangedHandler(id self, SEL _cmd,
        GCControllerButtonValueChangedHandler handler) {
    if (!handler) {
        if (orig_Btn_setValueChangedHandler)
            orig_Btn_setValueChangedHandler(self, _cmd, handler);
        return;
    }
    GCControllerButtonValueChangedHandler wrapper =
        ^(GCControllerButtonInput *btn, float val, BOOL pressed) {
            NSNumber *codeNum = objc_getAssociatedObject(btn, &kButtonCodeKey);
            if (codeNum && _isMouseButtonSuppressed([codeNum intValue])) return;
            handler(btn, val, pressed);
        };
    if (orig_Btn_setValueChangedHandler)
        orig_Btn_setValueChangedHandler(self, _cmd, wrapper);
}

static BOOL swz_Btn_isPressed(id self, SEL _cmd) {
    NSNumber *codeNum = objc_getAssociatedObject(self, &kButtonCodeKey);
    if (codeNum) {
        int code = [codeNum intValue];

        if (_isMouseButtonSuppressed(code)) return NO;

        if (code == MOUSE_BUTTON_LEFT   && leftButtonIsPressed)   return NO;
        if (code == MOUSE_BUTTON_RIGHT  && rightButtonIsPressed)  return NO;
        if (code == MOUSE_BUTTON_MIDDLE && middleButtonIsPressed) return NO;
    }
    return orig_Btn_isPressed ? orig_Btn_isPressed(self, _cmd) : NO;
}

static float swz_Btn_value(id self, SEL _cmd) {
    NSNumber *codeNum = objc_getAssociatedObject(self, &kButtonCodeKey);
    if (codeNum) {
        int code = [codeNum intValue];
        if (_isMouseButtonSuppressed(code)) return 0.0f;
        if (code == MOUSE_BUTTON_LEFT   && leftButtonIsPressed)   return 0.0f;
        if (code == MOUSE_BUTTON_RIGHT  && rightButtonIsPressed)  return 0.0f;
        if (code == MOUSE_BUTTON_MIDDLE && middleButtonIsPressed) return 0.0f;
    }
    return orig_Btn_value ? orig_Btn_value(self, _cmd) : 0.0f;
}

static void swz_Btn_setValue(id self, SEL _cmd, float val) {
    NSNumber *codeNum = objc_getAssociatedObject(self, &kButtonCodeKey);
    if (codeNum && _isMouseButtonSuppressed([codeNum intValue])) {
        if (orig_Btn_setValue) orig_Btn_setValue(self, _cmd, 0.0f);
        return;
    }
    if (orig_Btn_setValue) orig_Btn_setValue(self, _cmd, val);
}

static void swz_Btn_setPressed(id self, SEL _cmd, BOOL pressed) {
    NSNumber *codeNum = objc_getAssociatedObject(self, &kButtonCodeKey);
    if (codeNum && _isMouseButtonSuppressed([codeNum intValue])) {
        if (orig_Btn_setPressed) orig_Btn_setPressed(self, _cmd, NO);
        return;
    }
    if (orig_Btn_setPressed) orig_Btn_setPressed(self, _cmd, pressed);
}

static BOOL swz_Btn_pressed(id self, SEL _cmd) {
    (void)_cmd;
    return swz_Btn_isPressed(self, @selector(isPressed));
}

static void fnmac_install_swizzles(void) {

    FNSwizzleInstance("GCExtendedGamepad", @selector(leftThumbstickButton),
                      (IMP)swz_GCExtGP_leftThumbstickButton,
                      (IMP *)&orig_GCExtGP_leftThumbstickButton);
    FNSwizzleInstance("GCExtendedGamepad", @selector(_leftThumbstickButton),
                      (IMP)swz_GCExtGP__leftThumbstickButton,
                      (IMP *)&orig_GCExtGP__leftThumbstickButton);
    FNSwizzleInstance("GCExtendedGamepad", @selector(rightThumbstickButton),
                      (IMP)swz_GCExtGP_rightThumbstickButton,
                      (IMP *)&orig_GCExtGP_rightThumbstickButton);
    FNSwizzleInstance("GCExtendedGamepad", @selector(_rightThumbstickButton),
                      (IMP)swz_GCExtGP__rightThumbstickButton,
                      (IMP *)&orig_GCExtGP__rightThumbstickButton);

    FNSwizzleInstance("GCController", @selector(productCategory),
                      (IMP)swz_GCCtrl_productCategory,
                      (IMP *)&orig_GCCtrl_productCategory);
    FNSwizzleInstance("GCController", @selector(vendorName),
                      (IMP)swz_GCCtrl_vendorName,
                      (IMP *)&orig_GCCtrl_vendorName);

    FNSwizzleInstance("NSWindow", @selector(makeKeyAndOrderFront:),
                      (IMP)swz_NSWindow_makeKeyAndOrderFront,
                      (IMP *)&orig_NSWindow_makeKeyAndOrderFront);

    FNSwizzleInstance("GCMouseInput", @selector(setMouseMovedHandler:),
                      (IMP)swz_GCMouseInput_setMouseMovedHandler,
                      (IMP *)&orig_GCMouseInput_setMouseMovedHandler);

    FNSwizzleInstance("GCControllerDirectionPad", @selector(setValueChangedHandler:),
                      (IMP)swz_DPad_setValueChangedHandler,
                      (IMP *)&orig_DPad_setValueChangedHandler);

    FNSwizzleInstance("GCKeyboardInput", @selector(setKeyChangedHandler:),
                      (IMP)swz_GCKbd_setKeyChangedHandler,
                      (IMP *)&orig_GCKbd_setKeyChangedHandler);

    FNSwizzleInstance("IOSViewController", @selector(prefersPointerLocked),
                      (IMP)swz_IOSViewController_prefersPointerLocked,
                      (IMP *)&orig_IOSViewController_prefersPointerLocked);

    FNSwizzleInstance("UIScreen", @selector(maximumFramesPerSecond),
                      (IMP)swz_UIScreen_maximumFramesPerSecond,
                      (IMP *)&orig_UIScreen_maximumFramesPerSecond);

    FNSwizzleInstance("UITouch", @selector(type),
                      (IMP)swz_UITouch_type,
                      (IMP *)&orig_UITouch_type);

    FNSwizzleInstance("UIWindow", @selector(sendEvent:),
                      (IMP)swz_UIWindow_sendEvent,
                      (IMP *)&orig_UIWindow_sendEvent);

    FNSwizzleInstance("GCControllerButtonInput", @selector(setPressedChangedHandler:),
                      (IMP)swz_Btn_setPressedChangedHandler,
                      (IMP *)&orig_Btn_setPressedChangedHandler);
    FNSwizzleInstance("GCControllerButtonInput", @selector(setValueChangedHandler:),
                      (IMP)swz_Btn_setValueChangedHandler,
                      (IMP *)&orig_Btn_setValueChangedHandler);
    FNSwizzleInstance("GCControllerButtonInput", @selector(isPressed),
                      (IMP)swz_Btn_isPressed,
                      (IMP *)&orig_Btn_isPressed);
    FNSwizzleInstance("GCControllerButtonInput", @selector(value),
                      (IMP)swz_Btn_value,
                      (IMP *)&orig_Btn_value);
    FNSwizzleInstance("GCControllerButtonInput", @selector(setValue:),
                      (IMP)swz_Btn_setValue,
                      (IMP *)&orig_Btn_setValue);
    FNSwizzleInstance("GCControllerButtonInput", @selector(setPressed:),
                      (IMP)swz_Btn_setPressed,
                      (IMP *)&orig_Btn_setPressed);
    FNSwizzleInstance("GCControllerButtonInput", @selector(pressed),
                      (IMP)swz_Btn_pressed,
                      NULL);

    fnlog("swizzles installed: 11 classes, 22 methods  (no-substrate build)");
}
