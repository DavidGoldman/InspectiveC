#include <substrate.h>
#include <Foundation/Foundation.h>

#include <cstdarg>
#include <cstdio>

#include <sys/types.h>
#include <sys/stat.h>

#include <pthread.h>

#include "hashmap.h"
#include "logging.h"

// Optional - comment this out if you want to log on ALL threads (laggy due to rw-locks).
#define MAIN_THREAD_ONLY

#define MAX_PATH_LENGTH 1024

#define DEFAULT_CALLSTACK_DEPTH 128
#define CALLSTACK_DEPTH_INCREMENT 64

#define DEFAULT_MAX_RELATIVE_RECURSIVE_DESCENT_DEPTH 64

#define RLOCK pthread_rwlock_rdlock(&lock)
#define WLOCK pthread_rwlock_wrlock(&lock)
#define UNLOCK pthread_rwlock_unlock(&lock)

#if __arm64__
#define arg_list pa_list
#else
#define arg_list va_list
#endif

// The original objc_msgSend.
static id (*orig_objc_msgSend)(id, SEL, ...);

// These classes support handling of void *s using callback functions, yet their methods
// accept (fake) ids. =/ i.e. objectForKey: and setObject:forKey: are dangerous for us because what
// looks like an id can be a regular old int and crash our program...
static Class NSMapTable_Class;
static Class NSHashTable_Class;

// We have to call [<self> class] when logging to make sure that the class is initialized.
static SEL class_SEL = @selector(class);

static HashMapRef objectsSet;
static HashMapRef classSet;
static HashMapRef selsSet;
static pthread_key_t threadKey;
static const char *directory;

// Max callstack depth to log after the last hit.
static int maxRelativeRecursiveDepth = DEFAULT_MAX_RELATIVE_RECURSIVE_DESCENT_DEPTH;

#ifndef MAIN_THREAD_ONLY
static pthread_rwlock_t lock = PTHREAD_RWLOCK_INITIALIZER;
#endif

// HashMap functions.
static int pointerEquality(void *a, void *b) {
  uintptr_t ia = reinterpret_cast<uintptr_t>(a);
  uintptr_t ib = reinterpret_cast<uintptr_t>(b);
  return ia == ib;
}

#ifdef __arm64__
// 64 bit hash from https://gist.github.com/badboy/6267743.
static inline NSUInteger pointerHash(void *v) {
  uintptr_t key = reinterpret_cast<uintptr_t>(v);
  key = (~key) + (key << 21); // key = (key << 21) - key - 1;
  key = key ^ (key >> 24);
  key = (key + (key << 3)) + (key << 8); // key * 265
  key = key ^ (key >> 14);
  key = (key + (key << 2)) + (key << 4); // key * 21
  key = key ^ (key >> 28);
  key = key + (key << 31);
  return key;
}
#else
// Robert Jenkin's 32 bit int hash.
static inline NSUInteger pointerHash(void *v) {
  uintptr_t a = reinterpret_cast<uintptr_t>(v);
  a = (a + 0x7ed55d16) + (a << 12);
  a = (a ^ 0xc761c23c) ^ (a >> 19);
  a = (a + 0x165667b1) + (a << 5);
  a = (a + 0xd3a2646c) ^ (a << 9);
  a = (a + 0xfd7046c5) + (a << 3);
  a = (a ^ 0xb55a4f09) ^ (a >> 16);
  return (NSUInteger)a;
}
#endif

// Shared structures.
typedef struct CallRecord_ {
  id obj;
  SEL _cmd;
  uintptr_t lr;
  int prevHitIndex; // Only used if isWatchHit is set.
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
  int lastHitIndex;
  char isLoggingEnabled;
} ThreadCallStack;

// Inspective C Public API.

#ifdef MAIN_THREAD_ONLY

extern "C" void InspectiveC_watchObject(id obj) {
  if (obj == nil) {
    return;
  }
  if (pthread_main_np()) {
    HMPut(objectsSet, (void *)obj, (void *)obj);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^(){
        HMPut(objectsSet, (void *)obj, (void *)obj);
    });
  }
}
extern "C" void InspectiveC_unwatchObject(id obj) {
  if (obj == nil) {
    return;
  }
  if (pthread_main_np()) {
    HMRemove(objectsSet, (void *)obj);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^(){
        HMRemove(objectsSet, (void *)obj);
    });
  }
}

