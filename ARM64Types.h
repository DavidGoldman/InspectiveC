#ifndef ARM64_TYPES_H
#define ARM64_TYPES_H

// ARM64 defines.
#define alignof(t) __alignof__(t)

#define pa_arg(args, t) \
  ( (args.ngrn < 8) ? ((t)(args.regs->general.arr[args.ngrn++])) : \
      (*(t *) ((args.stack = (unsigned char *)((uintptr_t)args.stack & -alignof(t)) + sizeof(t)) - sizeof(t))) \
    )

#define pa_float(args) \
  ( (args.nsrn < 8) ? args.regs->floating.arr[args.nsrn++].f.f4 : \
     (*(float *) ((args.stack = (unsigned char *)((uintptr_t)args.stack & -alignof(float)) + sizeof(float)) - sizeof(float))) \
    )

#define pa_double(args) \
  ( (args.nsrn < 8) ? args.regs->floating.arr[args.nsrn++].d.d2 : \
        (*(double *)((args.stack = (unsigned char *)((uintptr_t)args.stack & -alignof(double)) + sizeof(double)) - sizeof(double))) \
    )

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

typedef struct pa_list_ {
  struct RegState_ *regs; // Registers saved when function is called.
  unsigned char *stack; // Address of current argument.
  int ngrn; // The Next General-purpose Register Number.
  int nsrn; // The Next SIMD and Floating-point Register Number.
} pa_list;

#endif

