
struct PointerAndInt_ {
  uintptr_t ptr;
  int i;
};

struct RegState_ {
  uint64_t x0;
  uint64_t x1;
  uint64_t x2;
  uint64_t x3;
  uint64_t x4;
  uint64_t x5;
  uint64_t x6;
  uint64_t x7;
  uint64_t x8;
  uint64_t lr;

  __int128_t q0;
  __int128_t q1;
  __int128_t q2;
  __int128_t q3;
  __int128_t q4;
  __int128_t q5;
  __int128_t q6;
  __int128_t q7;
};

static inline void onNestedCall(ThreadCallStack *cs) {
  const int curIndex = cs->index;
  FILE *logFile = cs->file;
  if (logFile) {
    // Log the current call.
    char *spaces = cs->spacesStr;
    spaces[curIndex] = '\0';
    CallRecord curRecord = cs->stack[curIndex];

    // Call [<obj> class] to make sure the class is initialized.
    ((Class (*)(id, SEL))orig_objc_msgSend)(curRecord.obj, class_SEL);

    log(logFile, curRecord.obj, curRecord._cmd, spaces);
    spaces[curIndex] = ' ';
    // Don't need to set the lastPrintedIndex as it is only useful on the first hit, which has
    // already occurred. 
  }
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
    logHit(logFile, hitRecord->obj, hitRecord->_cmd, spaces);
    // Clean up spacesStr.
    spaces[hitIndex] = ' ';
    // Lastly, set the lastPrintedIndex.
    cs->lastPrintedIndex = hitIndex;
  }
}

// arm64 hooking magic.

// Called in our replacementObjc_msgSend before calling the original objc_msgSend.
// This pushes a CallRecord to our stack, most importantly saving the lr.
// Returns orig_objc_msgSend in x0 and isLoggingEnabled in x1.
struct PointerAndInt_ preObjc_msgSend(id self, uintptr_t lr, SEL _cmd, struct RegState_ *regs) {
  // Testing our regs.
  self = (id)regs->x0;
  _cmd = (SEL)regs->x1;
  lr = (uintptr_t)regs->lr;
  ThreadCallStack *cs = getThreadCallStack();
  if (!cs->isLoggingEnabled) { // Not enabled, just return.
    return (struct PointerAndInt_) {reinterpret_cast<uintptr_t>(orig_objc_msgSend), 0};
  }
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
  return (struct PointerAndInt_) {reinterpret_cast<uintptr_t>(orig_objc_msgSend), 1};
}

// Called in our replacementObjc_msgSend after calling the original objc_msgSend.
// This returns the lr in x0.
uintptr_t postObjc_msgSend() {
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

// Our replacement objc_msgSend (arm64).
//
// See:
// https://blog.nelhage.com/2010/10/amd64-and-va_arg/
// http://infocenter.arm.com/help/topic/com.arm.doc.ihi0055b/IHI0055B_aapcs64.pdf
// https://developer.apple.com/library/ios/documentation/Xcode/Conceptual/iPhoneOSABIReference/Articles/ARM64FunctionCallingConventions.html
__attribute__((__naked__))
static volatile void replacementObjc_msgSend() {
  __asm__ volatile (
    // push {q0-q7}
      "stp q6, q7, [sp, #-32]!\n"
      "stp q4, q5, [sp, #-32]!\n"
      "stp q2, q3, [sp, #-32]!\n"
      "stp q0, q1, [sp, #-32]!\n"
    // push {x0-x8, lr}
      "stp x8, lr, [sp, #-16]!\n" // Not sure if x8 needed - push for alignment.
      "stp x6, x7, [sp, #-16]!\n"
      "stp x4, x5, [sp, #-16]!\n"
      "stp x2, x3, [sp, #-16]!\n"
      "stp x0, x1, [sp, #-16]!\n"
    // Swap args around for call.
      "mov x2, x1\n"
      "mov x1, lr\n"
      "mov x3, sp\n"
    // Call preObjc_msgSend which puts orig_objc_msgSend into x0 and isLoggingEnabled into x1.
      "bl __Z15preObjc_msgSendP11objc_objectmP13objc_selectorP9RegState_\n"
      "mov x9, x0\n"
      "mov x10, x1\n"
      "tst x10, x10\n" // Set condition code for later branch.
    // pop {x0-x8, lr}
      "ldp x0, x1, [sp], #16\n"
      "ldp x2, x3, [sp], #16\n"
      "ldp x4, x5, [sp], #16\n"
      "ldp x6, x7, [sp], #16\n"
      "ldp x8, lr, [sp], #16\n"
    // pop {q0-q7}
      "ldp q0, q1, [sp], #32\n"
      "ldp q2, q3, [sp], #32\n"
      "ldp q4, q5, [sp], #32\n"
      "ldp q6, q7, [sp], #32\n"
    // Make sure it's enabled.
      "b.eq Lpassthrough\n"
    // Call through to the original objc_msgSend.
      "blr x9\n"
    // push {x0-x9}
      "stp x0, x1, [sp, #-16]!\n"
      "stp x2, x3, [sp, #-16]!\n"
      "stp x4, x5, [sp, #-16]!\n"
      "stp x6, x7, [sp, #-16]!\n"
      "stp x8, x9, [sp, #-16]!\n" // not sure if needed - push for alignment.
    // push {q0-q7}
      "stp q0, q1, [sp, #-32]!\n"
      "stp q2, q3, [sp, #-32]!\n"
      "stp q4, q5, [sp, #-32]!\n"
      "stp q6, q7, [sp, #-32]!\n"
    // Call our postObjc_msgSend hook.
      "bl __Z16postObjc_msgSendv\n"
      "mov lr, x0\n"
    // pop {q0-q7}
      "ldp q6, q7, [sp], #32\n"
      "ldp q4, q5, [sp], #32\n"
      "ldp q2, q3, [sp], #32\n"
      "ldp q0, q1, [sp], #32\n"
    // pop {x0-x9}
      "ldp x8, x9, [sp], #16\n"
      "ldp x6, x7, [sp], #16\n"
      "ldp x4, x5, [sp], #16\n"
      "ldp x2, x3, [sp], #16\n"
      "ldp x0, x1, [sp], #16\n"
      "ret\n"

    // Pass through to original objc_msgSend.
      "Lpassthrough:\n"
      "br x9"
    );
}
