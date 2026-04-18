# tweak-fnmac — FnMacTweak without CydiaSubstrate

Drop-in replacement for
[`../FnMacTweak/`](../FnMacTweak/). Same feature set, same UI, same
keybinds logic. The only difference is **no Logos, no CydiaSubstrate /
ellekit dependency**:

| Original (CydiaSubstrate) | This version |
|---|---|
| `.xm` (Logos preprocessor) | `.mm` (plain Objective-C++) |
| `%hook ClassName … %end` | `method_setImplementation` via `FnSwizzle.h` |
| `%orig(args)` | typed IMP pointer `orig_Class_method(self, _cmd, args)` |
| `%ctor { … }` | `__attribute__((constructor))` |
| `Depends: mobilesubstrate` | no runtime deps beyond the iOS frameworks |

fishhook is used exactly as upstream (libc symbol rebinds for
`sysctl` / `sysctlbyname` / `_availability_version_check`).

## Layout

```
tweak-fnmac/
├── Makefile                 targets .mm, no substrate -lsubstrate
├── FnMacTweak.plist         filter on com.apple.springboard (unchanged)
├── control                  package metadata
├── README.md
├── lib/
│   ├── fishhook.c           verbatim from upstream
│   └── fishhook.h
└── src/
    ├── FnSwizzle.h          tiny header-only helpers:
    │                        FNSwizzleInstance / FNSwizzleClass
    ├── Tweak.mm             ex-Tweak.xm; every %hook block rewritten
    │                        as static C swizzle functions + IMP
    │                        storage, installed in the constructor
    ├── FnOverlayWindow.{h,m}  copy
    ├── globals.{h,m}          copy
    ├── ue_reflection.{h,m}    copy
    └── views/
        ├── popupViewController.{h,m}
        └── welcomeViewController.{h,m}
```

## Hook conversion

For every `%hook Cls` block, the pattern is:

```objc
// 1. IMP typedef matching the selector signature.
typedef ReturnType (*Cls_method_IMP)(id, SEL, Arg1Type, Arg2Type);
static Cls_method_IMP orig_Cls_method;

// 2. Swizzle body. Call the original like you would have called %orig.
static ReturnType swz_Cls_method(id self, SEL _cmd,
                                  Arg1Type a1, Arg2Type a2) {
    // ... same body as inside the original %hook ...
    return orig_Cls_method(self, _cmd, a1, a2);
}

// 3. Install in the constructor (FnSwizzle.h inlines the boilerplate).
FNSwizzleInstance("Cls", @selector(method:arg2:),
                  (IMP)swz_Cls_method,
                  (IMP *)&orig_Cls_method);
```

Classes swizzled (every one was a `%hook` in the original):

| Class | Methods |
|---|---|
| `GCExtendedGamepad` | `leftThumbstickButton`, `_leftThumbstickButton`, `rightThumbstickButton`, `_rightThumbstickButton` |
| `GCController` | `productCategory`, `vendorName` |
| `NSWindow` | `makeKeyAndOrderFront:` |
| `GCMouseInput` | `setMouseMovedHandler:` |
| `GCControllerDirectionPad` | `setValueChangedHandler:` |
| `GCKeyboardInput` | `setKeyChangedHandler:` |
| `IOSViewController` | `prefersPointerLocked` |
| `UIScreen` | `maximumFramesPerSecond` |
| `UITouch` | `type` |
| `UIWindow` | `sendEvent:` |
| `GCControllerButtonInput` | `setPressedChangedHandler:`, `setValueChangedHandler:`, `isPressed`, `value`, `setValue:`, `setPressed:`, `pressed` |

One installer function `fnmac_install_swizzles()` at the top of the
constructor registers all of them; if any class/selector is missing at
runtime the helper just logs and skips (robust to iOS version drift).

## Build

```sh
export THEOS=~/theos
cd tweak-fnmac
make package install
```

Output `.deb` goes in `packages/`. Theos package scheme is `rootless`
so it fits alongside all the other tweaks in this repo.
