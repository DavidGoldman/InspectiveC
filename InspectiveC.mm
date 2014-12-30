#include <substrate.h>
#include <Foundation/Foundation.h>

#include <cstdarg>
#include <cstdio>

#include <sys/types.h>
#include <sys/stat.h>

#include <pthread.h>

#include "hashmap.h"

#define MAIN_THREAD_ONLY

#define MAX_PATH_LENGTH 1024

#define DEFAULT_CALLSTACK_DEPTH 128
#define CALLSTACK_DEPTH_INCREMENT 64

static HashMapRef objectsSet;
static HashMapRef classSet;
static HashMapRef selsSet;
static pthread_key_t threadKey;

#ifndef MAIN_THREAD_ONLY
static pthread_rwlock_t lock = PTHREAD_RWLOCK_INITIALIZER;
#endif

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

#ifdef MAIN_THREAD_ONLY

extern "C" void InspectiveC_watchObject(id obj) {
  if (pthread_main_np()) {
    HMPut(objectsSet, (void *)obj, (void *)obj);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^(){
        HMPut(objectsSet, (void *)obj, (void *)obj);
    });
  }
}
extern "C" void InspectiveC_unwatchObject(id obj) {
  if (pthread_main_np()) {
    HMRemove(objectsSet, (void *)obj);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^(){
        HMRemove(objectsSet, (void *)obj);
    });
  }
}

extern "C" void InspectiveC_watchInstancesOfClass(Class clazz) {
  if (pthread_main_np()) {
    HMPut(classSet, (void *)clazz, (void *)clazz);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^(){
        HMPut(classSet, (void *)clazz, (void *)clazz);
    });
  }
}
extern "C" void InspectiveC_unwatchInstancesOfClass(Class clazz) {
  if (pthread_main_np()) {
    HMRemove(classSet, (void *)clazz);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^(){
        HMRemove(classSet, (void *)clazz);
    });
  }
}

extern "C" void InspectiveC_watchSelector(SEL _cmd) {
  if (pthread_main_np()) {
    HMPut(selsSet, (void *)_cmd, (void *)_cmd);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^(){
        HMPut(selsSet, (void *)_cmd, (void *)_cmd);
    });
  }
}
extern "C" void InspectiveC_unwatchSelector(SEL _cmd) {
  if (pthread_main_np()) {
    HMRemove(selsSet, (void *)_cmd);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^(){
        HMRemove(selsSet, (void *)_cmd);
    });
  }
}

#else // Multithreaded - uses rw locks.

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

#endif

typedef struct CallRecord_ {
  id obj;
  SEL _cmd;
  uint32_t lr;
  char isWatchHit;
} CallRecord;

typedef struct ThreadCallStack_ {
  FILE *file;
  char *spacesStr;
  CallRecord *stack;
  int allocatedLength;
  int index;
  int numWatchHits;
  int lastPrintedIndex;
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
#ifdef MAIN_THREAD_ONLY
    cs->file = (pthread_main_np()) ? newFileForThread() : NULL;
#else
    cs->file = newFileForThread();
#endif
    cs->spacesStr = (char *)malloc(DEFAULT_CALLSTACK_DEPTH + 1);
    memset(cs->spacesStr, ' ', DEFAULT_CALLSTACK_DEPTH);
    cs->spacesStr[DEFAULT_CALLSTACK_DEPTH] = '\0';
    cs->stack = (CallRecord *)calloc(DEFAULT_CALLSTACK_DEPTH, sizeof(CallRecord));
    cs->allocatedLength = DEFAULT_CALLSTACK_DEPTH;
    cs->index = cs->lastPrintedIndex = -1;
    cs->numWatchHits = 0;
    pthread_setspecific(threadKey, cs);
  }
  return cs;
}

static inline void pushCallRecord(id obj, uint32_t lr, SEL _cmd, ThreadCallStack *cs) {
  int nextIndex = (++cs->index);
  if (nextIndex >= cs->allocatedLength) {
    cs->allocatedLength += CALLSTACK_DEPTH_INCREMENT;
    cs->stack = (CallRecord *)realloc(cs->stack, cs->allocatedLength * sizeof(CallRecord));
    cs->spacesStr = (char *)realloc(cs->spacesStr, cs->allocatedLength + 1);
    memset(cs->spacesStr, ' ', cs->allocatedLength);
    cs->spacesStr[cs->allocatedLength] = '\0';
  }
  CallRecord *newRecord = &cs->stack[nextIndex];
  newRecord->obj = obj;
  newRecord->_cmd = _cmd;
  newRecord->lr = lr;
  newRecord->isWatchHit = 0;
}

static inline CallRecord * popCallRecord(ThreadCallStack *cs) {
  return &cs->stack[cs->index--];
}

