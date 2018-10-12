#ifndef INSPECTIVE_C_H
#define INSPECTIVE_C_H

#include <objc/objc.h>

#if __cplusplus
extern "C" {
#endif

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


// Flushes the log file for the current thread.
void InspectiveC_flushLogFile();

#if __cplusplus
}
#endif

#endif
