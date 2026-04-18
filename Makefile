TARGET := iphone:clang:latest:latest
THEOS_PACKAGE_SCHEME = rootless
THEOS_DEVICE_IP = 192.168.1.37
DEBUG = 0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = GLESignFnMac
$(TWEAK_NAME)_FILES = $(shell find . -type f \( -iname "*.cpp" -o -iname "*.c" -o -iname "*.m" -o -iname "*.mm" -o -iname "*.x" -o -iname "*.xm" \))
$(TWEAK_NAME)_CFLAGS     = -fobjc-arc -O3 -Wno-deprecated-declarations
include $(THEOS_MAKE_PATH)/tweak.mk