extern "C" void InspectiveC_watchInstancesOfClass(Class clazz) {
  if (clazz == nil) {
    return;
  }
  if (pthread_main_np()) {
    HMPut(classSet, (void *)clazz, (void *)clazz);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^(){
        HMPut(classSet, (void *)clazz, (void *)clazz);
    });
  }
}
extern "C" void InspectiveC_unwatchInstancesOfClass(Class clazz) {
  if (clazz == nil) {
    return;
  }
  if (pthread_main_np()) {
    HMRemove(classSet, (void *)clazz);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^(){
        HMRemove(classSet, (void *)clazz);
    });
  }
}

extern "C" void InspectiveC_watchSelector(SEL _cmd) {
  if (_cmd == NULL) {
    return;
  }
  if (pthread_main_np()) {
    HMPut(selsSet, (void *)_cmd, (void *)_cmd);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^(){
        HMPut(selsSet, (void *)_cmd, (void *)_cmd);
    });
  }
}
extern "C" void InspectiveC_unwatchSelector(SEL _cmd) {
  if (_cmd == NULL) {
    return;
  }
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
  if (obj == nil) {
    return;
  }
  WLOCK;
  HMPut(objectsSet, (void *)obj, (void *)obj);
  UNLOCK;
}
extern "C" void InspectiveC_unwatchObject(id obj) {
  if (obj == nil) {
    return;
  }
  WLOCK;
  HMRemove(objectsSet, (void *)obj);
  UNLOCK;
}

extern "C" void InspectiveC_watchInstancesOfClass(Class clazz) {
  if (clazz == nil) {
    return;
  }
  WLOCK;
  HMPut(classSet, (void *)clazz, (void *)clazz);
  UNLOCK;
}
extern "C" void InspectiveC_unwatchInstancesOfClass(Class clazz) {
  if (clazz == nil) {
    return;
  }
  WLOCK;
  HMRemove(classSet, (void *)clazz);
  UNLOCK;
}

extern "C" void InspectiveC_watchSelector(SEL _cmd) {
  if (_cmd == NULL) {
    return;
  }
  WLOCK;
  HMPut(selsSet, (void *)_cmd, (void *)_cmd);
  UNLOCK;
}
extern "C" void InspectiveC_unwatchSelector(SEL _cmd) {
  if (_cmd == NULL) {
    return;
  }
  WLOCK;
  HMRemove(selsSet, (void *)_cmd);
  UNLOCK;
}

#endif

static inline ThreadCallStack * getThreadCallStack();

// Semi Public API - used to temporarily disable logging.

extern "C" void InspectiveC_enableLogging() {
  ThreadCallStack *cs = getThreadCallStack();
  cs->isLoggingEnabled = 1;
}

extern "C" void InspectiveC_disableLogging() {
  ThreadCallStack *cs = getThreadCallStack();
  cs->isLoggingEnabled = 0;
}

extern "C" int InspectiveC_isLoggingEnabled() {
  ThreadCallStack *cs = getThreadCallStack();
  return (int)cs->isLoggingEnabled;
}

// Shared functions.
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

  sprintf(path, "%s/InspectiveC", directory);
  mkdir(path, 0755);
  sprintf(path, "%s/InspectiveC/%s", directory, exeName);
  mkdir(path, 0755);

  if (pthread_main_np()) {
    sprintf(path, "%s/InspectiveC/%s/%d_main.log", directory, exeName, pid);
  } else {
    mach_port_t tid = pthread_mach_thread_np(pthread_self());
    sprintf(path, "%s/InspectiveC/%s/%d_t%u.log", directory, exeName, pid, tid);
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
    cs->isLoggingEnabled = (cs->file != NULL);
    cs->spacesStr = (char *)malloc(DEFAULT_CALLSTACK_DEPTH + 1);
    memset(cs->spacesStr, ' ', DEFAULT_CALLSTACK_DEPTH);
    cs->spacesStr[DEFAULT_CALLSTACK_DEPTH] = '\0';
    cs->stack = (CallRecord *)calloc(DEFAULT_CALLSTACK_DEPTH, sizeof(CallRecord));
    cs->allocatedLength = DEFAULT_CALLSTACK_DEPTH;
    cs->index = cs->lastPrintedIndex = cs->lastHitIndex = -1;
    cs->numWatchHits = 0;
    pthread_setspecific(threadKey, cs);
  }
  return cs;
}