static void destroyThreadCallStack(void *ptr) {
  ThreadCallStack *cs = (ThreadCallStack *)ptr;
  free(cs->stack);
  free(cs);
}

static inline void log(FILE *file, id obj, SEL _cmd, char *spaces) {
  Class kind = object_getClass(obj);
  fprintf(file, "%s%s<%s@%p>\t%s\n", spaces, spaces, class_getName(kind), (void *)obj, sel_getName(_cmd));
}

static inline void logWatchedHit(FILE *file, id obj, SEL _cmd, char *spaces) {
  Class kind = object_getClass(obj);
  fprintf(file, "%s%s**<%s@%p>\t%s**\n", spaces, spaces, class_getName(kind), (void *)obj, sel_getName(_cmd));
}

static inline void onWatchHit(ThreadCallStack *cs) {
  const int hitIndex = cs->index;
  CallRecord *hitRecord = &cs->stack[hitIndex];
  hitRecord->isWatchHit = 1;
  ++cs->numWatchHits;

  FILE *logFile = cs->file;
  if (logFile) {
    // Log previous calls if necessary.
    if (cs->numWatchHits == 1) {
      for (int i = cs->lastPrintedIndex + 1; i < hitIndex; ++i) {
        CallRecord record = cs->stack[i];
        // Modify spacesStr.
        char *spaces = cs->spacesStr;
        spaces[i] = '\0';
        log(logFile, record.obj, record._cmd, spaces);
        // Clean up spacesStr.
        spaces[i] = ' ';
      }
    }
    // Log the hit call.
    char *spaces = cs->spacesStr;
    spaces[hitIndex] = '\0';
    logWatchedHit(logFile, hitRecord->obj, hitRecord->_cmd, spaces);
    // Clean up spacesStr.
    spaces[hitIndex] = ' ';
    // Lastly, set the lastPrintedIndex.
    cs->lastPrintedIndex = hitIndex;
  }
}

static inline void onNestedCall(ThreadCallStack *cs) {
  const int curIndex = cs->index;
  FILE *logFile = cs->file;
  if (logFile) {
    // Log the current call.
    char *spaces = cs->spacesStr;
    spaces[curIndex] = '\0';
    CallRecord curRecord = cs->stack[curIndex];
    log(logFile, curRecord.obj, curRecord._cmd, spaces);
    spaces[curIndex] = ' ';
    // Don't need to set the lastPrintedIndex as it is only useful on the first hit, which has
    // already occurred. 
  }
}

// Hooking magic.

// Called in our replacementObjc_msgSend before calling the original objc_msgSend.
// This pushes a CallRecord to our stack, most importantly saving the lr.
void preObjc_msgSend(id self, uint32_t lr, SEL _cmd, va_list args) {
  ThreadCallStack *cs = getThreadCallStack();
  pushCallRecord(self, lr, _cmd, cs);

#ifdef MAIN_THREAD_ONLY
  if (self && pthread_main_np()) {
    Class clazz = object_getClass(self);
    int isWatchedObject = (HMGet(objectsSet, (void *)self) != NULL);
    int isWatchedClass = (HMGet(classSet, (void *)clazz) != NULL);
    int isWatchedSel = (HMGet(selsSet, (void *)_cmd) != NULL);
    if (isWatchedObject && _cmd == @selector(dealloc)) {
      HMRemove(objectsSet, (void *)self);
    }
    if (isWatchedObject || isWatchedClass || isWatchedSel) {
      onWatchHit(cs);
    } else if (cs->numWatchHits > 0) {
      onNestedCall(cs);
    }
  }
#else
  if (self) {
    Class clazz = object_getClass(self);
    RLOCK;
    // Critical section - check for hits.
    int isWatchedObject = (HMGet(objectsSet, (void *)self) != NULL);
    int isWatchedClass = (HMGet(classSet, (void *)clazz) != NULL);
    int isWatchedSel = (HMGet(selsSet, (void *)_cmd) != NULL);
    UNLOCK;
    if (isWatchedObject && _cmd == @selector(dealloc)) {
      WLOCK;
      HMRemove(objectsSet, (void *)self);
      UNLOCK;
    }
    if (isWatchedObject || isWatchedClass || isWatchedSel) {
      onWatchHit(cs);
    } else if (cs->numWatchHits > 0) {
      onNestedCall(cs);
    }
  }
#endif
}

// Called in our replacementObjc_msgSend after calling the original objc_msgSend.
// This returns the lr in r0.
uint32_t postObjc_msgSend() {
  ThreadCallStack *cs = (ThreadCallStack *)pthread_getspecific(threadKey);
  CallRecord *record = popCallRecord(cs);
  if (record->isWatchHit) {
    --cs->numWatchHits;
  }
  if (cs->lastPrintedIndex > cs->index) {
    cs->lastPrintedIndex = cs->index;
  }
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
