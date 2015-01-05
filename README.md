InspectiveC
======

*MobileSubstrate based objc_msgSend hook for debugging/inspection purposes.*

Based on [itrace by emeau](https://github.com/emeau/itrace), [AspectiveC by saurik](http://svn.saurik.com/repos/menes/trunk/aspectivec/AspectiveC.mm), and [Subjective-C by kennytm](http://networkpx.blogspot.com/2009/09/introducing-subjective-c.html).

Logs output to **/var/mobile/Documents/InspectiveC** or **/var/mobile/Containers/Data/Application/\<App-Hex\>/Documents/InspectiveC** (sandbox). Inside the InspectiveC folder, you'll find **\<exe\>/\<pid\>_\<tid\>.log**.

This is **not compatible with arm64** at the moment, although I do hope to add support in the future.

**Features:**
* Watch specific objects
* Watch instances of a specific class
* Watch specific selectors
* Prints arguments

**Hopeful Features (in no particular order):**
* Print retvals
* Hook obj_msgSend[st|fp]ret
* More advanced filtering
* arm64 support???
* Optimizations
  * Nicer hooking
  * Reduce redundancy
  * Better multithreading performance

**Usage:**

Properly [install theos](http://iphonedevwiki.net/index.php/Theos/Setup) and grab yourself a copy
of the iOS SDK. You may have to modify the Makefile (i.e. ARCHS or TARGET) and/or InspectiveC.mm. I
compile this on my Mac with Clang - if you use anything different you may have some issues with the
assembly code.

When you install the deb, you will find **libinspectivec.dylib** in /usr/lib. Copy this dylib into
$THEOS/lib and then copy **InspectiveC.h** into $THEOS/include.

**Option 1: Use the InspectiveC Wrapper**

Copy the source of PutThisInYourTweak.m into your Tweak file and use those functions.



**Option 2: Link directly against InspectiveC**

Add the following line to your makefil:

```
<YOUR_TWEAK_NAME>_LIBRARIES = inspectivec
```

This will automatically load InspectiveC in your tweak (whatever process your tweak injects into).
Then include InspectiveC.h in your tweak and use those functions.


InspectiveC.h headlines the following API:
```c
// Watches/unwatches the specified object. Objects will be automatically unwatched when they
// receive a -|dealloc| message.
void InspectiveC_watchObject(id obj);
void InspectiveC_unwatchObject(id obj);

// Watches/unwatches instances of the specified class ONLY - will not watch subclass instances.
void InspectiveC_watchInstancesOfClass(Class clazz);
void InspectiveC_unwatchInstancesOfClass(Class clazz);

// Watches/unwatches the specified selector.
void InspectiveC_watchSelector(SEL _cmd);
void InspectiveC_unwatchSelector(SEL _cmd);

// Enables/disables logging for the current thread.
void InspectiveC_enableLogging();
void InspectiveC_disableLogging();
```
