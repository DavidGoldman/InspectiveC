
struct PointerAndInt_ {
  uintptr_t ptr;
  int i;
};

typedef union FPReg_ {
  __int128_t q;
  struct {
    double d1;
    double d2; // Should have the double. - TODO verify
  } d;
  struct {
    float f1;
    float f2;
    float f3;
    float f4; // Should have the float. - TODO verify
  } f;
} FPReg;

struct RegState_ {
  union {
    uint64_t arr[10];
    struct {
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
    } regs;
  } general;

  union {
    FPReg arr[8];
    struct {
      FPReg q0;
      FPReg q1;
      FPReg q2;
      FPReg q3;
      FPReg q4;
      FPReg q5;
      FPReg q6;
      FPReg q7;
    } regs;
  } floating;
};

// Logging stuff.

static Class NSString_Class = objc_getClass("NSString");

static inline void logNSStringForStruct(FILE *file, NSString *str) {
  fprintf(file, "%s", [str UTF8String]);
}

static inline void logNSString(FILE *file, NSString *str) {
  fprintf(file, "@\"%s\"", [str UTF8String]);
}

static inline BOOL isKindOfClass(Class selfClass, Class clazz) {
  for (Class candidate = selfClass; candidate; candidate = class_getSuperclass(candidate)) {
    if (candidate == clazz) {
      return YES;
    }
  }
  return NO;
}

typedef struct pa_list_ {
  struct RegState_ *regs; // Registers saved when function is called.
  unsigned char *stack; // Address of current argument.
  int ngrn; // The Next General-purpose Register Number.
  int nsrn; // The Next SIMD and Floating-point Register Number.
} pa_list;

#define alignof(t) __alignof__(t)

#define pa_arg(args, t) \
  ( (args->ngrn < 8) ? ((t)(args->regs->general.arr[args->ngrn++])) : \
      (*(t *) ((args->stack = (unsigned char *)((uintptr_t)args->stack & -alignof(t)) + sizeof(t)) - sizeof(t))) \
    )

#define pa_float(args) \
  ( (args->nsrn < 8) ? args->regs->floating.arr[args->nsrn++].f.f4 : \
     (*(float *) ((args->stack = (unsigned char *)((uintptr_t)args->stack & -alignof(float)) + sizeof(float)) - sizeof(float))) \
    )

#define pa_double(args) \
  ( (args->nsrn < 8) ? args->regs->floating.arr[args->nsrn++].d.d2 : \
        (*(double *)((args->stack = (unsigned char *)((uintptr_t)args->stack & -alignof(double)) + sizeof(double)) - sizeof(double))) \
    )

