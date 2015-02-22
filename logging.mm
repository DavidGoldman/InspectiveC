#include "logging.h"

#include <objc/runtime.h>

// Heavily based/taken from AspectiveC by saurik.

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

void logObject(FILE *file, id obj) {
  if (obj == nil) {
    fprintf(file, "nil");
    return;
  }
  Class kind = object_getClass(obj);
  if (class_isMetaClass(kind)) {
    fprintf(file, "[%s class]", class_getName(obj));
    return;
  }
  if (isKindOfClass(kind, NSString_Class)) {
    logNSString(file, obj);
    return;
  }
  fprintf(file, "<%s@0x%08lx>", class_getName(kind), reinterpret_cast<uintptr_t>(obj));
}

#define pa_two_ints(args, varType, varName, intType) \
  varType varName; \
  if (args.ngrn < 7) { \
    intType a = (intType)args.regs->general.arr[args.ngrn++]; \
    intType b = (intType)args.regs->general.arr[args.ngrn++]; \
    varName = (varType) { a, b }; \
  } else { \
    args.ngrn = 8; \
    intType a = (*(intType *)((args.stack = (unsigned char *)((uintptr_t)args.stack & -alignof(intType)) + sizeof(intType)) - sizeof(intType))); \
    intType b = (*(intType *)((args.stack = (unsigned char *)((uintptr_t)args.stack & -alignof(intType)) + sizeof(intType)) - sizeof(intType))); \
    varName = (varType) { a, b }; \
  } \

#define pa_two_doubles(args, t, varName) \
  t varName; \
  if (args.nsrn < 7) { \
    double a = args.regs->floating.arr[args.nsrn++].d.d1; \
    double b = args.regs->floating.arr[args.nsrn++].d.d1; \
    varName = (t) { a, b }; \
  } else { \
    args.nsrn = 8; \
    double a = (*(double *)((args.stack = (unsigned char *)((uintptr_t)args.stack & -alignof(double)) + sizeof(double)) - sizeof(double))); \
    double b = (*(double *)((args.stack = (unsigned char *)((uintptr_t)args.stack & -alignof(double)) + sizeof(double)) - sizeof(double))); \
    varName = (t) { a, b }; \
  } \

#define pa_four_doubles(args, t, varName) \
  t varName; \
  if (args.nsrn < 5) { \
    double a = args.regs->floating.arr[args.nsrn++].d.d1; \
    double b = args.regs->floating.arr[args.nsrn++].d.d1; \
    double c = args.regs->floating.arr[args.nsrn++].d.d1; \
    double d = args.regs->floating.arr[args.nsrn++].d.d1; \
    varName = (t) { a, b, c, d }; \
  } else { \
    args.nsrn = 8; \
    double a = (*(double *)((args.stack = (unsigned char *)((uintptr_t)args.stack & -alignof(double)) + sizeof(double)) - sizeof(double))); \
    double b = (*(double *)((args.stack = (unsigned char *)((uintptr_t)args.stack & -alignof(double)) + sizeof(double)) - sizeof(double))); \
    double c = (*(double *)((args.stack = (unsigned char *)((uintptr_t)args.stack & -alignof(double)) + sizeof(double)) - sizeof(double))); \
    double d = (*(double *)((args.stack = (unsigned char *)((uintptr_t)args.stack & -alignof(double)) + sizeof(double)) - sizeof(double))); \
    varName = (t) { a, b, c, d }; \
  } \

#ifdef __arm64__

