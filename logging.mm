#include "logging.h"

#include <objc/runtime.h>

#include "blocks.h"
#include "types.h"

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
bool logArgument(FILE *file, const char *objCType, arg_list &args) {
  InspectiveCType type = InspectiveCType_parseFromObjCType(objCType);
  
  switch(type) {
    case InspectiveCTypeNone:
    case InspectiveCTypeUnknown:
      return false;
    case InspectiveCTypeClass:
    case InspectiveCTypeObject: {
      id value = pa_arg(args, id);
      logObject(file, value);
    } break;
    case InspectiveCTypeSelector: {
      SEL value = pa_arg(args, SEL);
      if (value == NULL) {
        fprintf(file, "NULL");
      } else {
        fprintf(file, "@selector(%s)", sel_getName(value));
      }
    } break;
    case InspectiveCTypeCharString: {
      const char *value = pa_arg(args, const char *);
      fprintf(file, "\"%s\"", value);
    } break;
    case InspectiveCTypePointer: {
      void *value = pa_arg(args, void *);
      if (value == NULL) {
        fprintf(file, "NULL");
      } else {
        fprintf(file, "0x%08lx", reinterpret_cast<uintptr_t>(value));
      }
    } break;
    case InspectiveCTypeBool: {
      bool value = pa_arg(args, int_up_cast(bool));
      fprintf(file, "%s", value ? "true" : "false");
    } break;
    case InspectiveCTypeChar: {
      signed char value = pa_arg(args, int_up_cast(char));
      fprintf(file, "%d", value);
    } break;
    case InspectiveCTypeUChar: {
      unsigned char value = pa_arg(args, uint_up_cast(unsigned char));
      fprintf(file, "%d", value);
    } break;
    case InspectiveCTypeShort: {
      short value = pa_arg(args, int_up_cast(short));
      fprintf(file, "%d", value);
    } break;
    case InspectiveCTypeUShort: {
      unsigned short value = pa_arg(args, uint_up_cast(unsigned short));
      fprintf(file, "%u", value);
    } break;
    case InspectiveCTypeInt: {
      int value = pa_arg(args, int);
      if (value == INT_MAX) {
        fprintf(file, "INT_MAX");
      } else {
        fprintf(file, "%d", value);
      }
    } break;
    case InspectiveCTypeUInt: {
      unsigned int value = pa_arg(args, unsigned int);
      fprintf(file, "%u", value);
    } break;
    case InspectiveCTypeLong: {
      long value = pa_arg(args, long);
      fprintf(file, "%ld", value);
    } break;
    case InspectiveCTypeULong: {
      unsigned long value = pa_arg(args, unsigned long);
      fprintf(file, "%lu", value);
    } break;
    case InspectiveCTypeLongLong: {
      long long value = pa_arg(args, long long);
      fprintf(file, "%lld", value);
    } break;
    case InspectiveCTypeULongLong: {
      unsigned long long value = pa_arg(args, unsigned long long);
      fprintf(file, "%llu", value);
    } break;
    case InspectiveCTypeFloat: {
      float value = pa_float(args);
      fprintf(file, "%g", value);
    } break;
    case InspectiveCTypeDouble: {
      double value = pa_double(args);
      fprintf(file, "%g", value);
    } break;
    case InspectiveCTypeCGAffineTransform: {
  #ifdef __arm64__
      CGAffineTransform *ptr = (CGAffineTransform *)pa_arg(args, void *);
      logNSStringForStruct(file, NSStringFromCGAffineTransform(*ptr));
  #else
      CGAffineTransform at = va_arg(args, CGAffineTransform);
      logNSStringForStruct(file, NSStringFromCGAffineTransform(at));
  #endif
    } break;
    case InspectiveCTypeCGPoint: {
      pa_two_doubles(args, CGPoint, point)
      logNSStringForStruct(file, NSStringFromCGPoint(point));
    } break;
    case InspectiveCTypeCGRect: {
      pa_four_doubles(args, UIEdgeInsets, insets)
      CGRect rect = CGRectMake(insets.top, insets.left, insets.bottom, insets.right);
      logNSStringForStruct(file, NSStringFromCGRect(rect));
    } break;
    case InspectiveCTypeCGSize: {
      pa_two_doubles(args, CGSize, size)
      logNSStringForStruct(file, NSStringFromCGSize(size));
    } break;
    case InspectiveCTypeUIEdgeInsets: {
      pa_four_doubles(args, UIEdgeInsets, insets)
      logNSStringForStruct(file, NSStringFromUIEdgeInsets(insets));
    } break;
    case InspectiveCTypeUIOffset: {
      pa_two_doubles(args, UIOffset, offset)
      logNSStringForStruct(file, NSStringFromUIOffset(offset));
    } break;
    case InspectiveCTypeNSRange: {
      pa_two_ints(args, NSRange, range, unsigned long);
      logNSStringForStruct(file, NSStringFromRange(range));
    } break;
  }

  return true;
}
