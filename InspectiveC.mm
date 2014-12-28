/* Cydia Substrate - Powerful Code Insertion Platform
 * Copyright (C) 2012  Jay Freeman (saurik)
*/

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

MSClassHook(__NSArrayI)
MSClassHook(__NSArrayM)
MSClassHook(__NSCFArray)

MSClassHook(NSNumber)
MSClassHook(NSString)

static std::set<SEL> banned_;

static void log(FILE *file, id obj, SEL _cmd) {
    if (obj) {
        Class kind = object_getClass(obj);
        fprintf(file, "%s\t%s\n", class_getName(kind), sel_getName(_cmd));
    }
}

/*
static void log(FILE *file, id value, SEL _cmd) {
    if (value == nil) {
        fprintf(file, "nil");
        return;
    }

    Class kind(object_getClass(value));
    if (class_isMetaClass(kind)) {
        fprintf(file, "[%s class]", class_getName(value));
        return;
    }

    if (
        kind == $__NSArrayI ||
        kind == $__NSArrayM ||
        kind == $__NSCFArray ||
    false) {
        fprintf(file, "@[");

        for (size_t index(0), count([value count]); index != count; ++index) {
            if (index != 0)
                fprintf(file, ", ");

            if (index == 16) {
                fprintf(file, "...%zu", count);
                break;
            }

            log(file, [value objectAtIndex:index], _cmd);
            fflush(file);
        }

        fprintf(file, "]\n");
        return;
    }
    
    if ([value isKindOfClass:$NSNumber]) {
        double number([value doubleValue]);
        fprintf(file, "@%g\n", number);
    } else if ([value isKindOfClass:$NSString]) {
        const char *str = [value UTF8String];
        fprintf(file, "@\"%s\"\n", str);
    } else {
        fprintf(file, "<%s@0x%08lx>\n", class_getName(kind), reinterpret_cast<uintptr_t>(value));
    }
}*/

FILE *logFile = NULL;
unsigned long msgCounter = 0;

