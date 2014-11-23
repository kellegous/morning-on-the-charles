#include <algorithm>
#include <fstream>
#include <getopt.h>
#include <math.h>
#include <memory>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <Cocoa/Cocoa.h>
#include <exiv2/exiv2.hpp>
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

struct Photo {
  Photo(std::string filename, cv::Mat image) : filename(filename), image(image) {
  }

  std::string filename;
  cv::Mat image;
  std::vector<cv::KeyPoint> key_points;
  cv::Mat descriptors;
};

struct Tx {
  Tx(double x, double y) : x(x), y(y) {
  } 

  double x, y;
};

Status ReadFileList(std::vector<std::string>* out, std::string& filename) {
  std::ifstream r(filename);
  if (!r.is_open()) {
    return ERR("unable to open file");
  }

  std::string line;

  while (!r.eof()) {
    line.clear();
    if (!std::getline(r, line, '\n')) {
      if (r.eof()) {
        break;
      }

      return ERR("read error");
    }

    line.erase(std::remove(line.begin(), line.end(), ' '), line.end());
    if (line.compare(0, 1, "#") == 0 || line.empty()) {
      continue;
    }

    out->push_back(line);
  }

  return NoErr();
}

void Panic(const std::string& msg) {
  fprintf(stderr, "ERROR: %s\n", msg.c_str());
  exit(1);
}

Status LoadPhotos( std::vector<std::shared_ptr<Photo> >* photos, std::string& filename) {
  std::vector<std::string> filenames;
  Status did = ReadFileList(&filenames, filename);
  if (!did.ok()) {
    return did;
  }

  cv::SurfFeatureDetector detector(400);
  cv::SurfDescriptorExtractor extractor;

  for (int i = 0, n = filenames.size(); i < n; i++) {
    const std::string path(filenames[i]);
    cv::Mat img = cv::imread(path.c_str(), CV_LOAD_IMAGE_GRAYSCALE);
    if (!img.data) {
      std::string err;
      util::StringFormat(&err, "read failed for %s", path.c_str());
      return ERR(err.c_str());
    }

    std::shared_ptr<Photo> photo(new Photo(path, img));
    detector.detect(img, photo->key_points);
    extractor.compute(img, photo->key_points, photo->descriptors);
    photos->push_back(photo);
    fprintf(stdout, "\r[ %02d / %02d ] : %s ", i+1, n, filenames[i].c_str());
    fflush(stdout);
  }

  printf("\ndone\n");
  return NoErr();
}

void FindMedianTransform(
    std::vector<cv::KeyPoint>& a,
    std::vector<cv::KeyPoint>& b,
    std::vector<cv::DMatch> m,
    double* x,
    double* y) {
  std::vector<double> dx, dy;
  dx.reserve(m.size());
  dy.reserve(m.size());

  for (int i = 0, n = m.size(); i < n; i++) {
    cv::Point2f ap = a[m[i].queryIdx].pt;
    cv::Point2f bp = b[m[i].trainIdx].pt;

    dx.push_back(bp.x - ap.x);
    dy.push_back(bp.y - ap.y);
  }

  std::sort(dx.begin(), dx.end());
  std::sort(dy.begin(), dy.end());

  *x = dx[dx.size() / 2];
  *y = dy[dy.size() / 2];
}

void FindTransforms(
    std::vector<Tx>* translations,
    std::vector<std::shared_ptr<Photo> > photos) {

  cv::FlannBasedMatcher matcher;

  std::vector<cv::DMatch> matches;
  Tx translation(0.0, 0.0);
  translations->push_back(translation);

  for (int i = 0, n = photos.size() - 1; i < n; i++) {
    matches.clear();

    matcher.match(photos[i]->descriptors, photos[i+1]->descriptors, matches);

    double dx, dy;

    FindMedianTransform(
      photos[i]->key_points,
      photos[i+1]->key_points,
      matches,
      &dx, &dy);

    translation.x += dx;
    translation.y += dy;
    translations->push_back(translation);

    fprintf(stdout, "\r[ %02d / %02d ] : %s & %s",
      i+1,
      n,
      photos[i]->filename.c_str(),
      photos[i+1]->filename.c_str());
    fflush(stdout);
  }

  printf("\ndone\n");
}

