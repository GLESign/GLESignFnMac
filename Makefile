TARGET := iphone:clang:latest:26.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = rootless
THEOS_DEVICE_IP = 192.168.1.37

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FnMacTweak

# No Logos, no CydiaSubstrate / ellekit -- plain .mm + fishhook.c.
# Tweak.mm is the ex-Tweak.xm with every %hook converted to
# method_setImplementation swizzles via FnSwizzle.h.
FnMacTweak_FILES = \
    ./src/Tweak.mm \
    ./src/FnOverlayWindow.m \
    ./src/views/popupViewController.m \
    ./src/views/welcomeViewController.m \
    ./src/globals.m \
    ./src/ue_reflection.m \
    ./lib/fishhook.c

FnMacTweak_FRAMEWORKS = UIKit WebKit CoreGraphics GameController QuartzCore
FnMacTweak_CFLAGS     = -fobjc-arc -O3 -Wno-deprecated-declarations

DEBUG = 0

include $(THEOS_MAKE_PATH)/tweak.mk
