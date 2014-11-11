#include "status.h"

#include <pthread.h>
#include <stdlib.h>
#include <stdio.h>

#include "util.h"

namespace {

// The interned version of NoErr()
static Status* noErr;

// leveldb is going to use pthread anyway, so this allows us
// to use proper pthread_once for initialization.
pthread_once_t once = PTHREAD_ONCE_INIT;

// Module level initialization.
void Init() {
  noErr = new Status();
}

} // anonymous

Status::Status(const char* msg, const char* file) {
  util::StringFormat(&data_, "[%s] %s", msg, file);
}

const char* Status::what() {
  return data_.c_str();
}

const Status NoErr() {
  if (pthread_once(&once, Init) != 0) {
    fprintf(stderr, "once failed\n");
    abort();
  }
  return *noErr;
}