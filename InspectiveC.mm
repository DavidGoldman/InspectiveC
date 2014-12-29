#include <substrate.h>
#include <Foundation/Foundation.h>

#include <cstdarg>
#include <cstdio>

#include <set>
#include <sys/types.h>
#include <sys/stat.h>

#include <pthread.h>

#include "hashmap.h"

#define MAX_PATH_LENGTH 1024

#define DEFAULT_CALLSTACK_DEPTH 128
#define CALLSTACK_DEPTH_INCREMENT 64

static HashMapRef objectsSet;
static HashMapRef classSet;
static HashMapRef selsSet;
static pthread_rwlock_t lock = PTHREAD_RWLOCK_INITIALIZER;
static pthread_key_t threadKey;

static int pointerEquality(void *a, void *b) {
  uintptr_t ia = reinterpret_cast<uintptr_t>(a);
  uintptr_t ib = reinterpret_cast<uintptr_t>(b);
  return ia == ib;
}

static unsigned pointerHash(void *v) {
  uintptr_t a = reinterpret_cast<uintptr_t>(v);
  a = (a + 0x7ed55d16) + (a << 12);
  a = (a ^ 0xc761c23c) ^ (a >> 19);
  a = (a + 0x165667b1) + (a << 5);
  a = (a + 0xd3a2646c) ^ (a << 9);
  a = (a + 0xfd7046c5) + (a << 3);
  a = (a ^ 0xb55a4f09) ^ (a >> 16);
  return (unsigned)a;
}

#define RLOCK pthread_rwlock_rdlock(&lock)
#define WLOCK pthread_rwlock_wrlock(&lock)
#define UNLOCK pthread_rwlock_unlock(&lock)

// Inspective C Public API.

extern "C" void InspectiveC_watchObject(id obj) {
  WLOCK;
  HMPut(objectsSet, (void *)obj, (void *)obj);
  UNLOCK;
}
extern "C" void InspectiveC_unwatchObject(id obj) {
  WLOCK;
  HMRemove(objectsSet, (void *)obj);
  UNLOCK;
}

extern "C" void InspectiveC_watchInstancesOfClass(Class clazz) {
  WLOCK;
  HMPut(classSet, (void *)clazz, (void *)clazz);
  UNLOCK;
}
extern "C" void InspectiveC_unwatchInstancesOfClass(Class clazz) {
  WLOCK;
  HMRemove(classSet, (void *)clazz);
  UNLOCK;
}

extern "C" void InspectiveC_watchSelector(SEL _cmd) {
  WLOCK;
  HMPut(selsSet, (void *)_cmd, (void *)_cmd);
  UNLOCK;
}
extern "C" void InspectiveC_unwatchSelector(SEL _cmd) {
  WLOCK;
  HMRemove(selsSet, (void *)_cmd);
  UNLOCK;
}

typedef struct CallRecord_ {
  id obj;
  SEL _cmd;
  uint32_t lr;
} CallRecord;

typedef struct ThreadCallStack_ {
  FILE *file;
  CallRecord *stack;
  int allocatedLength;
  int index;
} ThreadCallStack;

extern "C" char ***_NSGetArgv(void);

static FILE * newFileForThread() {
  const char *exeName = **_NSGetArgv();
  if (exeName == NULL) {
    exeName = "(NULL)";
  } else if (const char *slash = strrchr(exeName, '/')) {
    exeName = slash + 1;
  }

  pid_t pid = getpid();

  char path[MAX_PATH_LENGTH];
  mkdir("/tmp/InspectiveC", 0755);
  sprintf(path, "/tmp/InspectiveC/%s", exeName);
  mkdir(path, 0755);
  if (pthread_main_np()) {
    sprintf(path, "/tmp/InspectiveC/%s/%d_main.log", exeName, pid);
  } else {
    mach_port_t tid = pthread_mach_thread_np(pthread_self());
    sprintf(path, "/tmp/InspectiveC/%s/%d_t%u.log", exeName, pid, tid);
  }
  return fopen(path, "a");
}

static inline ThreadCallStack * getThreadCallStack() {
  ThreadCallStack *cs = (ThreadCallStack *)pthread_getspecific(threadKey);
  if (cs == NULL) {
    cs = (ThreadCallStack *)malloc(sizeof(ThreadCallStack));
    cs->file = newFileForThread();
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

// Hooking magic.

// Called in our replacementObjc_msgSend before calling the original objc_msgSend.
// This pushes a CallRecord to our stack, most importantly saving the lr.
void preObjc_msgSend(id self, uint32_t lr, SEL _cmd, va_list args) {
  pushCallRecord(self, lr, _cmd);

  if (self) {
    Class clazz = object_getClass(self);
    RLOCK;
    // Critical section - check for hits.
    int isWatchedObject = (HMGet(objectsSet, (void *)self) != NULL);
    int isWatchedClass = (HMGet(classSet, (void *)clazz) != NULL);
    int isWatchedSel = (HMGet(selsSet, (void *)_cmd) != NULL);
    UNLOCK;
    if (isWatchedObject || isWatchedClass || isWatchedSel) {
      FILE *logFile = getThreadCallStack()->file;
      if (logFile) {
        log(logFile, self, _cmd);
      }
    }
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

  objectsSet = HMCreate(&pointerEquality, &pointerHash);
  classSet = HMCreate(&pointerEquality, &pointerHash);
  selsSet = HMCreate(&pointerEquality, &pointerHash);

  MSHookFunction(&objc_msgSend, (id (*)(id, SEL, ...))&replacementObjc_msgSend, &orig_objc_msgSend);
}
