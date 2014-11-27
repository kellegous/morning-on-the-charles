#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <Cocoa/Cocoa.h>
#include "opencv2/core/core.hpp"
#include "opencv2/features2d/features2d.hpp"
#include "opencv2/nonfree/features2d.hpp"
#include "opencv2/calib3d/calib3d.hpp"
#include "opencv2/highgui/highgui.hpp"
#include "opencv2/nonfree/nonfree.hpp"
#include "opencv2/video/tracking.hpp"

#include "auto_ref.h"
#include "gr.h"
#include "status.h"
#include "util.h"

namespace {

void PrintUsage() {
  printf("usage\n");
}

bool ParseArgs(int argc, char* argv[], std::string* src, std::string* dst) {
  if (argc < 3) {
    PrintUsage();
    return false;
  }

  src->assign(argv[1]);
  dst->assign(argv[2]);
  return true;
}

void Panic(const std::string& msg) {
  fprintf(stderr, "%s\n", msg.c_str());
  exit(1);
}

Status Render(std::string& src, std::string& dst, std::vector<cv::KeyPoint>& keypoints) {
  AutoRef<CGImageRef> img;
  Status did = gr::LoadFromFile(img.addr(), src);
  if (!did.ok()) {
    return did;
  }

  size_t w = CGImageGetWidth(img);
  size_t h = CGImageGetHeight(img);
  AutoRef<CGContextRef> ctx = gr::NewContext(w, h);

  CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);

  CGContextTranslateCTM(ctx, 0, h);
  CGContextScaleCTM(ctx, 1.0, -1.0);
  CGContextSetLineWidth(ctx, 2.0);
  // CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 0.2);
  // CGContextSetRGBStrokeColor(ctx, 1.0, 1.0, 1.0, 0.6);
  CGContextSetRGBFillColor(ctx, 0.6, 0.0, 0.0, 0.05);
  CGContextSetRGBStrokeColor(ctx, 0.6, 0.0, 0.0, 0.5);
  // static float size = 10.0;
  for (int i = 0, n = keypoints.size(); i < n; i++) {
    cv::KeyPoint k = keypoints[i];
    CGRect r = CGRectMake(k.pt.x - k.size/2.0, k.pt.y - k.size/2.0, k.size, k.size);
    // CGRect r = CGRectMake(k.pt.x - size/2.0, k.pt.y - size/2.0, size, size);
    CGContextFillEllipseInRect(ctx, r);
    CGContextStrokeEllipseInRect(ctx, r);
  }

  did = gr::ExportAsJpg(ctx, dst, 0.8);
  if (!did.ok()) {
    return did;
  }

  return NoErr();
}

void FilterKeyPoints(std::vector<cv::KeyPoint>* out, std::vector<cv::KeyPoint>& pts, double p) {
  srand(0x422);
  for (std::vector<cv::KeyPoint>::iterator it = pts.begin(); it != pts.end(); it++) {
    double r = ((double) rand() / (RAND_MAX));
    if (r < p) {
      out->push_back(*it);
    }
  }
}

} // anonymous

int main(int argc, char* argv[]) {
  std::string src, dst;

  if (!ParseArgs(argc, argv, &src, &dst)) {
    return 1;
  }

  cv::Mat img = cv::imread(src.c_str(), CV_LOAD_IMAGE_GRAYSCALE);
  if (!img.data) {
    std::string err;
    util::StringFormat(&err, "read failed for %s", src.c_str());
    Panic(err.c_str());
  }

  std::vector<cv::KeyPoint> keypoints;
  cv::SurfFeatureDetector detector(400);

  detector.detect(img, keypoints);

  std::vector<cv::KeyPoint> filtered;
  // FilterKeyPoints(&filtered, keypoints, 0.1);

  Status did = Render(src, dst, keypoints);
  if (!did.ok()) {
    Panic(did.what());
  }

  printf("found %ld keypoints.\n", keypoints.size());

  return 0;
}