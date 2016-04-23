ARCHS = armv7 arm64
TARGET = iphone:9.2:9.2
ADDITIONAL_OBJCFLAGS = -fobjc-exceptions
# ADDITIONAL_OBJCFLAGS += -S

LIBRARY_NAME = libinspectivec
libinspectivec_FILES = hashmap.mm logging.mm blocks.mm InspectiveC.mm
libinspectivec_LIBRARIES = substrate
libinspectivec_FRAMEWORKS = Foundation UIKit

include theos/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/library.mk

after-install::
	install.exec "killall -9 SpringBoard"
