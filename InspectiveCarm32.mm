
// arm32 hooking magic.

// Called in our replacementObjc_msgSend before calling the original objc_msgSend.
// This pushes a CallRecord to our stack, most importantly saving the lr.
// Returns orig_objc_msgSend.
uintptr_t preObjc_msgSend(id self, uintptr_t lr, SEL _cmd, va_list args) {
  ThreadCallStack *cs = getThreadCallStack();
  pushCallRecord(self, lr, _cmd, cs);

  preObjc_msgSend_common(self, lr, _cmd, cs, args);

  return reinterpret_cast<uintptr_t>(orig_objc_msgSend);
}

// Our replacement objc_msgSend for arm32.
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
      "movw  r12, :lower16:(__ZL17orig_objc_msgSend-(Loffset+4))\n"
      "movt  r12, :upper16:(__ZL17orig_objc_msgSend-(Loffset+4))\n"
      "Loffset:\n"
      "add r12, pc\n"
      "ldr r12, [r12]\n"
      "bx r12\n"
    );
}

