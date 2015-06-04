#ifndef INSPECTIVE_C_TYPES_H
#define INSPECTIVE_C_TYPES_H

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

InspectiveCType InspectiveCType_parseFromObjCType(const char *objC_type);

const char * InspectiveCType_toString(InspectiveCType type);

#endif
