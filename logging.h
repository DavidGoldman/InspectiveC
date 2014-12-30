#ifndef LOGGING_H
#define LOGGING_H

#import <Foundation/Foundation.h>
#include <cstdio>

void logObject(FILE *file, id obj);

bool logArgument(FILE *file, const char *type, va_list &args);

#endif
