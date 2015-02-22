ARCHS = armv7 arm64
TARGET = iphone:8.1:8.1
include theos/makefiles/common.mk

TWEAK_NAME = Example
Example_FILES = Tweak.xm

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
