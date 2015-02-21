// arm32 functions.
static BOOL isKindOfClass(Class selfClass, Class clazz) {
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

static inline void logWatchedHit(ThreadCallStack *cs, FILE *file, id obj, SEL _cmd, char *spaces, va_list &args) {
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

static inline void logObjectAndArgs(ThreadCallStack *cs, FILE *file, id obj, SEL _cmd, char *spaces, va_list &args) {
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

static inline void onWatchHit(ThreadCallStack *cs, va_list &args) {
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
    logWatchedHit(cs, logFile, hitRecord->obj, hitRecord->_cmd, spaces, args);
    // Clean up spacesStr.
    spaces[hitIndex] = ' ';
    // Lastly, set the lastPrintedIndex.
    cs->lastPrintedIndex = hitIndex;
  }
}

static inline void onNestedCall(ThreadCallStack *cs, va_list &args) {
  const int curIndex = cs->index;
  FILE *logFile = cs->file;
  if (logFile) {
    // Log the current call.
    char *spaces = cs->spacesStr;
    spaces[curIndex] = '\0';
    CallRecord curRecord = cs->stack[curIndex];
    logObjectAndArgs(cs, logFile, curRecord.obj, curRecord._cmd, spaces, args);
    spaces[curIndex] = ' ';
    // Don't need to set the lastPrintedIndex as it is only useful on the first hit, which has
    // already occurred. 
  }
}

// arm32 hooking magic.

// Called in our replacementObjc_msgSend before calling the original objc_msgSend.
// This pushes a CallRecord to our stack, most importantly saving the lr.
// Returns orig_objc_msgSend.
uintptr_t preObjc_msgSend(id self, uintptr_t lr, SEL _cmd, va_list args) {
  ThreadCallStack *cs = getThreadCallStack();
  pushCallRecord(self, lr, _cmd, cs);

#ifdef MAIN_THREAD_ONLY
  if (self && pthread_main_np() && cs->isLoggingEnabled) {
    Class clazz = object_getClass(self);
    int isWatchedObject = (HMGet(objectsSet, (void *)self) != NULL);
    int isWatchedClass = (HMGet(classSet, (void *)clazz) != NULL);
    int isWatchedSel = (HMGet(selsSet, (void *)_cmd) != NULL);
    if (isWatchedObject && _cmd == @selector(dealloc)) {
      HMRemove(objectsSet, (void *)self);
    }
    if (isWatchedObject || isWatchedClass || isWatchedSel) {
      onWatchHit(cs, args);
    } else if (cs->numWatchHits > 0) {
      onNestedCall(cs, args);
    }
  }
#else
  if (self && cs->isLoggingEnabled) {
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
      onWatchHit(cs, args);
    } else if (cs->numWatchHits > 0) {
      onNestedCall(cs, args);
    }
  }
#endif
  return reinterpret_cast<uintptr_t>(orig_objc_msgSend);
}

// Called in our replacementObjc_msgSend after calling the original objc_msgSend.
// This returns the lr in r0.
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

// Our replacement objc_msgSeng for arm32.
__attribute__((__naked__))
static void replacementObjc_msgSend() {
  __asm__ volatile (
  // Make sure it's enabled.
      "push {r0-r3, lr}\n"
      "blx _InspectiveC_isLoggingEnabled\n"
      "mov r12, r0\n"
      "pop {r0-r3, lr}\n"
      "ands r12, r12\n"
      "beq Lpassthrough\n"
  // Call our preObjc_msgSend hook - returns orig_objc_msgSend.
  // Swap the args around for our call to preObjc_msgSend.
      "push {r0, r1, r2, r3}\n"
      "mov r2, r1\n"
      "mov r1, lr\n"
      "add r3, sp, #8\n"
      "blx __Z15preObjc_msgSendP11objc_objectmP13objc_selectorPv\n"
      "mov r12, r0\n"
      "pop {r0, r1, r2, r3}\n"
  // Call through to the original objc_msgSend.
      "blx r12\n"
  // Call our postObjc_msgSend hook.
      "push {r0-r3}\n"
      "blx __Z16postObjc_msgSendv\n"
      "mov lr, r0\n"
      "pop {r0-r3}\n"
      "bx lr\n"
  // Pass through to original objc_msgSend.
      "Lpassthrough:\n"
      "push {r0, lr}\n"
      "blx __Z19getOrigObjc_msgSendv\n"
      "mov r12, r0\n"
      "pop {r0, lr}\n"
      "bx r12"
    );
}

