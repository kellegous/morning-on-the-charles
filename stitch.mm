#include <stdio.h>
#include <string>
#include <vector>
#include <Cocoa/Cocoa.h>
#include "opencv2/core/core.hpp"
#include "opencv2/features2d/features2d.hpp"
#include "opencv2/highgui/highgui.hpp"
#include "opencv2/nonfree/nonfree.hpp"
#include "opencv2/calib3d/calib3d.hpp"
#include "opencv2/imgproc/imgproc.hpp"

#include "auto_ref.h"
#include "gr.h"
#include "status.h"
#include "util.h"

namespace {

void PrintUsage() {
  fprintf(stderr, "usage: stitch in1.jpg in2.jpg\n");
}

void Panic(const char* msg) {
  fprintf(stderr, "ERROR: %s\n", msg);
  exit(1);
}

Status ReadImage(cv::Mat* mat, const char* filename) {
  cv::Mat m = cv::imread(filename);
  if (!m.data) {
    std::string err;
    util::StringFormat(&err, "read failure: %s", filename);
    return ERR(err.c_str());
  }

  *mat = m;
  return NoErr();
}

Status ConvertColorspace(cv::Mat* dst, cv::Mat src, int cs) {
  cv::Mat m;
  cv::cvtColor(src, m, cs);
  if (!m.data) {
    return ERR("conversion failed");
  }

  *dst = m;
  return NoErr();
}

void FindStrongMatches(std::vector<cv::DMatch>* res, std::vector<cv::DMatch>& matches) {
  double min = 100.0;
  for (int i = 0, n = matches.size(); i < n; i++) {
    double dist = matches[i].distance;
    if (dist < min) {
      min = dist;
    }
  }

  for (int i = 0, n = matches.size(); i < n; i++) {
    if (matches[i].distance < 4*min) {
      res->push_back(matches[i]);
    }
  }
}

void FindMaxAndMin(float* max, float* min, const std::vector<cv::DMatch>& matches) {
  float mn = 1e6, mx = -1e6;
  for (int i = 0, n = matches.size(); i < n; i++) {
    float dist = matches[i].distance;
    mn = std::min(mn, dist);
    mx = std::max(mx, dist);
  }
  *min = mn;
  *max = mx;
}

Status Render(const std::string& dest,
    const std::string& img_a,
    const std::string& img_b,
    const std::vector<cv::KeyPoint>& kp_a,
    const std::vector<cv::KeyPoint>& kp_b,
    const std::vector<cv::DMatch>& matches) {

  Status did;

  AutoRef<CGImageRef> ma;
  did = gr::LoadFromFile(ma.addr(), img_a);
  if (!did.ok()) {
    return did;
  }

  AutoRef<CGImageRef> mb;
  did = gr::LoadFromFile(mb.addr(), img_b);
  if (!did.ok()) {
    return did;
  }

  size_t w = CGImageGetWidth(ma), h = CGImageGetHeight(mb);

  AutoRef<CGContextRef> ctx = gr::NewContext(w, h);

  CGRect view = CGRectMake(0, 0, w, h);

  CGContextDrawImage(ctx, view, ma);

  CGContextSaveGState(ctx);
  CGContextSetAlpha(ctx, 0.5);
  CGContextDrawImage(ctx, view, mb);
  CGContextRestoreGState(ctx);

  CGContextTranslateCTM(ctx, 0, h);
  CGContextScaleCTM(ctx, 1.0, -1.0);
  CGContextSetLineWidth(ctx, 2.0);

  CGContextSetRGBStrokeColor(ctx, 1.0, 0.6, 0.0, 1.0);
  CGContextSetRGBFillColor(ctx, 1.0, 0.6, 0.0, 1.0);

  float min, max;
  FindMaxAndMin(&min, &max, matches);

  static float limit = 0.65;
  static float size = 10;

  for (int i = 0, n = matches.size(); i < n; i++) {
    cv::Point2f pa = kp_a[matches[i].queryIdx].pt;
    cv::Point2f pb = kp_b[matches[i].trainIdx].pt;
    float diff = (matches[i].distance - min)  / (max - min);
    if (diff < limit) {
      continue;
    }
    CGContextSaveGState(ctx);
    CGContextSetAlpha(ctx, (diff - limit)/(1.0 - limit));
    CGContextSetLineWidth(ctx, 2.0);
    CGContextMoveToPoint(ctx, pa.x, pa.y);
    CGContextAddLineToPoint(ctx, pb.x, pb.y);
    CGContextStrokePath(ctx);
    CGContextFillEllipseInRect(ctx, CGRectMake(pa.x - size/2, pa.y - size/2, size, size));
    CGContextFillEllipseInRect(ctx, CGRectMake(pb.x - size/2, pb.y - size/2, size, size));
    CGContextRestoreGState(ctx);
  }

  return gr::ExportAsJpg(ctx, dest, 0.9);
}

} // anonymous

int main(int argc, char* argv[]) {
  if (argc != 4) {
    PrintUsage();
    return 1;
  }

  Status did;

  cv::Mat img_a;
  did = ReadImage(&img_a, argv[1]);
  if (!did.ok()) {
    Panic(did.what());
  }

  cv::Mat img_b;
  did = ReadImage(&img_b, argv[2]);
  if (!did.ok()) {
    Panic(did.what());
  }

  cv::Mat gimg_a;
  did = ConvertColorspace(&gimg_a, img_a, CV_RGB2GRAY);
  if (!did.ok()) {
    Panic(did.what());
  }

  cv::Mat gimg_b;
  did = ConvertColorspace(&gimg_b, img_b, CV_RGB2GRAY);
  if (!did.ok()) {
    Panic(did.what());
  }

  cv::SurfFeatureDetector detector(400);
  std::vector<cv::KeyPoint> kp_a, kp_b;
  detector.detect(gimg_a, kp_a);
  detector.detect(gimg_b, kp_b);

  cv::SurfDescriptorExtractor extractor;
  cv::Mat des_a, des_b;
  extractor.compute(gimg_a, kp_a, des_a);
  extractor.compute(gimg_b, kp_b, des_b);

  cv::FlannBasedMatcher matcher;
  std::vector<cv::DMatch> matches;
  matcher.match(des_a, des_b, matches);

  did = Render(
      std::string(argv[3]),
      std::string(argv[1]),
      std::string(argv[2]),
      kp_a,
      kp_b,
      matches);
  if (!did.ok()) {
    Panic(did.what());
  }
  // cv::Mat H = cv::findHomography(pts_a, pts_b, CV_RANSAC); 

  // cv::Mat res;
  // cv::warpPerspective(img_a, res, H, cv::Size(img_a.cols + img_b.cols, img_a.rows));
  // cv::Mat half(res, cv::Rect(0, 0, img_b.cols, img_b.rows));
  // img_b.copyTo(half);
  // cv::imwrite(argv[3], res);

  return 0;
}