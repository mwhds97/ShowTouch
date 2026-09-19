ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = CCToggle
CCToggle_BUNDLE_EXTENSION = bundle
CCToggle_FILES = Sources/P9ShowTouchControlCenterToggle.m ../Shared/STPreferences.m
CCToggle_CFLAGS = -fobjc-arc -I../Shared
CCToggle_FRAMEWORKS = UIKit CoreGraphics
CCToggle_PRIVATE_FRAMEWORKS = ControlCenterUIKit
CCToggle_INSTALL_PATH = /Library/ControlCenter/Bundles
include $(THEOS_MAKE_PATH)/bundle.mk