void SelectStrips(std::vector<std::shared_ptr<Photo> >& photos, std::vector<Tx>& transforms) {
  int w = photos[0]->image.cols;

  int dx = w / photos.size();

  for (int i = 0, n = photos.size(); i < n; i++) {
    double x = transforms[i].x;
    if (dx*i+dx+(int)x >= w) {
      photos.erase(photos.begin() + i);
      transforms.erase(transforms.begin() + i);
      SelectStrips(photos, transforms);
      return;
    }
  }
}

void FindVerticalBounds(double* top, double* bot, std::vector<Tx>& transforms) {
  double t = 0.0, b = 0.0;
  for (int i = 0, n = transforms.size(); i < n; i++) {
    Tx tx = transforms[i];
    if (tx.y > t) {
      t = tx.y;
    } else if (tx.y < b) {
      b = tx.y;
    }
  }
  *top = t;
  *bot = b;
}

Status RenderOverlayForEachTransform(
    const std::string& dest,
    std::vector<std::shared_ptr<Photo> >& photos,
    std::vector<Tx> transforms) {

  Status did;

  int w = photos[0]->image.cols;
  int h = photos[0]->image.rows;

  for (int i = 0, n = photos.size()-1; i < n; i++) {
    Tx txa = transforms[i];
    Tx txb = transforms[i+1];

    AutoRef<CGImageRef> ima, imb;
    did = gr::LoadFromFile(ima.addr(), photos[i]->filename);
    if (!did.ok()) {
      return did;
    }

    did = gr::LoadFromFile(imb.addr(), photos[i+1]->filename);
    if (!did.ok()) {
      return did;
    }

    double tx = txb.x - txa.x;
    double ty = txb.y - txa.y;

    AutoRef<CGContextRef> ctx = gr::NewContext(w, h);

    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), ima);

    CGContextSaveGState(ctx);
    CGContextSetAlpha(ctx, 0.5);
    CGContextTranslateCTM(ctx, -tx, -ty);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), imb);
    CGContextRestoreGState(ctx);

    std::string base;
    util::Basename(&base, photos[i]->filename);

    std::string path(dest);
    util::PathJoin(&path, base);
    did = gr::ExportAsJpg(ctx, path, 0.9);
    if (!did.ok()) {
      return did;
    }
  }

  return NoErr();
}

Status RenderTransformMap(
    const std::string& dest,
    float dst_width,
    float photo_width,
    float photo_height,
    std::vector<Tx>& transforms) {

  static float padding = 10.0;

  double minX = 0.0, maxX = 0.0, minY = 0.0, maxY = 0.0;
  for (int i = 0, n = transforms.size(); i < n; i++) {
    Tx tx = transforms[i];
    minX = std::min(tx.x, minX);
    minY = std::min(tx.y, minY);
    maxX = std::max(tx.x, maxX);
    maxY = std::max(tx.y, maxY);
  }

  double vw = photo_width + maxX - minX;
  double vh = photo_height + maxY - minY;

  double ar = vw / vh;
  double sf = (dst_width - padding*2.0) / vw;
  CGRect view = CGRectMake(0, 0, dst_width, (dst_width - padding*2.0) / ar + padding*2.0);

  AutoRef<CGContextRef> ctx = gr::NewContext(
      CGRectGetWidth(view),
      CGRectGetHeight(view));

  CGContextTranslateCTM(ctx, padding, padding);

  CGContextSetRGBStrokeColor(ctx, 1.0, 0.0, 0.6, 1.0);
  CGContextSetLineWidth(ctx, 2.0);
  for (int i = 0, n = transforms.size(); i < n; i++) {
    Tx tx = transforms[i];

    CGRect r = CGRectMake(
        sf * (tx.x - minX),
        sf * (tx.y - minY),
        sf * photo_width,
        sf * photo_height);
    CGContextStrokeRect(ctx, r);
  }

  return gr::ExportAsPng(ctx, dest);
}

