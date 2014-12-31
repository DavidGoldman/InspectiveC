ARCHS = armv7
TARGET = iphone:8.1:8.1
# ADDITIONAL_OBJCFLAGS = -S

LIBRARY_NAME = libinspectivec
libinspectivec_FILES = hashmap.mm logging.mm InspectiveC.mm
libinspectivec_LIBRARIES = substrate
libinspectivec_FRAMEWORKS = Foundation UIKit

include theos/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/library.mk

after-install::
	install.exec "killall -9 SpringBoard"
