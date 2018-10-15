#ifndef HASHMAP_H
#define HASHMAP_H

#include <stddef.h>
#import <Foundation/Foundation.h>

#if __cplusplus
extern "C" {
#endif

// Equality function used in hashmap to test for equality - returns nonzero if equal.
typedef int (*EqualityFuncT)(void *, void *);

// Hashing function used to position items inside the HashMap.
typedef NSUInteger (*HashFuncT)(void *);

// Destruction function used to release {key, value} entries inside the HashMap.
typedef void (*EntryDestructFuncT)(void *, void *);

// HashBucket structure, used in the HashMap's table.
typedef struct HashBucket_ {
	void *key;
	void *value;
	struct HashBucket_ *next;
} HashBucket;

// HashMap structure, containing a table of HashBuckets, and the required functions.
typedef struct HashMap_ {
	HashBucket **table;
	size_t tableSize;
	size_t size;
	EqualityFuncT equalityFunction;
	HashFuncT hashFunction;
} HashMap;
typedef HashMap * HashMapRef;

// Creates a new int HashMap.
HashMapRef HMCreateIntHashMap();

// Creates a new string HashMap.
HashMapRef HMCreateStringHashMap();

// Creates a new HashMap.
HashMapRef HMCreate(EqualityFuncT ef, HashFuncT hf);

// Creates a copy of the given HashMap.
HashMapRef HMCopy(HashMapRef ref);

// Frees a HashMap without touching the keys and values.
void HMFree(HashMapRef hashMap);

// Frees a HashMap after calling the EntryDestructFuncT on all entries in the HashMap.
void HMFreeWithEntryDestruct(HashMapRef hashMap, EntryDestructFuncT edf);

// Inserts the given value into the HashMap, using key. Note that if key already exists in the
// HashMap, it will be updated to reference value instead.
//
// This function returns 1 if it succeeds; 0 otherwise.
int HMPut(HashMapRef hashMap, void *key, void *value);

// Returns the object referenced by key, if any.
void * HMGet(HashMapRef hashMap, void *key);

// Removes a key from the HashMap, returning the value removed, if any. Note that this may be called
// when iterating through buckets if and only if you only remove the current key being iterated.
void * HMRemove(HashMapRef hashMap, void *key);

// Calls the function on all entries in the HashMap, in an arbitrary order.
void HMIterate(HashMapRef hashMap, void (*function)(void *, void *));

// Calls the function on all entries in the HashMap, in an arbitrary order.
void HMIterateWithArg(HashMapRef hashMap, void *arg, void (*functionWithExtraArg)(void *, void *, void *extraArg));

// Prints some HashMap stats.
void HMPrintStats(HashMapRef hashMap);

#if __cplusplus
}
#endif

#endif
