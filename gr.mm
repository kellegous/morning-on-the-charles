#include "gr.h"

#include "auto_ref.h"

namespace {

Status FileUrlFromString(CFURLRef* url, std::string& filename) {
  AutoRef<CFStringRef> fn = CFStringCreateWithCStringNoCopy(
      NULL,
      filename.c_str(),
      kCFStringEncodingUTF8,
      kCFAllocatorNull);
  if (!fn) {
    return ERR("cannot create string");
  }

  CFURLRef cfUrl = CFURLCreateWithFileSystemPath(
      NULL,
      fn,
      kCFURLPOSIXPathStyle,
      false);
  if (!cfUrl) {
    return ERR("cannot create url");
  }

  *url = cfUrl;

  return NoErr();
}

Status LoadFromCfUrl(CGImageRef* img, CFURLRef url) {
  AutoRef<CGDataProviderRef> cfIp = CGDataProviderCreateWithURL(url);
  if (!cfIp) {
    return ERR("cannot create data provider");
  }

  CGImageRef cgImg = CGImageCreateWithJPEGDataProvider(
      cfIp,
      NULL,
      false,
      kCGRenderingIntentDefault);
  if (!cgImg) {
    return ERR("cannot decode image");
  }

  *img = cgImg;
  return NoErr();
}

Status Export(CGImageRef img,
    std::string& filename,
    CFStringRef format,
    CFMutableDictionaryRef opts) {
  Status did;

  AutoRef<CFURLRef> url;
  did = FileUrlFromString(url.addr(), filename);
  if (!did.ok()) {
    return did;
  }

  AutoRef<CGImageDestinationRef> dst = CGImageDestinationCreateWithURL(
      url,
      format,
      1,
      NULL);
  if (!dst) {
    return ERR("cannot create imate destination");
  }

  CGImageDestinationAddImage(dst, img, opts);
  return NoErr();
}

} // anonymous

namespace gr {

//
CGContextRef NewContext(int w, int h) {
  return NewContext(NULL, w, h);
}

//
CGContextRef NewContext(uint8_t* data, int w, int h) {
  AutoRef<CGColorSpaceRef> colorSpace = CGColorSpaceCreateDeviceRGB();
  return CGBitmapContextCreate(
      data,
      w,
      h,
      8,
      w * 4,
      colorSpace,
      kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
}

//
CGRect BoundsOf(CGContextRef ctx) {
  return CGRectMake(
      0,
      0,
      CGBitmapContextGetWidth(ctx),
      CGBitmapContextGetHeight(ctx));
}


Status ExportAsJpg(CGImageRef img, std::string& filename, float qual) {
  CFMutableDictionaryRef opts = CFDictionaryCreateMutable(
      nil,
      0,
      &kCFTypeDictionaryKeyCallBacks,
      &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(
      opts,
      kCGImageDestinationLossyCompressionQuality,
      CFNumberCreate(NULL, kCFNumberFloat32Type, &qual));
  return Export(img, filename, kUTTypeJPEG, opts);
}

Status ExportAsJpg(CGContextRef ctx, std::string& filename, float qual) {
  AutoRef<CGImageRef> img = CGBitmapContextCreateImage(ctx);
  if (!img) {
    return ERR("cannot create image");
  }
  return ExportAsJpg(img, filename, qual);
}

//
Status ExportAsPng(CGImageRef img, std::string& filename) {
  return Export(img, filename, kUTTypePNG, NULL);
}

//
Status ExportAsPng(CGContextRef ctx, std::string& filename) {
  AutoRef<CGImageRef> img = CGBitmapContextCreateImage(ctx);
  if (!img) {
    return ERR("cannot create image");
  }

  return Export(img, filename, kUTTypePNG, NULL);
}

//
Status LoadFromUrl(CGImageRef* img, std::string& url) {
  *img = NULL;

  AutoRef<CFStringRef> cfUrlStr = CFStringCreateWithCStringNoCopy(
      NULL,
      url.c_str(),
      kCFStringEncodingUTF8,
      kCFAllocatorNull);
  if (!cfUrlStr) {
    return ERR("cannot create string");
  }

  AutoRef<CFURLRef> cfUrl = CFURLCreateWithString(
      NULL,
      cfUrlStr,
      NULL);
  if (!cfUrl) {
    return ERR("cannot create url");
  }

  return LoadFromCfUrl(img, cfUrl);
}

Status LoadFromFile(CGImageRef* img, std::string& filename) {
  *img = NULL;

  AutoRef<CFURLRef> url;
  Status did = FileUrlFromString(url.addr(), filename);
  if (!did.ok()) {
    return did;
  }

  return LoadFromCfUrl(img, url);
}

//
void DrawCoveringImage(CGContextRef ctx, CGImageRef img) {
  float sw = CGImageGetWidth(img);
  float sh = CGImageGetHeight(img);

  float dw = CGBitmapContextGetWidth(ctx);
  float dh = CGBitmapContextGetHeight(ctx);

  float sr = sw / sh;
  float dr = dw / dh;

  if (sr / dr > 1.0) {
    // fit height
    float csw = dh*sr;
    CGContextDrawImage(
      ctx,
      CGRectMake(dw/2 - csw/2, 0, csw, dh),
      img);
  } else {
    // fit width
    float csh = dw/sr;
    CGContextDrawImage(
      ctx,
      CGRectMake(0, dh/2 - csh/2, dw, csh),
      img);
  }
}

//
void DrawRoundedRect(CGContextRef ctx, CGPathDrawingMode mode, CGRect rect, float rad) {
  CGFloat minx = CGRectGetMinX(rect), midx = CGRectGetMidX(rect), maxx = CGRectGetMaxX(rect);
  CGFloat miny = CGRectGetMinY(rect), midy = CGRectGetMidY(rect), maxy = CGRectGetMaxY(rect);
  CGContextMoveToPoint(ctx, minx, midy);
  CGContextAddArcToPoint(ctx, minx, miny, midx, miny, rad);
  CGContextAddArcToPoint(ctx, maxx, miny, maxx, midy, rad);
  CGContextAddArcToPoint(ctx, maxx, maxy, midx, maxy, rad);
  CGContextAddArcToPoint(ctx, minx, maxy, minx, midy, rad);
  CGContextClosePath(ctx);
  CGContextDrawPath(ctx, mode);
}

}