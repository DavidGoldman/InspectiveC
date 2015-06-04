#include "types.h"

typedef NS_ENUM(NSInteger, InspectiveCType) {
  InspectiveCTypeNone = 0, // v (a void) is considered None.
  InspectiveCTypeUnknown,
  InspectiveCTypeChar,
  InspectiveCTypeInt,
  InspectiveCTypeShort,
  InspectiveCTypeLong,
  InspectiveCTypeLongLong,
  InspectiveCTypeUChar,
  InspectiveCTypeUInt,
  InspectiveCTypeUShort,
  InspectiveCTypeULong,
  InspectiveCTypeULongLong,
  InspectiveCTypeFloat,
  InspectiveCTypeDouble,
  InspectiveCTypeBool,
  InspectiveCTypeCharString,
  InspectiveCTypeObject,
  InspectiveCTypeClass,
  InspectiveCTypeSelector,
  InspectiveCTypePointer,
  InspectiveCTypeCGAffineTransform,
  InspectiveCTypeCGPoint,
  InspectiveCTypeCGRect,
  InspectiveCTypeCGSize,
  InspectiveCTypeUIEdgeInsets,
  InspectiveCTypeUIOffset,
  InspectiveCTypeNSRange
};

InspectiveCType InspectiveCType_parseFromObjCType(const char *objC_type) {
loop:
  switch(*type) {
    case 'v': return InspectiveCTypeNone;
    case '#': return InspectiveCTypeClass;
    case '@': return InspectiveCTypeObject;
    case ':': return InspectiveCTypeSelector;
    case '*': return InspectiveCTypeCharString;
    case '^': return InspectiveCTypePointer;
    case 'B': return InspectiveCTypeBool;
    case 'c': return InspectiveCTypeChar;
    case 'C': return InspectiveCTypeUChar;
    case 's': return InspectiveCTypeShort;
    case 'S': return InspectiveCTypeUShort;
    case 'i': return InspectiveCTypeInt;
    case 'I': return InspectiveCTypeUInt;
#ifdef __arm64__ // Longs - treated as a 32-bit quantity on 64-bit programs.
    case 'l': return InspectiveCTypeInt;
    case 'L': return InspectiveCTypeUInt;
#else
    case 'l': return InspectiveCTypeLong;
    case 'L': return InspectiveCTypeULong;
#endif
    case 'q': return InspectiveCTypeLongLong;
    case 'Q': return InspectiveCTypeULongLong;
    case 'f': return InspectiveCTypeFloat;
    case 'd': return InspectiveCTypeDouble;
    case '{': { // A struct. We check for some common structs.
      if (strncmp(type, "{CGAffineTransform=", 19) == 0) {
        return InspectiveCTypeCGAffineTransform;
      } else if (strncmp(type, "{CGPoint=", 9) == 0) {
        return InspectiveCTypeCGPoint;
      } else if (strncmp(type, "{CGRect=", 8) == 0) {
        return InspectiveCTypeCGRect;
      } else if (strncmp(type, "{CGSize=", 8) == 0) {
        return InspectiveCTypeCGSize;
      }  else if (strncmp(type, "{UIEdgeInsets=", 14) == 0) {
        return InspectiveCTypeUIEdgeInsets;
      } else if (strncmp(type, "{UIOffset=", 10) == 0) {
        return InspectiveCTypeUIOffset;
      } else if (strncmp(type, "{_NSRange=", 10) == 0) {
        return InspectiveCTypeNSRange;
      } else { // Nope.
        return InspectiveCTypeUnknown;
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
      return InspectiveCTypeUnknown;
  }
  return InspectiveCTypeUnknown;
}

const char * InspectiveCType_toString(InspectiveCType type) {
  switch(type) {
    case InspectiveCTypeNone: return "None";
    case InspectiveCTypeUnknown: return "Unknown";
    case InspectiveCTypeChar: return "char";
    case InspectiveCTypeInt: return "int";
    case InspectiveCTypeShort: return "short";
    case InspectiveCTypeLong: return "long";
    case InspectiveCTypeLongLong: return "long long";
    case InspectiveCTypeUChar: return "unsigned char";
    case InspectiveCTypeUInt: return "unsigned int";
    case InspectiveCTypeUShort: return "unsigned short";
    case InspectiveCTypeULong: return "unsigned long";
    case InspectiveCTypeULongLong: return "unsigned long long";
    case InspectiveCTypeFloat: return "float";
    case InspectiveCTypeDouble: return "double";
    case InspectiveCTypeBool: return "BOOL";
    case InspectiveCTypeCharString: return "char *";
    case InspectiveCTypeObject: return "id";
    case InspectiveCTypeClass: return "Class";
    case InspectiveCTypeSelector: return "SEL";
    case InspectiveCTypePointer: return "void *";
    case InspectiveCTypeCGAffineTransform: return "CGAffineTransform";
    case InspectiveCTypeCGPoint: return "CGPoint";
    case InspectiveCTypeCGRect: return "CGRect";
    case InspectiveCTypeCGSize: return "CGSize";
    case InspectiveCTypeUIEdgeInsets: return "UIEdgeInsets";
    case InspectiveCTypeUIOffset: return "UIOffset";
    case InspectiveCTypeNSRange: return "NSRange";
  }
  perrror("InspectiveCType_toString: Unknown type");
  return "Unknown";
}
