#include "hashmap.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define INITIAL_SIZE 16
#define LOAD_FACTOR 0.75

#define TRUE 1
#define FALSE 0

// Dummy destruct function used for freeing the map with a call to HMFree.
static void hm_dummy_entry_destruct(void *key, void *value) { }

// Returns the given table index for a given key.
static inline NSUInteger hm_index_for_key(HashMapRef hashMap, void *key) {
  return hashMap->hashFunction(key) % hashMap->tableSize;
}

// Inserts the given bucket into the HashMap in constant time.
static inline void hm_insert(HashMapRef hashMap, HashBucket *bucket) {
  NSUInteger index = hm_index_for_key(hashMap, bucket->key);
  bucket->next = hashMap->table[index];
  hashMap->table[index] = bucket;
}

// Returns the bucket (or NULL) for the given key. Expected constant time behavior, but has a worst
// case of O(n).
static inline HashBucket * hm_get_bucket(HashMapRef hashMap, void *key) {
  HashBucket *bucket = hashMap->table[hm_index_for_key(hashMap, key)];
  while (bucket) {
    if (hashMap->equalityFunction(key, bucket->key)) {
      return bucket;
    }
    bucket = bucket->next;
  }
  return NULL;
}

// Removes the bucket for the given key if it exists. Expected constant time behavior, but has a 
// worst case of O(n).
static inline HashBucket * hm_remove_bucket(HashMapRef hashMap, void *key) {
  NSUInteger index = hm_index_for_key(hashMap, key);
  HashBucket *prev = NULL;
  HashBucket *cur = hashMap->table[index];

  while (cur) {
    if (hashMap->equalityFunction(key, cur->key)) {
      if (prev == NULL) {
        hashMap->table[index] = cur->next;
      } else {
        prev->next = cur->next;
      }
      return cur;
    }
    prev = cur;
    cur = cur->next;
  }
  return NULL;
}

// Resizes the given HashMap by a factor of 2. Returns 1 if it succeeds.
static inline int hm_resize(HashMapRef hashMap) {
  size_t oldTableSize = hashMap->tableSize;
  size_t newTableSize = 2 * oldTableSize;
  HashBucket **oldTable = hashMap->table;
  HashBucket **newTable = (HashBucket **)calloc(newTableSize, sizeof(HashBucket *));
  if (!newTable) {
    return FALSE;
  }
  hashMap->tableSize = newTableSize;
  hashMap->table = newTable;

  for (size_t index = 0; index < oldTableSize; ++index) {
    HashBucket *bucket = oldTable[index];

    while (bucket) {
      HashBucket *nextBucket = bucket->next;
      hm_insert(hashMap, bucket);
      bucket = nextBucket;
    }
  }
  free(oldTable);
  return TRUE;
}

// Resizes the given HashMap if necessary (judged by the size of the HashMap and LOAD_FACTOR).
// Returns 1 if the HashMap does not need to be resized after adding 1 more item.
static inline int hm_resize_check(HashMapRef hashMap) {
  if (hashMap->size + 1 > hashMap->tableSize * LOAD_FACTOR) {
    return hm_resize(hashMap);
  }
  return TRUE;
}

// V is actually a signed int *.
// Robert Jenkins' 32 bit integer hash function.
static NSUInteger intHash(void *v) {
  unsigned a = *(unsigned *)v;
  a = (a + 0x7ed55d16) + (a<<12);
  a = (a ^ 0xc761c23c) ^ (a>>19);
  a = (a + 0x165667b1) + (a<<5);
  a = (a + 0xd3a2646c) ^ (a<<9);
  a = (a + 0xfd7046c5) + (a<<3);
  a = (a ^ 0xb55a4f09) ^ (a>>16);
  return a;
}

// Tests int pointers for equality.
static int intEquality(void *va, void *vb) {
  int a = *(int *)va;
  int b = *(int *)vb;
  return a == b;
}

// Creates a new int HashMap.
HashMapRef HMCreateIntHashMap() {
  return HMCreate(&intEquality, &intHash);
}

// Tests two strings for equality.
static int strEquality(void *va, void *vb) {
  return strcmp((char *)va, (char *)vb) == 0;
}

// Jenkins's one-at-a-time string hash function, as used in Perl.
// See http://en.wikipedia.org/wiki/Jenkins_hash_function
static NSUInteger strHash(void *voidStr) {
  char *str = (char *)voidStr;
  size_t len = strlen(str);
  NSUInteger hash, i;
  for(hash = i = 0; i < len; ++i) {
    hash += str[i];
    hash += (hash << 10);
    hash ^= (hash >> 6);
  }
  hash += (hash << 3);
  hash ^= (hash >> 11);
  hash += (hash << 15);
  return hash;
}

// Creates a new string HashMap.
HashMapRef HMCreateStringHashMap() {
  return HMCreate(&strEquality, &strHash);
}