static void destroyThreadCallStack(void *ptr) {
  ThreadCallStack *cs = (ThreadCallStack *)ptr;
  if (cs->file) {
    fclose(cs->file);
  }
  free(cs->spacesStr);
  free(cs->stack);
  free(cs);
}

static inline void pushCallRecord(id obj, uintptr_t lr, SEL _cmd, ThreadCallStack *cs) {
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

static inline void log(FILE *file, id obj, SEL _cmd, char *spaces) {
  Class kind = object_getClass(obj);
  bool isMetaClass = class_isMetaClass(kind);
  if (isMetaClass) {
    fprintf(file, "%s%s+|%s %s|\n", spaces, spaces, class_getName(kind), sel_getName(_cmd));
  } else {
    fprintf(file, "%s%s-|%s %s| @<%p>\n", spaces, spaces, class_getName(kind), sel_getName(_cmd), (void *)obj);
  }
}

// Returns orig_objc_msgSend in r0. Sadly I couldn't figure out a way to "blx orig_objc_msgSend"
// and moving this directly inside the replacementObjc_msgSend method generates assembly that
// overrides r0 before can we push it... without this you're gonna have a bad time. 
uintptr_t getOrigObjc_msgSend() {
  return reinterpret_cast<uintptr_t>(orig_objc_msgSend);
}

static inline BOOL isKindOfClass(Class selfClass, Class clazz) {
  for (Class candidate = selfClass; candidate; candidate = class_getSuperclass(candidate)) {
    if (candidate == clazz) {
      return YES;
    }
  }
  return NO;
}

static inline BOOL classSupportsArbitraryPointerTypes(Class clazz) {
  return isKindOfClass(clazz, NSMapTable_Class) || isKindOfClass(clazz, NSHashTable_Class);
}

static inline void logWatchedHit(ThreadCallStack *cs, FILE *file, id obj, SEL _cmd, char *spaces, arg_list &args) {
  Class kind = object_getClass(obj);
  bool isMetaClass = class_isMetaClass(kind);
  Method method = class_getInstanceMethod(kind, _cmd);

  if (method) {
    if (isMetaClass) {
      fprintf(file, "%s%s***+|%s %s|", spaces, spaces, class_getName(kind), sel_getName(_cmd));
    } else {
      fprintf(file, "%s%s***-|%s@<%p> %s|", spaces, spaces, class_getName(kind), (void *)obj, sel_getName(_cmd));
    }
    const char *typeEncoding = method_getTypeEncoding(method);
    if (!typeEncoding || classSupportsArbitraryPointerTypes(kind)) {
      fprintf(file, " ~NO ENCODING~***\n");
      return;
    }

    cs->isLoggingEnabled = 0;
    @try {
      NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:typeEncoding];
      const NSUInteger numberOfArguments = [signature numberOfArguments];
      for (NSUInteger index = 2; index < numberOfArguments; ++index) {
        const char *type = [signature getArgumentTypeAtIndex:index];
        fprintf(file, " ");
        if (!logArgument(file, type, args)) { // Can't understand arg - probably a struct.
          fprintf(file, "~BAIL on \"%s\"~", type);
          break;
        }
      }
    } @catch(NSException *e) {
      fprintf(file, "~BAD ENCODING~");
    }
    fprintf(file, "***\n");
    cs->isLoggingEnabled = 1;
  }
}

static inline void logObjectAndArgs(ThreadCallStack *cs, FILE *file, id obj, SEL _cmd, char *spaces, arg_list &args) {
  // Call [<obj> class] to make sure the class is initialized.
  Class kind = ((Class (*)(id, SEL))orig_objc_msgSend)(obj, class_SEL);
  bool isMetaClass = (kind == obj);

  Method method = (isMetaClass) ? class_getClassMethod(kind, _cmd) : class_getInstanceMethod(kind, _cmd);
  if (method) {
    if (isMetaClass) {
      fprintf(file, "%s%s+|%s %s|", spaces, spaces, class_getName(kind), sel_getName(_cmd));
    } else {
      fprintf(file, "%s%s-|%s@<%p> %s|", spaces, spaces, class_getName(kind), (void *)obj, sel_getName(_cmd));
    }
    const char *typeEncoding = method_getTypeEncoding(method);
    if (!typeEncoding || classSupportsArbitraryPointerTypes(kind)) {
      fprintf(file, " ~NO ENCODING~\n");
      return;
    }

    cs->isLoggingEnabled = 0;
    @try {
      NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:typeEncoding];
      const NSUInteger numberOfArguments = [signature numberOfArguments];
      for (NSUInteger index = 2; index < numberOfArguments; ++index) {
        const char *type = [signature getArgumentTypeAtIndex:index];
        fprintf(file, " ");
        if (!logArgument(file, type, args)) { // Can't understand arg - probably a struct.
          fprintf(file, "~BAIL on \"%s\"~", type);
          break;
        }
      }
    } @catch(NSException *e) {
      fprintf(file, "~BAD ENCODING~");
    }
    fprintf(file, "\n");
    cs->isLoggingEnabled = 1;
  }
}

