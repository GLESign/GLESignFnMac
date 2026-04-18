

#pragma once

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

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
