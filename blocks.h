#ifndef BLOCKS_H
#define BLOCKS_H

#include <stdio.h>

enum {
  BLOCK_HAS_COPY_DISPOSE = (1 << 25),
  BLOCK_HAS_CTOR = (1 << 26), // Helpers have C++ code.
  BLOCK_IS_GLOBAL = (1 << 28),
  BLOCK_HAS_STRET = (1 << 29), // IFF BLOCK_HAS_SIGNATURE.
  BLOCK_HAS_SIGNATURE = (1 << 30),
};

struct BlockLiteral_ {
  void *isa; // Should be initialized to &_NSConcreteStackBlock or &_NSConcreteGlobalBlock.
  int flags;
  int reserved;
  void (*invoke)(void *, ...);
  struct BlockDescriptor_ {
    unsigned long int reserved; // NULL.
    unsigned long int size; // sizeof(struct BlockLiteral_).
    // Optional helper functions.
    void (*copy_helper)(void *dst, void *src); // IFF (1 << 25).
    void (*dispose_helper)(void *src); // IFF (1 << 25).
    const char *signature; // IFF (1 << 30).
  } *descriptor;
};

void logBlock(FILE *file, id block);

#endif
