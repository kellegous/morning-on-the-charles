#ifndef STATUS_H_
#define STATUS_H_

#include <string>

// A lightweight object used to return error codes in a sane way.
// 
// TODO(knorton): This could be lighter, it currently copies data_ at
// every level of the call stack.
class Status {
 public:
  Status() {}
  Status(const char* msg, const char* file);

  // A description of what went wrong. "" for NoErr();
  const char* what();

  // The definitive way to tell if this was success/failure.
  bool ok() {
    return data_.empty();
  }
 private:
  std::string data_;
};

// An internned version of the NoErr object.
extern const Status NoErr();

// The easiest way to create an error.
#define ERR(M) Status(M, __FILE__);

#endif // STATUS_H_