#include <substrate.h>
#include <Foundation/Foundation.h>

#include <cstdarg>
#include <cstdio>

#include <set>

#include <pthread.h>

 #define DEFAULT_CALLSTACK_DEPTH 128
 #define CALLSTACK_DEPTH_INCREMENT 64
 #define LOG_FREQUENCY (25 * 1000)

static pthread_key_t threadKey;
static std::set<SEL> bannedSels;

 typedef struct CallRecord_ {
    id obj;
    SEL _cmd;
    uint32_t lr;
 } CallRecord;

 typedef struct ThreadCallStack_ {
    CallRecord *stack;
    int allocatedLength;
    int index;
 } ThreadCallStack;

static inline ThreadCallStack * getThreadCallStack() {
    ThreadCallStack *cs = (ThreadCallStack *)pthread_getspecific(threadKey);
    if (cs == NULL) {
        cs = (ThreadCallStack *)malloc(sizeof(ThreadCallStack));
        cs->stack = (CallRecord *)calloc(DEFAULT_CALLSTACK_DEPTH, sizeof(CallRecord));
        cs->allocatedLength = DEFAULT_CALLSTACK_DEPTH;
        cs->index = -1;
        pthread_setspecific(threadKey, cs);
    }
    return cs;
}

static inline void pushCallRecord(id obj, uint32_t lr, SEL _cmd) {
    ThreadCallStack *cs = getThreadCallStack();
    int nextIndex = (++cs->index);
    if (nextIndex >= cs->allocatedLength) {
        cs->allocatedLength += CALLSTACK_DEPTH_INCREMENT;
        cs->stack = (CallRecord *)realloc(cs->stack, cs->allocatedLength * sizeof(CallRecord));
    }
    CallRecord *newRecord = &cs->stack[nextIndex];
    newRecord->obj = obj;
    newRecord->_cmd = _cmd;
    newRecord->lr = lr;
}

static inline CallRecord * popCallRecord() {
    ThreadCallStack *cs = (ThreadCallStack *)pthread_getspecific(threadKey);
    return &cs->stack[cs->index--];
}

 static void destroyThreadCallStack(void *ptr) {
    ThreadCallStack *cs = (ThreadCallStack *)ptr;
    free(cs->stack);
    free(cs);
 }

static void log(FILE *file, id obj, SEL _cmd) {
    if (obj) {
        Class kind = object_getClass(obj);
        fprintf(file, "%s\t%s\n", class_getName(kind), sel_getName(_cmd));
    }
}

FILE *logFile = NULL;
unsigned long msgCounter = 0;

// Hooking magic.

// Called in our replacementObjc_msgSend before calling the original objc_msgSend.
// This pushes a CallRecord to our stack, most importantly saving the lr.
void preObjc_msgSend(id self, uint32_t lr, SEL _cmd, va_list args) {
    pushCallRecord(self, lr, _cmd);

    if (bannedSels.find(_cmd) != bannedSels.end())
        return;
    if (self && logFile && ++msgCounter % LOG_FREQUENCY == 0) {
        log(logFile, self, _cmd);
    }
}

// Called in our replacementObjc_msgSend after calling the original objc_msgSend.
// This returns the lr in r0.
uint32_t postObjc_msgSend() {
    CallRecord *record = popCallRecord();
    return record->lr;
}

static id (*orig_objc_msgSend)(id, SEL, ...);

// Returns orig_objc_msgSend in r0.
__attribute__((__naked__))
uint32_t getOrigObjc_msgSend() {
    __asm__ volatile (
            "mov r0, %0" :: "r"(orig_objc_msgSend)
        );
}

// Our replacement objc_msgSeng.
__attribute__((__naked__))
static void replacementObjc_msgSend() {
    // Call our preObjc_msgSend hook.
    __asm__ volatile ( // Swap the args around for our call to preObjc_msgSend.
            "push {r0, r1, r2, r3}\n"
            "mov r2, r1\n"
            "mov r1, lr\n"
            "add r3, sp, #8\n"
            "blx __Z15preObjc_msgSendP11objc_objectjP13objc_selectorPv\n"
            "pop {r0, r1, r2, r3}\n"
        );
    // Call through to the original objc_msgSend.
    __asm__ volatile (
            "push {r0}\n"
            "blx __Z19getOrigObjc_msgSendv\n"
            "mov r12, r0\n"
            "pop {r0}\n"
            "blx r12\n"
        );
    // Call our postObjc_msgSend hook.
    __asm__ volatile (
            "push {r0-r3}\n"
            "blx __Z16postObjc_msgSendv\n"
            "mov lr, r0\n"
            "pop {r0-r3}\n"
            "bx lr\n"
        );
}

MSInitialize {
    pthread_key_create(&threadKey, &destroyThreadCallStack);

    logFile = fopen("/tmp/inspectivec_calls.log", "a");

    bannedSels.insert(@selector(alloc));
    bannedSels.insert(@selector(autorelease));
    bannedSels.insert(@selector(initialize));
    bannedSels.insert(@selector(class));
    bannedSels.insert(@selector(copy));
    bannedSels.insert(@selector(copyWithZone:));
    bannedSels.insert(@selector(dealloc));
    bannedSels.insert(@selector(delegate));
    bannedSels.insert(@selector(isKindOfClass:));
    bannedSels.insert(@selector(lock));
    bannedSels.insert(@selector(retain));
    bannedSels.insert(@selector(release));
    bannedSels.insert(@selector(unlock));
    bannedSels.insert(@selector(UTF8String));
    bannedSels.insert(@selector(count));
    bannedSels.insert(@selector(doubleValue));

    MSHookFunction(&objc_msgSend, (id (*)(id, SEL, ...))&replacementObjc_msgSend, &orig_objc_msgSend);
    fprintf(logFile, "POST: <%p> <%p> <%p>\n", &objc_msgSend, &replacementObjc_msgSend, orig_objc_msgSend);
}