static bool logArgument_arm64(FILE *file, const char *type, pa_list *args) {
  loop:
    switch(*type) {
      case '#': // A class object (Class).
      case '@': { // An object (whether statically typed or typed id).
        id value = pa_arg(args, id);
        logObject(file, value);
      } break;
      case ':': { // A method selector (SEL).
        SEL value = pa_arg(args, SEL);
        if (value == NULL) {
          fprintf(file, "NULL");
        } else {
          fprintf(file, "@selector(%s)", sel_getName(value));
        }
      } break;
      case '*': { // A character string (char *).
        const char *value = pa_arg(args, const char *);
        fprintf(file, "\"%s\"", value);
      } break;
      case '^': { // A pointer to type (^type).
        void *value = pa_arg(args, void *);
        if (value == NULL) {
          fprintf(file, "NULL");
        } else {
          fprintf(file, "0x%08lx", reinterpret_cast<uintptr_t>(value));
        }
      } break;
      case 'B': { // A C++ bool or a C99 _Bool.
        bool value = pa_arg(args, bool);
        fprintf(file, "%s", value ? "true" : "false");
      } break;
      case 'c': { // A char.
        signed char value = pa_arg(args, char);
        fprintf(file, "%d", value);
      } break;
      case 'C': { // An unsigned char.
        unsigned char value = pa_arg(args, unsigned char);
        fprintf(file, "%d", value);
      } break;
      case 's': { // A short.
        short value = pa_arg(args, short);
        fprintf(file, "%d", value);
      } break;
      case 'S': { // An unsigned short.
        unsigned short value = pa_arg(args, unsigned short);
        fprintf(file, "%u", value);
      } break;
      case 'i': { // An int.
        int value = pa_arg(args, int);
        if (value == INT_MAX) {
          fprintf(file, "INT_MAX");
        } else {
          fprintf(file, "%d", value);
        }
      } break;
      case 'I': { // An unsigned int.
        unsigned int value = pa_arg(args, unsigned int);
        fprintf(file, "%u", value);
      } break;
      case 'l': { // A long.
        long value = pa_arg(args, long);
        fprintf(file, "%ld", value);
      } break;
      case 'L': { // An unsigned long.
        unsigned long value = pa_arg(args, unsigned long);
        fprintf(file, "%lu", value);
      } break;
      case 'q': { // A long long.
        long long value = pa_arg(args, long long);
        fprintf(file, "%lld", value);
      } break;
      case 'Q': { // An unsigned long long.
        unsigned long long value = pa_arg(args, unsigned long long);
        fprintf(file, "%llu", value);
      } break;
      case 'f': { // A float.
        float value = pa_float(args);
        fprintf(file, "%g", value);
      } break;
      case 'd': { // A double.
        double value = pa_double(args);
        fprintf(file, "%g", value);
      } break;
      case '{': // A struct. We don't support them at the moment.
          return false;
      case 'N': // inout.
      case 'n': // in.
      case 'O': // bycopy.
      case 'o': // out.
      case 'R': // byref.
      case 'r': // const.
      case 'V': // oneway.
        ++type;
        goto loop;
      default:
        return false;
    }
    return true;
}

/*
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
}*/

static inline BOOL classSupportsArbitraryPointerTypes(Class clazz) {
  return isKindOfClass(clazz, NSMapTable_Class) || isKindOfClass(clazz, NSHashTable_Class);
}

static inline void logWatchedHit(ThreadCallStack *cs, FILE *file, id obj, SEL _cmd, char *spaces, pa_list *args) {
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
        if (!logArgument_arm64(file, type, args)) { // Can't understand arg - probably a struct.
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

static inline void logObjectAndArgs(ThreadCallStack *cs, FILE *file, id obj, SEL _cmd, char *spaces, pa_list *args) {
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
        if (!logArgument_arm64(file, type, args)) { // Can't understand arg - probably a struct.
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

static inline void onWatchHit(ThreadCallStack *cs, pa_list *args) {
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

static inline void onNestedCall(ThreadCallStack *cs, pa_list *args) {
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


// arm64 hooking magic.

// Called in our replacementObjc_msgSend before calling the original objc_msgSend.
// This pushes a CallRecord to our stack, most importantly saving the lr.
// Returns orig_objc_msgSend in x0 and isLoggingEnabled in x1.
struct PointerAndInt_ preObjc_msgSend(id self, uintptr_t lr, SEL _cmd, struct RegState_ *rs) {
  // Testing our regs.
  self = (id)rs->general.regs.x0;
  _cmd = (SEL)rs->general.regs.x1;
  lr = (uintptr_t)rs->general.regs.lr;
  ThreadCallStack *cs = getThreadCallStack();
  if (!cs->isLoggingEnabled) { // Not enabled, just return.
    return (struct PointerAndInt_) {reinterpret_cast<uintptr_t>(orig_objc_msgSend), 0};
  }
  pushCallRecord(self, lr, _cmd, cs);
  pa_list args = (pa_list){ rs, ((unsigned char *)rs) + 208, 2, 0 }; // 208 is the offset of rs from the top of the stack.

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
      onWatchHit(cs, &args);
    } else if (cs->numWatchHits > 0) {
      onNestedCall(cs, &args);
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
      onWatchHit(cs, &args);
    } else if (cs->numWatchHits > 0) {
      onNestedCall(cs, &args);
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
// https://blog.nelhage.com/2010/10/amd64-and-pa_arg/
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