void preObjc_msgSend(id self, Class _class, SEL _cmd, va_list args) {
    if (banned_.find(_cmd) != banned_.end())
        return;
    if (self && logFile && ++msgCounter % 5000 == 0) {
        log(logFile, self, _cmd);
    }
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

// Returns &preObjc_msgSend in r0.
__attribute__((__naked__))
uint32_t getPreObjc_msgSend() {
    __asm__ volatile (
        "mov r0, %0" :: "r"(&preObjc_msgSend)
    );
}

// Our replacement objc_msgSeng.
__attribute__((__naked__))
static void replacementObjc_msgSend() {
    // Call our pre-objc_msgSend hook.
    save() // Save r0-r3.
    __asm__ volatile ( // Swap the args around for our call to preObjc_msgSend.
            "mov r2, r1\n"
            "mov r1, #0\n"
            "add r3, sp, #8\n"
            "blx __Z15preObjc_msgSendP11objc_objectP10objc_classP13objc_selectorPv\n"
        );
    link(blx, __Z18getPreObjc_msgSendv);
    load() // Load r0-r3.
    // Call through to the original objc_msgSend.
    call(bx, __Z19getOrigObjc_msgSendv)
}
/*
static void (*_objc_msgSend_stret)(id, SEL, ...);

__attribute__((__naked__))
static void $objc_msgSend_stret() {
    save()
        __asm volatile ("mov r0, r1\n");
        __asm volatile ("mov r1, #0\n");
        __asm volatile ("add r3, sp, #12\n");

        link(blx, &$objc_msgSend$)
    load()

    call(bx, _objc_msgSend_stret)
}

static id (*_objc_msgSendSuper)(struct objc_super *, SEL, ...);

__attribute__((__naked__))
static void $objc_msgSendSuper() {
    save()
        __asm volatile ("mov r2, r1\n");
        __asm volatile ("ldr r1, [r0, #4]\n");
        __asm volatile ("ldr r0, [r0, #0]\n");
        __asm volatile ("add r3, sp, #8\n");

        link(blx, &$objc_msgSend$)
    load()

    call(bx, _objc_msgSendSuper)
}

static void (*_objc_msgSendSuper_stret)(struct objc_super *, SEL, ...);

__attribute__((__naked__))
static void $objc_msgSendSuper_stret() {
    save()
        __asm volatile ("ldr r0, [r1, #0]\n");
        __asm volatile ("ldr r1, [r1, #4]\n");
        __asm volatile ("add r3, sp, #12\n");

        link(blx, &$objc_msgSend$)
    load()

    call(bx, _objc_msgSendSuper_stret)
}

static id (*_objc_msgSendSuper2)(struct objc_super *, SEL, ...);

__attribute__((__naked__))
static void $objc_msgSendSuper2() {
    save()
        __asm volatile ("ldr r0, [r0, #4]\n");
        link(blx, class_getSuperclass)
        __asm volatile ("mov r12, r0");
    load()

    save()
        __asm volatile ("mov r2, r1\n");
        __asm volatile ("ldr r0, [r0, #0]\n");
        __asm volatile ("mov r1, r12\n");
        __asm volatile ("add r3, sp, #8\n");

        link(blx, &$objc_msgSend$)
    load()

    call(bx, _objc_msgSendSuper2)
}

static void (*_objc_msgSendSuper2_stret)(struct objc_super *, SEL, ...);

__attribute__((__naked__))
static void $objc_msgSendSuper2_stret() {
    save()
        __asm volatile ("ldr r0, [r1, #4]\n");
        link(blx, class_getSuperclass)
        __asm volatile ("mov r12, r0");
    load()

    save()
        __asm volatile ("ldr r0, [r1, #0]\n");
        __asm volatile ("mov r1, r12\n");
        __asm volatile ("add r3, sp, #12\n");

        link(blx, &$objc_msgSend$)
    load()

    call(bx, _objc_msgSendSuper2_stret)
}*/

MSInitialize {
    logFile = fopen("/tmp/inspectivec_calls.log", "a");

    banned_.insert(@selector(alloc));
    banned_.insert(@selector(autorelease));
    banned_.insert(@selector(initialize));
    banned_.insert(@selector(class));
    banned_.insert(@selector(copy));
    banned_.insert(@selector(copyWithZone:));
    banned_.insert(@selector(dealloc));
    banned_.insert(@selector(delegate));
    banned_.insert(@selector(isKindOfClass:));
    banned_.insert(@selector(lock));
    banned_.insert(@selector(retain));
    banned_.insert(@selector(release));
    banned_.insert(@selector(unlock));
    banned_.insert(@selector(UTF8String));
    banned_.insert(@selector(count));
    banned_.insert(@selector(doubleValue));

    //MSImageRef libobjc(MSGetImageByName("/usr/lib/libobjc.A.dylib"));
    MSHookFunction(&objc_msgSend, (id (*)(id, SEL, ...))&replacementObjc_msgSend, &orig_objc_msgSend);
    fprintf(logFile, "POST: <%p> <%p> <%p>\n", &objc_msgSend, &replacementObjc_msgSend, orig_objc_msgSend);

    /*
    MSHookFunction(&objc_msgSend_stret, (void (*)(id, SEL, ...)) MSHake(objc_msgSend_stret));

    MSHookFunction(&objc_msgSendSuper, (id (*)(struct objc_super *, SEL, ...)) MSHake(objc_msgSendSuper));
    MSHookFunction(&objc_msgSendSuper_stret, (void (*)(struct objc_super *, SEL, ...)) MSHake(objc_msgSendSuper_stret));

    MSHookFunction(libobjc, "objc_msgSendSuper2", (id (*)(struct objc_super *, SEL, ...)) MSHake(objc_msgSendSuper2));
    MSHookFunction(libobjc, "objc_msgSendSuper2_stret", (void (*)(struct objc_super *, SEL, ...)) MSHake(objc_msgSendSuper2_stret));
    */
}
