ARCHS = armv7
TARGET = iphone:8.1:8.1
# ADDITIONAL_OBJCFLAGS = -S

include theos/makefiles/common.mk

TWEAK_NAME = InspectiveC
InspectiveC_FILES = hashmap.mm InspectiveC.mm

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
