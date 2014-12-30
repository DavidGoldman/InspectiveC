#include "logging.h"

#include <objc/runtime.h>

// Heavily based/taken from AspectiveC by saurik.

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
  fprintf(file, "<%s@0x%08lx>", class_getName(kind), reinterpret_cast<uintptr_t>(obj));
}

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