static inline void onWatchHit(ThreadCallStack *cs, arg_list &args) {
  const int hitIndex = cs->index;
  CallRecord *hitRecord = &cs->stack[hitIndex];
  hitRecord->isWatchHit = 1;
  hitRecord->prevHitIndex = cs->lastHitIndex;
  cs->lastHitIndex = hitIndex;
  ++cs->numWatchHits;

  FILE *logFile = cs->file;
  if (logFile) {
    // Log previous calls if necessary.
    for (int i = cs->lastPrintedIndex + 1; i < hitIndex; ++i) {
      CallRecord record = cs->stack[i];
      // Modify spacesStr.
      char *spaces = cs->spacesStr;
      spaces[i] = '\0';
      log(logFile, record.obj, record._cmd, spaces);
      // Clean up spacesStr.
      spaces[i] = ' ';
    }
    // Log the hit call.
    char *spaces = cs->spacesStr;
    spaces[hitIndex] = '\0';
    logWatchedHit(cs, logFile, hitRecord->obj, hitRecord->_cmd, spaces, args);
    // Clean up spacesStr.
    spaces[hitIndex] = ' ';
    // Lastly, set the lastPrintedIndex.
    cs->lastPrintedIndex = hitIndex;
  }
}

static inline void onNestedCall(ThreadCallStack *cs, arg_list &args) {
  const int curIndex = cs->index;
  FILE *logFile = cs->file;
  if (logFile && (curIndex - cs->lastHitIndex) <= maxRelativeRecursiveDepth) {
    // Log the current call.
    char *spaces = cs->spacesStr;
    spaces[curIndex] = '\0';
    CallRecord curRecord = cs->stack[curIndex];
    logObjectAndArgs(cs, logFile, curRecord.obj, curRecord._cmd, spaces, args);
    spaces[curIndex] = ' ';
    // Lastly, set the lastPrintedIndex.
    cs->lastPrintedIndex = curIndex;
  }
}

// Called in our replacementObjc_msgSend after calling the original objc_msgSend.
// This returns the lr in r0/x0.
uintptr_t postObjc_msgSend() {
  ThreadCallStack *cs = (ThreadCallStack *)pthread_getspecific(threadKey);
  CallRecord *record = popCallRecord(cs);
  if (record->isWatchHit) {
    --cs->numWatchHits;
    cs->lastHitIndex = record->prevHitIndex;
  }
  if (cs->lastPrintedIndex > cs->index) {
    cs->lastPrintedIndex = cs->index;
  }
  return record->lr;
}

// 32-bit vs 64-bit stuff.
#ifdef __arm64__
#include "InspectiveCarm64.mm"
#else
#include "InspectiveCarm32.mm"
#endif

MSInitialize {
  pthread_key_create(&threadKey, &destroyThreadCallStack);

  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  NSString *path = [paths firstObject];
  directory = [path UTF8String];
  NSLog(@"[InspectiveC] Loading - Directory is \"%s\"", directory);

  NSMapTable_Class = [objc_getClass("NSMapTable") class];
  NSHashTable_Class = [objc_getClass("NSHashTable") class];

  objectsSet = HMCreate(&pointerEquality, &pointerHash);
  classSet = HMCreate(&pointerEquality, &pointerHash);
  selsSet = HMCreate(&pointerEquality, &pointerHash);

  MSHookFunction(&objc_msgSend, (id (*)(id, SEL, ...))&replacementObjc_msgSend, &orig_objc_msgSend);
}
