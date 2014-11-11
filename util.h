#ifndef UTIL_H_
#define UTIL_H_

#include <cstdio>
#include <stdint.h>
#include <string>
#include <vector>

#include "status.h"

namespace util {

// A simple RAII container for a FILE*
class File {
 public:
  File() : file_(NULL) {}
  
  ~File() {
    Close();
  }

  FILE* get() { return file_; }

  Status Open(const char* filename, const char* mode);
  Status Close();
 private:
  FILE* file_;
};

// A timer utility for timing things.
// Example:
//
// util::Timer timer;
//
// do something.
//
// double seconds = timer.Elapsed();
// timer.Reset();
// seconds = timer.Elapsed(); 
class Timer {
 public:
  static const uint64_t kMillisecondsPerSecond = 1000;
  static const uint64_t kMicrosecondsPerMillisecond = 1000;
  static const uint64_t kMicrosecondsPerSecond = kMicrosecondsPerMillisecond *
                                                 kMillisecondsPerSecond;
  static const uint64_t kMicrosecondsPerMinute = kMicrosecondsPerSecond * 60; 
  static const uint64_t kMicrosecondsPerHour = kMicrosecondsPerMinute * 60; 
  static const uint64_t kMicrosecondsPerDay = kMicrosecondsPerHour * 24; 
  static const uint64_t kMicrosecondsPerWeek = kMicrosecondsPerDay * 7;
  static const uint64_t kNanosecondsPerMicrosecond = 1000;
  static const uint64_t kNanosecondsPerSecond = kNanosecondsPerMicrosecond *
                                                kMicrosecondsPerSecond;
  Timer();
  double Elapsed();
  void Reset();
 private:
  uint64_t started_;
};

// std::string version of sprintf.
void StringFormat(std::string* s, const char* fmt, va_list args);
void StringFormat(std::string* s, const char* fmt, ...);

// A proper interface to strtol.
Status ParseInt(std::string& s, int base, int* v);

// A simple file glob utility.
Status Glob(const char* p, std::vector<std::string>* res);

// Append a child path to a parent path. The file-separator is assumed to
// be unix-like.
void PathJoin(std::string* par, const std::string& chd);

// Does this path point to a directory?
bool IsDirectory(const std::string& path);

// Remove a directory. If recursive is false, simply use rmdir. Otherwise,
// recursively remove all sub-content before removing the directory.
Status RemoveDirectory(const std::string& path, bool recursive=false);

Status MakeDirectory(const std::string& path);

void Basename(std::string* res, std::string& path);

} // util

#endif // UTIL_H_