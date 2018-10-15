#include "logging.h"

#include <objc/runtime.h>
#import <CoreGraphics/CGAffineTransform.h>
#import <UIKit/UIGeometry.h>

#include "blocks.h"

static Class NSString_Class = objc_getClass("NSString");
static Class NSBlock_Class = objc_getClass("NSBlock");

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
  if (isKindOfClass(kind, NSBlock_Class)) {
    logBlock(file, obj);
    return;
  }
  fprintf(file, "<%s@%p>", class_getName(kind), reinterpret_cast<void *>(obj));
}

#ifndef __arm64__
static float float_from_va_list(va_list &args) {
  union {
    uint32_t i;
    float f;
  } value = {va_arg(args, uint32_t)};
  return value.f;
}
#endif

// Heavily based/taken from AspectiveC by saurik.
// @see http://svn.saurik.com/repos/menes/trunk/aspectivec/AspectiveC.mm
// @see https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
bool logArgument(FILE *file, const char *type, arg_list &args) {
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
          fprintf(file, "%p", value);
        }
      } break;
      case 'B': { // A C++ bool or a C99 _Bool.
        bool value = pa_arg(args, int_up_cast(bool));
        fprintf(file, "%s", value ? "true" : "false");
      } break;
      case 'c': { // A char.
        signed char value = pa_arg(args, int_up_cast(char));
        fprintf(file, "%d", value);
      } break;
      case 'C': { // An unsigned char.
        unsigned char value = pa_arg(args, uint_up_cast(unsigned char));
        fprintf(file, "%d", value);
      } break;
      case 's': { // A short.
        short value = pa_arg(args, int_up_cast(short));
        fprintf(file, "%d", value);
      } break;
      case 'S': { // An unsigned short.
        unsigned short value = pa_arg(args, uint_up_cast(unsigned short));
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
#ifdef __arm64__
      case 'l': { // A long - treated as a 32-bit quantity on 64-bit programs.
        int value = pa_arg(args, int);
        fprintf(file, "%d", value);
      } break;
      case 'L': { // An unsigned long - treated as a 32-bit quantity on 64-bit programs.
        unsigned int value = pa_arg(args, unsigned int);
        fprintf(file, "%u", value);
      } break;
#else
      case 'l': { // A long.
        long value = pa_arg(args, long);
        fprintf(file, "%ld", value);
      } break;
      case 'L': { // An unsigned long.
        unsigned long value = pa_arg(args, unsigned long);
        fprintf(file, "%lu", value);
      } break;
#endif
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
        if (strncmp(type, "{CGAffineTransform=", 19) == 0) {
#ifdef __arm64__
          CGAffineTransform *ptr = (CGAffineTransform *)pa_arg(args, void *);
          logNSStringForStruct(file, NSStringFromCGAffineTransform(*ptr));
#else
          CGAffineTransform at = va_arg(args, CGAffineTransform);
          logNSStringForStruct(file, NSStringFromCGAffineTransform(at));
#endif
        } else if (strncmp(type, "{CGPoint=", 9) == 0) {
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