Status RenderSlices(
    const std::string& dest,
    std::vector<std::shared_ptr<Photo> >& photos,
    std::vector<Tx>& transforms) {
  double top, bot;
  FindVerticalBounds(&top, &bot, transforms);

  int w = photos[0]->image.cols;
  int h = photos[0]->image.rows;

  int dx = w / photos.size();

  for (int i = 0, n = photos.size(); i < n; i++) {
    AutoRef<CGImageRef> img;
    Status did = gr::LoadFromFile(img.addr(), photos[i]->filename);
    if (!did.ok()) {
      return did;
    }

    Tx tx = transforms[i];

    AutoRef<CGContextRef> ctx = gr::NewContext(dx, h - (int)top + (int)bot);

    CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, dx, h - (int)top + (int)bot));

    AutoRef<CGImageRef> src = CGImageCreateWithImageInRect(
        img,
        CGRectMake(dx*i+tx.x, tx.y, dx, h));

    CGContextDrawImage(ctx, CGRectMake(0, 0, dx, h), src);

    std::string name;
    util::StringFormat(&name, "s%02d.jpg", i);

    std::string path(dest);
    util::PathJoin(&path, name);

    did = gr::ExportAsJpg(ctx, path, 0.9);
    if (!did.ok()) {
      return did;
    }

    fprintf(stdout, "\r[ %02d / %02d ] : s%02d.jpg", i, n, i);
    fflush(stdout);
  }

  printf("\ndone\n");
  return NoErr();
}

Status Render(
    const std::string& dest,
    std::vector<std::shared_ptr<Photo> >& photos,
    std::vector<Tx>& transforms) {
  double top, bot;
  FindVerticalBounds(&top, &bot, transforms);

  int w = photos[0]->image.cols;
  int h = photos[0]->image.rows;

  int dx = w / photos.size();

  AutoRef<CGContextRef> ctx = gr::NewContext(w, h - (int)top + (int)bot);

  CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 1.0);
  CGContextFillRect(ctx, CGRectMake(0, 0, w, h-top+bot));

  for (int i = 0, n = photos.size(); i < n; i++) {
    AutoRef<CGImageRef> img;
    Status did = gr::LoadFromFile(img.addr(), photos[i]->filename);
    if (!did.ok()) {
      return did;
    }

    Tx tx = transforms[i];

    AutoRef<CGImageRef> src = CGImageCreateWithImageInRect(
        img,
        CGRectMake(dx*i+tx.x, tx.y, dx, h));

    CGContextDrawImage(
        ctx,
        CGRectMake(dx*i, -top, dx, h),
        src);
  }

  std::string path(dest);
  util::PathJoin(&path, "render.jpg");
  return gr::ExportAsJpg(ctx, path, 0.9);
}

void PrintUsage() {
  fprintf(stderr, "Usage: strip [--dest=dir] file_list\n");
}

bool ParseArgs(int argc, char* argv[],
    std::string* src_file,
    std::string* dest_dir,
    bool* render_overlay_for_each_transform,
    bool* render_transform_map) {
  int c;

  while (true) {
    static struct option opts[] = {
      { "render-overlay-for-each-transform", no_argument, 0, 't' },
      { "render-transform-map", no_argument, 0, 'm'},
      { "dest", required_argument, 0, 'd' },
      { 0, 0, 0, 0}
    };

    int opt_index = 0;

    c = getopt_long(argc, argv, "", opts, &opt_index);
    if (c == -1) {
      break;
    }

    switch (c) {
    case 'd':
      dest_dir->assign(optarg);
      break;
    case 't':
      *render_overlay_for_each_transform = true;
      break;
    case 'm':
      *render_transform_map = true;
      break;
    default:
      PrintUsage();
      return false;
    }
  }

  if (argc - optind != 1) {
    PrintUsage();
    return false;
  }

  src_file->assign(argv[optind]);

  return true;
}

