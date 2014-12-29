/* GNU Lesser General Public License, Version 3 {{{ */
/*
 * Substrate is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Lesser General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version.
 *
 * Substrate is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
 * License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with Substrate.  If not, see <http://www.gnu.org/licenses/>.
**/
/* }}} */

#include <substrate.h>
#include <Foundation/Foundation.h>

#include <cstdarg>
#include <cstdio>

#include <set>
#include <vector>

#include <sys/time.h>
#include <pthread.h>

 #define DEFAULT_CALLSTACK_DEPTH 128
 #define CALLSTACK_DEPTH_INCREMENT 64

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
/*
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

static inline void pushCallRecord(id obj, SEL _cmd, uint32_t lr) {
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
*/
 static void destroyThreadCallStack(void *ptr) {
    ThreadCallStack *cs = (ThreadCallStack *)ptr;
    free(cs->stack);
    free(cs);
 }

// Hooking magic.

static void log(FILE *file, id obj, SEL _cmd) {
    if (obj) {
        Class kind = object_getClass(obj);
        fprintf(file, "%s\t%s\n", class_getName(kind), sel_getName(_cmd));
    }
}

FILE *logFile = NULL;
unsigned long msgCounter = 0;

// Called in our replacementObjc_msgSend before calling the original objc_msgSend.
// This pushes a CallRecord to our stack, most importantly saving the lr.
void preObjc_msgSend(id self, uint32_t lr, SEL _cmd, va_list args) {
    if (bannedSels.find(_cmd) != bannedSels.end())
        return;
    if (self && logFile && ++msgCounter % 10 == 0) {
        fprintf(logFile, "LR:%p ; SEL: %s\n", (void *)lr, sel_getName(_cmd));
        log(logFile, self, _cmd);
    }
}

// Called in our replacementObjc_msgSend after calling the original objc_msgSend.
// This returns the lr in r0.
uint32_t postObjc_msgSend() {
    CallRecord *record = popCallRecord();
    return record->lr;
}

#define call(b, value) \
    __asm__ volatile( \
            "push {r0, lr}\n" \
            "blx " #value "\n" \
            "mov r12, r0\n" \
            "pop {r0, lr}\n" #b " r12\n" \
        );

#define save() \
    __asm volatile ("push {r0, r1, r2, r3}\n");

#define load() \
    __asm volatile ("pop {r0, r1, r2, r3}\n");

#define link(b, value) \
    __asm volatile ("push {lr}\n"); \
    __asm volatile ("sub sp, #4\n"); \
    call(b, value) \
    __asm volatile ("add sp, #4\n"); \
    __asm volatile ("pop {lr}\n");

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
    // Call our pre-objc_msgSend hook.
    save()
    __asm__ volatile ( // Swap the args around for our call to preObjc_msgSend.
            "mov r2, r1\n"
            "mov r1, lr\n"
            "add r3, sp, #8\n"
            "push {lr}\n" // Call preObjc_msgSend.
            "blx __Z15preObjc_msgSendP11objc_objectjP13objc_selectorPv\n"
            "pop {lr}\n"
        );
    load()
    // Call through to the original objc_msgSend.
    call(bx, __Z19getOrigObjc_msgSendv)
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
