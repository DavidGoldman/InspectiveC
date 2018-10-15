#ifndef LOGGING_H
#define LOGGING_H

#import <Foundation/Foundation.h>
#include <stdio.h>

#ifdef __arm64__
#define arg_list pa_list
#define int_up_cast(t) t
#define uint_up_cast(t) t
#include "ARM64Types.h"
#else
#define arg_list va_list
#define int_up_cast(t) int
#define uint_up_cast(t) unsigned int
#define pa_arg(args, type) va_arg(args, type)
#define pa_float(args) float_from_va_list(args)
#define pa_double(args) va_arg(args, double)

#define pa_two_ints(args, varType, varName, intType) \
  varType varName = va_arg(args, varType); \

#define pa_two_doubles(args, t, varName) \
  t varName = va_arg(args, t); \

#define pa_four_doubles(args, t, varName) \
  t varName = va_arg(args, t); \

#endif

void logObject(FILE *file, id obj);

bool logArgument(FILE *file, const char *type, arg_list &args);

#endif