Status ExtractExifDate(std::string* out, const char* format, std::string filename) {
  try {
    Exiv2::Image::AutoPtr image = Exiv2::ImageFactory::open(filename.c_str());
    if (!image.get()) {
      std::string err;
      util::StringFormat(&err, "open failed: %s", filename.c_str());
      return ERR(err.c_str());
    }

    image->readMetadata();
    Exiv2::ExifData& data = image->exifData();
    if (data.empty()) {
      std::string err;
      util::StringFormat(&err, "empty exif data: %s", filename.c_str());
      return ERR(err.c_str());
    }

    Exiv2::ExifKey key("Exif.Photo.DateTimeOriginal");
    Exiv2::ExifData::const_iterator it = data.findKey(key);
    if (it == data.end()) {
      std::string err;
      util::StringFormat(&err, "no datetime: %s", filename.c_str());
      return ERR(err.c_str());
    }

    char buf[20];
    struct tm tm;

    memset(&tm, 0, sizeof(struct tm));
    if (strptime(it->value().toString().c_str(), "%Y:%m:%d %H:%M:%S", &tm) == NULL) {
      std::string err;
      util::StringFormat(&err, "invalid date: %s", filename.c_str());
      return ERR(err.c_str());
    }

    strftime(buf, sizeof(buf), format, &tm);
    out->assign(buf);
  } catch (Exiv2::AnyError& e) {
    std::string err;
    util::StringFormat(&err, "exif failed: %s", e.what());
    return ERR(err.c_str());
  }

  return NoErr();
}

Status WriteInfoFile(std::string& filename, std::vector<std::shared_ptr<Photo> >& photos) {
  util::File file;
  Status did = file.Open(filename.c_str(), "w");
  if (!did.ok()) {
    return did;
  }

  std::string t;
  if (fprintf(file.get(), "[\n") < 0) {
    return ERR("write error");
  }

  for (int i = 0, n = photos.size(); i < n; i++) {
    did = ExtractExifDate(&t, "%I:%M%p", photos[i]->filename);
    if (!did.ok()) {
      return did;
    }

    if (fprintf(file.get(),
        (i < n-1) ? "  \"%s\",\n" : "  \"%s\"\n",
        t.c_str()) < 0) {
      return ERR("write error");
    }
  }

  if (fprintf(file.get(), "]\n") < 0) {
    return ERR("write error");
  }

  return NoErr();
}

} // anonymous

int main(int argc, char* argv[]) {

  std::string dest("out");
  std::string data("day.txt");
  bool render_overlay_for_each_transform = false;
  bool render_transform_map = false;

  if (!ParseArgs(argc, argv,
      &data,
      &dest,
      &render_overlay_for_each_transform,
      &render_transform_map)) {
    return 1;
  }

  std::vector<std::shared_ptr<Photo> > photos;

  Status did = LoadPhotos(&photos, data);
  if (!did.ok()) {
    Panic(did.what());
  }

  std::vector<Tx> transforms;

  FindTransforms(&transforms, photos);

  SelectStrips(photos, transforms);

  if (!util::IsDirectory(dest)) {
    did = util::MakeDirectory(dest);
    if (!did.ok()) {
      Panic(did.what());
    }
  }

  if (render_overlay_for_each_transform) {
    did = RenderOverlayForEachTransform(dest, photos, transforms);
    if (!did.ok()) {
      Panic(did.what());
    }
  }

  if (render_transform_map) {
    std::string file(dest);
    util::PathJoin(&file, "transform.png");
    did = RenderTransformMap(
        file,
        900,
        photos[0]->image.cols,
        photos[0]->image.rows,
        transforms);
    if (!did.ok()) {
      Panic(did.what());
    }
  }

  did = Render(dest, photos, transforms);
  if (!did.ok()) {
    Panic(did.what());
  }

  did = RenderSlices(dest, photos, transforms);
  if (!did.ok()) {
    Panic(did.what());
  }

  std::string info(dest);
  util::PathJoin(&info, "info.json");
  did = WriteInfoFile(info, photos);
  if (!did.ok()) {
    Panic(did.what());
  }

  return 0;
}
