// FnSwizzle.h -- tiny helpers replacing Logos %hook / %orig with plain
// objc/runtime calls. Header-only; no CydiaSubstrate or ellekit needed.
//
// Usage pattern per method:
//
//   typedef void (*Cls_Method_IMP)(id, SEL, NSInteger);
//   static Cls_Method_IMP orig_Cls_method;
//   static void swz_Cls_method(id self, SEL _cmd, NSInteger arg) {
//       orig_Cls_method(self, _cmd, arg);   // == %orig(arg)
//   }
//
//   // Install once in the constructor:
//   FNSwizzleInstance("NSWindow", @selector(makeKeyAndOrderFront:),
//                     (IMP)swz_Cls_method, (IMP *)&orig_Cls_method);

#pragma once

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Replace an instance method and stash the original IMP so the
// swizzle body can tail-call it. If the class or the selector does
// not exist on the runtime, *outOrig stays NULL and no swizzle is
// installed -- caller code should null-check orig before calling.
static inline BOOL FNSwizzleInstance(const char *clsName, SEL sel,
                                     IMP repl, IMP *outOrig) {
    Class cls = objc_getClass(clsName);
    if (!cls) {
        NSLog(@"[fn-mac][swz] class '%s' not found -- skipping %@",
              clsName, NSStringFromSelector(sel));
        if (outOrig) *outOrig = NULL;
        return NO;
    }
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        NSLog(@"[fn-mac][swz] -[%s %@] not found -- skipping",
              clsName, NSStringFromSelector(sel));
        if (outOrig) *outOrig = NULL;
        return NO;
    }
    if (outOrig) *outOrig = method_getImplementation(m);
    method_setImplementation(m, repl);
    return YES;
}

// Same for class (+) methods.
static inline BOOL FNSwizzleClass(const char *clsName, SEL sel,
                                  IMP repl, IMP *outOrig) {
    Class cls = objc_getClass(clsName);
    if (!cls) {
        if (outOrig) *outOrig = NULL;
        return NO;
    }
    Method m = class_getClassMethod(cls, sel);
    if (!m) {
        if (outOrig) *outOrig = NULL;
        return NO;
    }
    if (outOrig) *outOrig = method_getImplementation(m);
    method_setImplementation(m, repl);
    return YES;
}
