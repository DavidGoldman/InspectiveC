ARCHS = armv7 arm64
TARGET = iphone:9.3:9.3
ADDITIONAL_OBJCFLAGS = -fobjc-exceptions
# ADDITIONAL_OBJCFLAGS += -S

LIBRARY_NAME = libinspectivec
libinspectivec_FILES = hashmap.mm logging.mm blocks.mm InspectiveC.mm
ifeq ($(USE_FISHHOOK),1)
	libinspectivec_FILES += fishhook/fishhook.c
	libinspectivec_CFLAGS = -DUSE_FISHHOOK=1
endif

libinspectivec_LIBRARIES = substrate
libinspectivec_FRAMEWORKS = Foundation UIKit

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/library.mk

after-install::
	install.exec "killall -9 SpringBoard"
