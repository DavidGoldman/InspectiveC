
static int counter = 0;

uintptr_t preObjc_msgSend(id self, SEL _cmd) {
  if (pthread_main_np() && (++counter & 0x4FFF) == 0) {
    ThreadCallStack *cs = getThreadCallStack();
    fprintf(cs->file, "%s\n", sel_getName(_cmd));
  }
  return reinterpret_cast<uintptr_t>(orig_objc_msgSend);
}

// Our replacement objc_msgSend (arm64).
__attribute__((__naked__))
static volatile void replacementObjc_msgSend() {
  __asm__ volatile (
    // push {x0-x8, lr}
      "stp x0, x1, [sp, #-16]!\n"
      "stp x2, x3, [sp, #-16]!\n"
      "stp x4, x5, [sp, #-16]!\n"
      "stp x6, x7, [sp, #-16]!\n"
      "stp x8, lr, [sp, #-16]!\n"
    // push {q0-q7}
      "stp q0, q1, [sp, #-32]!\n"
      "stp q2, q3, [sp, #-32]!\n"
      "stp q4, q5, [sp, #-32]!\n"
      "stp q6, q7, [sp, #-32]!\n"
    // Call preObjc_msgSend and move orig_objc_msgSend into x0.
      "bl __Z15preObjc_msgSendP11objc_objectP13objc_selector\n"
      "mov x9, x0\n"
    // pop {q0-q7}
      "ldp q6, q7, [sp], #32\n"
      "ldp q4, q5, [sp], #32\n"
      "ldp q2, q3, [sp], #32\n"
      "ldp q0, q1, [sp], #32\n"
    // pop {x0-x8, lr}
      "ldp x8, lr, [sp], #16\n"
      "ldp x6, x7, [sp], #16\n"
      "ldp x4, x5, [sp], #16\n"
      "ldp x2, x3, [sp], #16\n"
      "ldp x0, x1, [sp], #16\n"
      "br x9"
    );
}
