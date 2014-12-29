#include <substrate.h>
#include <Foundation/Foundation.h>

#include <cstdarg>
#include <cstdio>

#include <set>
#include <sys/types.h>
#include <sys/stat.h>

#include <pthread.h>

#define MAX_PATH_LENGTH 1024

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

unsigned long msgCounter = 0;

// Hooking magic.

// Called in our replacementObjc_msgSend before calling the original objc_msgSend.
// This pushes a CallRecord to our stack, most importantly saving the lr.
void preObjc_msgSend(id self, uint32_t lr, SEL _cmd, va_list args) {
  pushCallRecord(self, lr, _cmd);

  if (bannedSels.find(_cmd) != bannedSels.end())
    return;
  FILE *logFile = getThreadCallStack()->file;
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
}
