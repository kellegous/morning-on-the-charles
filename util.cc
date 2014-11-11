#include "util.h"

#include <cstdarg>
#include <dirent.h>
#include <glob.h>
#include <libgen.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#ifdef __MACH__
#include <mach/mach_time.h>
#else
#include <time.h>
#endif
#include <unistd.h>

namespace {

// mach systems have a timebase that is needed to scale the results
// of mach_absolute_time to "real" absolute time. This allows for a
// single initializaiton of that factor.
pthread_once_t once = PTHREAD_ONCE_INIT;
static double factor;

// Get the current time in microseconds.
uint64_t Now() {
#ifdef __MACH__
  if (factor == 0.0) {
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    factor = (double)info.numer / (double)info.denom;    
  }
  return mach_absolute_time() / util::Timer::kNanosecondsPerMicrosecond;
#else
  struct timespec ts = {0};
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
    return 0;
  }
  return static_cast<uint64_t>(ts.tv_sec) * util::Timer::kMicrosecondsPerSecond +
      (static_cast<uint64_t>(ts.tv_nsec) / util::Timer::kNanosecondsPerMicrosecond);
#endif
}

// Initialize this module.
void Init() {
#ifdef __MACH__
  mach_timebase_info_data_t info;
  mach_timebase_info(&info);
  factor = (double)info.numer / (double)info.denom;
#else
  factor = 1.0;
#endif
}

} // anonymous


namespace util {

Status File::Open(const char* filename, const char* mode) {
  file_ = fopen(filename, mode);
  if (!file_) {
    std::string err;
    StringFormat(&err, "unable to open: %s", filename);
    return ERR(err.c_str());
  }

  return NoErr();
}

Status File::Close() {
  if (!file_) {
    return NoErr();
  }

  if (fclose(file_) != 0) {
    return ERR("close failed");
  }

  return NoErr();
}


Timer::Timer() : started_(0) {
  if (pthread_once(&once, Init) != 0) {
    fprintf(stderr, "module init failed\n");
    abort();
  }
  Reset();
}

double Timer::Elapsed() {
  return (Now() - started_) / Timer::kMicrosecondsPerSecond;
}

void Timer::Reset() {
  started_ = Now();
}


// TODO(knorton): crummy copy-paste of code.
void StringFormat(std::string* s, const char* fmt, va_list args) {
  int n, size=100;
  bool b=false;

  while (!b) {
    s->resize(size);
    n = vsnprintf((char*)s->c_str(), size, fmt, args);
    b = n < size;
    if (n > 0 && b) {
      s->resize(n);
    } else {
      size *= 2;
    }
  }
}

void StringFormat(std::string* s, const char* fmt, ...) {
  int n, size=100;
  bool b=false;
  va_list marker;

  while (!b) {
    s->resize(size);
    va_start(marker, fmt);
    n = vsnprintf((char*)s->c_str(), size, fmt, marker);
    va_end(marker);
    b = n < size;
    if (n > 0 && b) {
      s->resize(n);
    } else {
      size *= 2;
    }
  }
}

Status ParseInt(std::string& s, int base, int* v) {
  char* end;
  *v = strtol(s.c_str(), &end, 10);
  if (*end) {
    std::string err;
    StringFormat(&err, "invalid number format: %s", s.c_str());
    return ERR(err.c_str());
  }

  return NoErr();
}

Status Glob(const char* p, std::vector<std::string>* res) {
  glob_t gb;
  int err = glob(p, 0, NULL, &gb);
  if (err != 0) {
    return ERR("glob error");
  }

  for (size_t i = 0; i < gb.gl_pathc; i++) {
    res->push_back(gb.gl_pathv[i]);
  }

  globfree(&gb);

  return NoErr();
}


void PathJoin(std::string* par, const std::string& chd) {
  if (par->at(par->length() - 1) != '/') {
    par->append("/");
  }
  par->append(chd);
}

bool IsDirectory(const std::string& path) {
  struct stat s;
  if (stat(path.c_str(), &s) != 0)
    return false;
  return S_ISDIR(s.st_mode);
}

Status RemoveDirectory(const std::string& path, bool recursive) {
  struct dirent* e;
  DIR* d;
  std::string fp(path);
  fp.append("/");

  if (recursive) {
    d = opendir(path.c_str());
    if (!d) {
      std::string err;
      StringFormat(&err, "can't open dir: %s", path.c_str());
      return ERR(err.c_str());
    }

    while ((e = readdir(d)) != NULL) {
      if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) {
        continue;
      }

      fp.erase(path.length() + 1);
      fp.append(e->d_name);

      if (IsDirectory(fp)) {
        RemoveDirectory(fp);
      } else {
        if (unlink(fp.c_str()) != 0) {
          std::string err;
          StringFormat(&err, "unlink failed: %s", fp.c_str());
          return ERR(err.c_str());
        }
      }
    }

    closedir(d);
  }

  if (rmdir(path.c_str()) != 0) {
    std::string err;
    StringFormat(&err, "rmdir failed: %s", fp.c_str());
    return ERR(err.c_str());
  }

  return NoErr();
}

void Basename(std::string* res, std::string& path) {
  res->clear();
  if (path.empty()) {
    return;
  }

  size_t j = path.size()-1;
  do {
    if (path[j] == '/') {
      res->assign(path, j+1, path.size()-1);
      break;
    }
    j--;
  } while (j != 0);
}

Status MakeDirectory(const std::string& path) {
  if (mkdir(path.c_str(), S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH) != 0) {
    std::string err;
    StringFormat(&err, "mkdir failed: %s", path.c_str());
    return ERR(err.c_str());
  }
  return NoErr();
}

} // util