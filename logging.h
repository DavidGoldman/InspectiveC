#ifndef LOGGING_H
#define LOGGING_H

#import <Foundation/Foundation.h>
#include <cstdio>

#ifdef __arm64__
#include "ARM64Types.h"
#endif

void logObject(FILE *file, id obj);

#ifdef __arm64__
bool logArgument(FILE *file, const char *type, pa_list &args);
#else
bool logArgument(FILE *file, const char *type, va_list &args);
#endif

#endif
