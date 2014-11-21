#include <stdio.h>
#include <string>
#include <vector>

#include "opencv2/core/core.hpp"
#include "opencv2/features2d/features2d.hpp"
#include "opencv2/highgui/highgui.hpp"
#include "opencv2/nonfree/nonfree.hpp"
#include "opencv2/calib3d/calib3d.hpp"
#include "opencv2/imgproc/imgproc.hpp"

#include "util.h"
#include "status.h"

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
    if (matches[i].distance < 3*min) {
      res->push_back(matches[i]);
    }
  }
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

  std::vector<cv::DMatch> good_matches;
  FindStrongMatches(&good_matches, matches);

  std::vector<cv::Point2f> pts_a, pts_b;
  for (int i = 0, n = good_matches.size(); i < n; i++) {
    pts_a.push_back(kp_a[good_matches[i].queryIdx].pt);
    pts_b.push_back(kp_b[good_matches[i].trainIdx].pt);
  }

  cv::Mat H = cv::findHomography(pts_a, pts_b, CV_RANSAC); 

  cv::Mat res;
  cv::warpPerspective(img_a, res, H, cv::Size(img_a.cols + img_b.cols, img_a.rows));
  cv::Mat half(res, cv::Rect(0, 0, img_b.cols, img_b.rows));
  img_b.copyTo(half);
  cv::imwrite(argv[3], res);

  return 0;
}