DEBUG = 0
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = showtouch
showtouch_FILES = Sources/P9ShowTouchRootListController.m ../Shared/STPreferences.m
showtouch_CFLAGS = -fobjc-arc -I../Shared
showtouch_FRAMEWORKS = UIKit CoreGraphics
showtouch_PRIVATE_FRAMEWORKS = Preferences
showtouch_INSTALL_PATH = /Library/PreferenceBundles
include $(THEOS_MAKE_PATH)/bundle.mk
