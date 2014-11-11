
template <typename T>
struct AutoRefTraits;

template<>
struct AutoRefTraits<CFStringRef> {
  static void Release(CFStringRef ref) {
    CFRelease(ref);
  }
};

template<>
struct AutoRefTraits<CGColorSpaceRef> {
  static void Release(CGColorSpaceRef ref) {
    CFRelease(ref);
  }
};

template<>
struct AutoRefTraits<CGContextRef> {
  static void Release(CGContextRef ref) {
    CGContextRelease(ref);
  }
};

template<>
struct AutoRefTraits<CFURLRef> {
  static void Release(CFURLRef ref) {
    CFRelease(ref);
  }
};

template<>
struct AutoRefTraits<CGImageRef> {
  static void Release(CGImageRef ref) {
    CFRelease(ref);
  }
};

template<>
struct AutoRefTraits<CGImageDestinationRef> {
  static void Release(CGImageDestinationRef ref) {
    CGImageDestinationFinalize(ref);
  }
};

template<>
struct AutoRefTraits<CGDataProviderRef> {
  static void Release(CGDataProviderRef ref) {
    CGDataProviderRelease(ref);
  }
};

template<>
struct AutoRefTraits<CGColorRef> {
  static void Release(CGColorRef ref) {
    CGColorRelease(ref);
  }
};

template<typename T, typename Traits = AutoRefTraits<T> >
class AutoRef {
 public:
  AutoRef() : ref_(NULL) {}

  AutoRef(T ref) : ref_(ref) {}

  ~AutoRef() {
    reset();
  }

  T* addr() {
    return &ref_;
  }

  T get() {
    return ref_;
  }

  bool operator==(T that) {
    return ref_ == that;
  }

  bool operator!=(T that) {
    return ref_ != that;
  }

  operator T() const {
    return ref_;
  }

  void set(T ref) {
    if (ref_) {
      Traits::Release(ref_);
    }
    ref_ = ref;
  }

  void reset() {
    set(NULL);
  }

  AutoRef& operator=(T ref) {
    set(ref);
    return *this;
  }
 private:
  T ref_;
};