bool logArgument(FILE *file, const char *type, pa_list &args) {
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
      case '{': { // A struct. We check for some common structs.
        if (strncmp(type, "{CGPoint=", 9) == 0) {
          pa_two_doubles(args, CGPoint, point)
          logNSStringForStruct(file, NSStringFromCGPoint(point));
        } else if (strncmp(type, "{CGRect=", 8) == 0) {
          pa_four_doubles(args, UIEdgeInsets, insets)
          CGRect rect = CGRectMake(insets.top, insets.left, insets.bottom, insets.right);
          logNSStringForStruct(file, NSStringFromCGRect(rect));
        } else if (strncmp(type, "{CGSize=", 8) == 0) {
          pa_two_doubles(args, CGSize, size)
          logNSStringForStruct(file, NSStringFromCGSize(size));
        }  else if (strncmp(type, "{UIEdgeInsets=", 14) == 0) {
          pa_four_doubles(args, UIEdgeInsets, insets)
          logNSStringForStruct(file, NSStringFromUIEdgeInsets(insets));
        } else if (strncmp(type, "{UIOffset=", 10) == 0) {
          pa_two_doubles(args, UIOffset, offset)
          logNSStringForStruct(file, NSStringFromUIOffset(offset));
        } else if (strncmp(type, "{_NSRange=", 10) == 0) {
          pa_two_ints(args, NSRange, range, unsigned long);
          logNSStringForStruct(file, NSStringFromRange(range));
        } else { // Nope.
          return false;
        }
      } break;
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
#else // arm32
// Heavily based/taken from AspectiveC by saurik.
// @see https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
bool logArgument(FILE *file, const char *type, va_list &args) {
loop:
  switch(*type) {
    case '#': // A class object (Class).
    case '@': { // An object (whether statically typed or typed id).
      id value = va_arg(args, id);
      logObject(file, value);
    } break;
    case ':': { // A method selector (SEL).
      SEL value = va_arg(args, SEL);
      if (value == NULL) {
        fprintf(file, "NULL");
      } else {
        fprintf(file, "@selector(%s)", sel_getName(value));
      }
    } break;
    case '*': { // A character string (char *).
      const char *value = va_arg(args, const char *);
      fprintf(file, "\"%s\"", value);
    } break;
    case '^': { // A pointer to type (^type).
      void *value = va_arg(args, void *);
      if (value == NULL) {
        fprintf(file, "NULL");
      } else {
        fprintf(file, "0x%08lx", reinterpret_cast<uintptr_t>(value));
      }
    } break;
    case 'B': { // A C++ bool or a C99 _Bool.
      bool value = va_arg(args, int);
      fprintf(file, "%s", value ? "true" : "false");
    } break;
    case 'c': { // A char.
      signed char value = va_arg(args, int);
      fprintf(file, "%d", value);
    } break;
    case 'C': { // An unsigned char.
      unsigned char value = va_arg(args, unsigned int);
      fprintf(file, "%d", value);
    } break;
    case 's': { // A short.
      short value = va_arg(args, int);
      fprintf(file, "%d", value);
    } break;
    case 'S': { // An unsigned short.
      unsigned short value = va_arg(args, unsigned int);
      fprintf(file, "%u", value);
    } break;
    case 'i': { // An int.
      int value = va_arg(args, int);
      if (value == INT_MAX) {
        fprintf(file, "INT_MAX");
      } else {
        fprintf(file, "%d", value);
      }
    } break;
    case 'I': { // An unsigned int.
      unsigned int value = va_arg(args, unsigned int);
      fprintf(file, "%u", value);
    } break;
    case 'l': { // A long.
      long value = va_arg(args, long);
      fprintf(file, "%ld", value);
    } break;
    case 'L': { // An unsigned long.
      unsigned long value = va_arg(args, unsigned long);
      fprintf(file, "%lu", value);
    } break;
    case 'q': { // A long long.
      long long value = va_arg(args, long long);
      fprintf(file, "%lld", value);
    } break;
    case 'Q': { // An unsigned long long.
      unsigned long long value = va_arg(args, unsigned long long);
      fprintf(file, "%llu", value);
    } break;
    case 'f': { // A float.
      union {
        uint32_t i;
        float f;
      } value = {va_arg(args, uint32_t)};
      fprintf(file, "%g", value.f);
    } break;
    case 'd': { // A double.
      double value = va_arg(args, double);
      fprintf(file, "%g", value);
    } break;
    case '{': { // A struct. We check for some common structs.
      if (strncmp(type, "{CGAffineTransform=", 19) == 0) {
        CGAffineTransform at = va_arg(args, CGAffineTransform);
        logNSStringForStruct(file, NSStringFromCGAffineTransform(at));
      } else if (strncmp(type, "{CGPoint=", 9) == 0) {
        CGPoint point = va_arg(args, CGPoint);
        logNSStringForStruct(file, NSStringFromCGPoint(point));
      } else if (strncmp(type, "{CGRect=", 8) == 0) {
        CGRect rect = va_arg(args, CGRect);
        logNSStringForStruct(file, NSStringFromCGRect(rect));
      } else if (strncmp(type, "{CGSize=", 8) == 0) {
        CGSize size = va_arg(args, CGSize);
        logNSStringForStruct(file, NSStringFromCGSize(size));
      } else if (strncmp(type, "{UIEdgeInsets=", 14) == 0) {
        UIEdgeInsets insets = va_arg(args, UIEdgeInsets);
        logNSStringForStruct(file, NSStringFromUIEdgeInsets(insets));
      } else if (strncmp(type, "{UIOffset=", 10) == 0) {
        UIOffset offset = va_arg(args, UIOffset);
        logNSStringForStruct(file, NSStringFromUIOffset(offset));
      } else if (strncmp(type, "{_NSRange=", 10) == 0) {
        NSRange range = va_arg(args, NSRange);
        logNSStringForStruct(file, NSStringFromRange(range));
      } else { // Nope.
        return false;
      }
    } break;
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
#endif
