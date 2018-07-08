InspectiveC
======

*MobileSubstrate and Fishhook based objc_msgSend hook for debugging/inspection purposes.*

Based on [itrace by emeau](https://github.com/emeau/itrace), [AspectiveC by saurik](http://svn.saurik.com/repos/menes/trunk/aspectivec/AspectiveC.mm), and [Subjective-C by kennytm](http://networkpx.blogspot.com/2009/09/introducing-subjective-c.html).

Logs output to **/var/mobile/Documents/InspectiveC** or **/var/mobile/Containers/Data/Application/\<App-Hex\>/Documents/InspectiveC** (sandbox). Inside the InspectiveC folder, you'll find **\<exe\>/\<pid\>_\<tid\>.log**.

**You can download the deb from the stable_debs folder or from my [repo](http://apt.golddavid.com/).**

**Description:**

This is an inspection tool that you can use to log Objective-C message hierarchies. It can currently
watch specific objects, all objects of a given class, and specific selectors. It is indeed
compatible with arm64 - in fact, it is more full-featured on arm64 as arm32 has obj_msgSend[st|fp]ret
which are currently not hooked.

Note that due to limitations with MobileSubstrate on iOS 10 and 11, you must use Fishhook to
interpose objc_msgSend instead. To do this, build with `USE_FISHHOOK=1`, i.e.
`make package USE_FISHHOOK=1 FOR_RELEASE=1 install`.

**Features:**
* arm64 support (and arm32)
* Watch specific objects
* Watch instances of a specific class
* Watch specific selectors
* Prints arguments

**Hopeful Features (in no particular order):**
* Support logging blocks/replaced C functions
* Print retvals
* Optimizations
  * Better multithreading performance

**Example Output:**

```
***-|SpringBoard@<0x15455d320> _run|***
  +|NSAutoreleasePool alloc|
    +|NSAutoreleasePool allocWithZone:| NULL
  -|NSAutoreleasePool@<0x170442a00> init|
  -|SpringBoard@<0x15455d320> _accessibilityInit|
    -|SpringBoard@<0x15455d320> performSelector:withObject:afterDelay:| @selector(_accessibilitySetUpQuickSpeak) nil 1.5
      +|NSArray arrayWithObject:| @"kCFRunLoopDefaultMode"
      -|SpringBoard@<0x15455d320> performSelector:withObject:afterDelay:inModes:| @selector(_accessibilitySetUpQuickSpeak) nil 1.5 <__NSArrayI@0x174233560>
    -|SpringBoard@<0x15455d320> _updateAccessibilitySettingsLoader|
      +|NSBundle mainBundle|
      -|NSBundle@<0x17009f310> bundleIdentifier|
      -|__NSCFString@<0x1740557b0> isEqualToString:| @"com.apple.PreBoard"
      -|__NSStackBlock__@<0x16fdb7608> copy|
      +|CFPrefsSearchListSource withSearchListForIdentifier:container:perform:| 0x19819f3b0 NULL <__NSStackBlock__@0x16fdb7570>
      +|NSNumber class|
      -|__NSCFBoolean@<0x194d4ab70> isKindOfClass:| [NSNumber class]
      -|__NSCFBoolean@<0x194d4ab70> boolValue|
      -|__NSCFBoolean@<0x194d4ab70> release|
    -|SpringBoard@<0x15455d320> _updateApplicationAccessibility|
      +|NSBundle mainBundle|
      -|NSBundle@<0x17009f310> bundleIdentifier|
      -|__NSCFString@<0x1740557b0> isEqualToString:| @"com.apple.PreBoard"
      -|__NSStackBlock__@<0x16fdb75f8> copy|
      +|CFPrefsSearchListSource withSearchListForIdentifier:container:perform:| 0x19819f3b0 NULL <__NSStackBlock__@0x16fdb7560>
      +|NSNumber class|
      -|__NSCFNumber@<0xb000000000000003> isKindOfClass:| [NSNumber class]
      -|__NSCFNumber@<0xb000000000000003> boolValue|
      -|__NSCFNumber@<0xb000000000000003> release|
    -|SpringBoard@<0x15455d320> _updateLargeTextNotification|...
```

**Usage:**

Properly [install theos](http://iphonedevwiki.net/index.php/Theos/Setup) and grab yourself a copy
of the iOS SDK. You may have to modify the Makefile (i.e. ARCHS or TARGET) and/or InspectiveC.mm. I
compile this on my Mac with Clang - if you use anything different you may have some issues with the
assembly code.

When you install the deb, you will find **libinspectivec.dylib** in /usr/lib. Copy this dylib into
$THEOS/lib and then copy **InspectiveC.h** into $THEOS/include.

**Option 0: Use InspectiveC with Cycript for maximum efficiency**

Use Cycript to inject into a process, then paste a single line to load InspectiveC. The command is a
compiled version of the InspectiveC.cy file - found in this repo in cycript/InspectiveC.compiled.cy.

Be sure to install **Cycript on Cydia** and replace "SpringBoard" in the first command with the name
of the process that you want to inject into. Also, don't forget to **respring/kill the app** when
you no longer want InspectiveC loaded.

```c
// You can replace SpringBoard with whatever process name you want.
root# cycript -p SpringBoard

cy# intFunc=new Type("v").functionWith(int);objFunc=new Type("v").functionWith(id);classFunc=new Type("v").functionWith(Class);selFunc=new Type("v").functionWith(SEL);voidFunc=new Type("v").functionWith(new Type("v"));objSelFunc=new Type("v").functionWith(id,SEL);classSelFunc=new Type("v").functionWith(Class,SEL);handle=dlopen("/usr/lib/libinspectivec.dylib",RTLD_NOW);setMaximumRelativeLoggingDepth=intFunc(dlsym(handle,"InspectiveC_setMaximumRelativeLoggingDepth"));watchObject=objFunc(dlsym(handle,"InspectiveC_watchObject"));unwatchObject=objFunc(dlsym(handle,"InspectiveC_unwatchObject"));watchSelectorOnObject=objSelFunc(dlsym(handle,"InspectiveC_watchSelectorOnObject"));unwatchSelectorOnObject=objSelFunc(dlsym(handle,"InspectiveC_unwatchSelectorOnObject"));watchClass=classFunc(dlsym(handle,"InspectiveC_watchInstancesOfClass"));unwatchClass=classFunc(dlsym(handle,"InspectiveC_unwatchInstancesOfClass"));watchSelectorOnClass=classSelFunc(dlsym(handle,"InspectiveC_watchSelectorOnInstancesOfClass"));unwatchSelectorOnClass=classSelFunc(dlsym(handle,"InspectiveC_unwatchSelectorOnInstancesOfClass"));watchSelector=selFunc(dlsym(handle,"InspectiveC_watchSelector"));unwatchSelector=selFunc(dlsym(handle,"InspectiveC_unwatchSelector"));enableLogging=voidFunc(dlsym(handle,"InspectiveC_enableLogging"));disableLogging=voidFunc(dlsym(handle,"InspectiveC_disableLogging"));enableCompleteLogging=voidFunc(dlsym(handle,"InspectiveC_enableCompleteLogging"));disableCompleteLogging=voidFunc(dlsym(handle,"InspectiveC_disableCompleteLogging"))

// Now use your InspectiveC commands as if they were the ones in InspCWrapper.

// Use this command to limit the recursion when logging.
cy# setMaximumRelativeLoggingDepth(5)

cy# watchObject(choose(SBUIController)[0])

cy# unwatchObject(choose(SBUIController)[0])

cy# watchSelector(@selector(anySelectorYouWant))

cy# watchClass([AnyClassYouWant class])
```

**Option 1: Use the InspectiveC Wrapper**

Include **InspCWrapper.m** in your Tweak file. You should probably use a DEBUG guard.

```c
#if INSPECTIVEC_DEBUG
#include "InspCWrapper.m"
#endif
```

Then use the following API:

```c
// Set the maximum logging depth after a hit.
void setMaximumRelativeLoggingDepth(int depth);


// Watches/unwatches the specified object (all selectors).
// Objects will be automatically unwatched when they receive a -|dealloc| message.
void watchObject(id obj);
void unwatchObject(id obj);

// Watches/unwatches the specified selector on the object.
// Objects will be automatically unwatched when they receive a -|dealloc| message.
void watchSelectorOnObject(id obj, SEL _cmd);
void unwatchSelectorOnObject(id obj, SEL _cmd);


// Watches/unwatches instances of the specified class ONLY - will not watch subclass instances.
void watchClass(Class clazz);
void unwatchClass(Class clazz);

// Watches/unwatches the specified selector on instances of the specified class ONLY - will not
// watch subclass instances.
void watchSelectorOnClass(Class clazz, SEL _cmd);
void unwatchSelectorOnClass(Class clazz, SEL _cmd);


// Watches/unwatches the specified selector.
void watchSelector(SEL _cmd);
void unwatchSelector(SEL _cmd);

// Enables/disables logging for the current thread.
void enableLogging();
void disableLogging();

// Enables/disables logging every message for the current thread.
void enableCompleteLogging();
void disableCompleteLogging();
```


**Option 2: Link directly against InspectiveC**

Add the following line to your makefile:

```
<YOUR_TWEAK_NAME>_LIBRARIES = inspectivec
```

This will automatically load InspectiveC in your tweak (whatever process your tweak injects into).
Then include InspectiveC.h in your tweak and use those functions.


InspectiveC.h headlines the following API:
```c
// Set the maximum logging depth after a hit.
void InspectiveC_setMaximumRelativeLoggingDepth(int depth);


// Watches/unwatches the specified object (all selectors).
// Objects will be automatically unwatched when they receive a -|dealloc| message.
void InspectiveC_watchObject(id obj);
void InspectiveC_unwatchObject(id obj);

// Watches/unwatches the specified selector on the object.
// Objects will be automatically unwatched when they receive a -|dealloc| message.
void InspectiveC_watchSelectorOnObject(id obj, SEL _cmd);
void InspectiveC_unwatchSelectorOnObject(id obj, SEL _cmd);


// Watches/unwatches instances of the specified class ONLY - will not watch subclass instances.
void InspectiveC_watchInstancesOfClass(Class clazz);
void InspectiveC_unwatchInstancesOfClass(Class clazz);

// Watches/unwatches the specified selector on instances of the specified class ONLY - will not
// watch subclass instances.
void InspectiveC_watchSelectorOnInstancesOfClass(Class clazz, SEL _cmd);
void InspectiveC_unwatchSelectorOnInstancesOfClass(Class clazz, SEL _cmd);


// Watches/unwatches the specified selector.
void InspectiveC_watchSelector(SEL _cmd);
void InspectiveC_unwatchSelector(SEL _cmd);

// Enables/disables logging for the current thread.
void InspectiveC_enableLogging();
void InspectiveC_disableLogging();

// Enables/disables logging every message for the current thread.
void InspectiveC_enableCompleteLogging();
void InspectiveC_disableCompleteLogging();
```
