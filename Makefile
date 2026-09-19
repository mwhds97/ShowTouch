DEBUG = 0
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard
PACKAGE_VERSION = $(THEOS_PACKAGE_BASE_VERSION)

include $(THEOS)/makefiles/common.mk
TWEAK_NAME = ShowTouch
ShowTouch_FILES = Sources/ShowTouchRuntime.m
ShowTouch_CFLAGS = -fobjc-arc
ShowTouch_FRAMEWORKS = UIKit CoreGraphics QuartzCore
ShowTouch_LIBRARIES = substrate
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Preferences CCToggle
include $(THEOS_MAKE_PATH)/aggregate.mk

# Settings and SpringBoard on A12+ require an arm64e slice.
after-stage::
	@python3 scripts/verify-binaries.py "$(THEOS_STAGING_DIR)"