// Creates a new HashMap.
HashMapRef HMCreate(EqualityFuncT ef, HashFuncT hf) {
  HashMapRef hashMap = (HashMapRef)malloc(sizeof(HashMap));
  if (hashMap) { // Make sure malloc worked
    HashBucket **table = (HashBucket **)calloc(INITIAL_SIZE, sizeof(HashBucket *));
    if (!table) { // Check for alloc failure.
      free(hashMap);
      return NULL;
    }
    hashMap->tableSize = INITIAL_SIZE;
    hashMap->size = 0;
    hashMap->table = table;
    hashMap->equalityFunction = ef;
    hashMap->hashFunction = hf;
  }
  return hashMap;
}

static void hm_insert_entry(void *key, void *val, void *map) {
  HashMapRef hashMap = (HashMapRef)map;
  HMPut(hashMap, key, val);
}

// Creates a copy of the given HashMap.
HashMapRef HMCopy(HashMapRef ref) {
  HashMapRef hashMap = HMCreate(ref->equalityFunction, ref->hashFunction);
  if (hashMap) {
    HMIterateWithArg(ref, hashMap, &hm_insert_entry);
  }
  return hashMap;
}

// Inserts the given value into the HashMap, using key. Note that if key already exists in the
// HashMap, it will be updated to reference value instead.
//
// This function returns 1 if it succeeds; 0 otherwise.
int HMPut(HashMapRef hashMap, void *key, void *value) {
  HashBucket *bucket = hm_get_bucket(hashMap, key);
  if (bucket) { // Already exists in map.
    bucket->value = value;
    return TRUE;
  } else { // Add into map.
    HashBucket *bucket = (HashBucket *)malloc(sizeof(HashBucket));
    if (hm_resize_check(hashMap) && bucket) {
      bucket->key = key;
      bucket->value = value;
      hm_insert(hashMap, bucket);
      ++hashMap->size;
      return TRUE;
    } else {
      free(bucket);
      return FALSE;
    }
  }
}

// Returns the object referenced by key, if any.
void * HMGet(HashMapRef hashMap, void *key) {
  HashBucket *bucket = hm_get_bucket(hashMap, key);
  return (bucket) ? bucket->value : NULL;
}

// Removes a key from the HashMap, returning the value removed, if any. Note that this may be called
// when iterating through buckets if and only if you only remove the current key being iterated.
void * HMRemove(HashMapRef hashMap, void *key) {
  HashBucket *bucket = hm_remove_bucket(hashMap, key);
  if (bucket) {
    void *retVal = bucket->value;
    --hashMap->size;
    free(bucket);
    return retVal;
  } else {
    return NULL;
  }
}

// Calls the function on all entries in the HashMap, in an arbitrary order.
void HMIterate(HashMapRef hashMap, void (*function)(void *, void *)) {
  for (size_t index = 0; index < hashMap->tableSize; ++index) {
    HashBucket *bucket = hashMap->table[index];
    while (bucket) {
      HashBucket *nextBucket = bucket->next;
      function(bucket->key, bucket->value);
      bucket = nextBucket;
    }
  }
}

// Calls the function on all entries in the HashMap, in an arbitrary order.
void HMIterateWithArg(HashMapRef hashMap, void *arg, void (*functionWithExtraArg)(void *, void *, void *extraArg)) {
  for (size_t index = 0; index < hashMap->tableSize; ++index) {
    HashBucket *bucket = hashMap->table[index];
    while (bucket) {
      HashBucket *nextBucket = bucket->next;
      functionWithExtraArg(bucket->key, bucket->value, arg);
      bucket = nextBucket;
    }
  }
}

// Frees a HashMap after calling the EntryDestructFuncT on all entries in the HashMap.
void HMFreeWithEntryDestruct(HashMapRef hashMap, EntryDestructFuncT entryDestruct) {
  for (size_t index = 0; index < hashMap->tableSize; ++index) {
    HashBucket *bucket = hashMap->table[index];
    while (bucket) {
      HashBucket *nextBucket = bucket->next;
      entryDestruct(bucket->key, bucket->value);
      free(bucket);
      bucket = nextBucket;
    }
  }
  free(hashMap->table);
  free(hashMap);
}

// Frees a HashMap without touching the keys and values.
void HMFree(HashMapRef hashMap) {
  HMFreeWithEntryDestruct(hashMap, &hm_dummy_entry_destruct);
}

// Prints some HashMap stats.
void HMPrintStats(HashMapRef hashMap) {
  printf("HashMap <%p>, size=%u\n", (void *)hashMap, (unsigned)hashMap->size);
  printf("\tTableSize: %u\n", (unsigned)hashMap->tableSize);

  unsigned sumBucketLengths = 0;
  unsigned numNonZeroBuckets = 0;

  for (size_t index = 0; index < hashMap->tableSize; ++index) {
    unsigned bucketLength = 0;

    HashBucket *bucket = hashMap->table[index];
    while (bucket) {
      HashBucket *nextBucket = bucket->next;
      ++bucketLength;
      bucket = nextBucket;
    }

    if (bucketLength) {
      sumBucketLengths += bucketLength;
      ++numNonZeroBuckets;
    }
  }

  printf("\tNon Zero Buckets: %u\n", numNonZeroBuckets);
  printf("\tAverage Non Zero Size: %u\n", (sumBucketLengths / numNonZeroBuckets));
}
