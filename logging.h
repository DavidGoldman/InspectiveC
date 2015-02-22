#ifndef LOGGING_H
#define LOGGING_H

#import <Foundation/Foundation.h>
#include <cstdio>

void logObject(FILE *file, id obj);

bool logArgument_arm32(FILE *file, const char *type, va_list &args);

#endif
