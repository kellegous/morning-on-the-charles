#!/usr/bin/env python2.7

import glob
import os
import sys
import subprocess

def main():
  if not os.path.exists('out'):
    os.mkdirs('out')
  files = glob.glob('photos/*.JPG')
  for ix in range(len(files)-1):
    a, b = files[ix], files[ix+1]
    dst = os.path.join(
      'out',
      '%s-%s.jpg' % (os.path.basename(a[:-4]), os.path.basename(b[:-4])))
    st = subprocess.call(['./stitch', a, b, dst])
    if st != 0:
      return st
  return 0

if __name__ == '__main__':
  sys.exit(main())