This is the source code that accompanies a blog post [Surfing The Charles](http://www.kellegous.com/j/2014/11/30/surfing-the-charles/) about another blog post [A Morning on the Charles](http://www.kellegous.com/j/2014/11/08/morning-on-the-charles/). Yes, this is quite "meta".

### Requirements
* OS X (Sorry, porting to [cairo](http://cairographics.org/) should be easy enough).
* [OpenCV](http://opencv.org/) `brew install opencv`
* [Exiv2](http://www.exiv2.org/) `brew install exiv2`

### Building & Running

     make
     ./strip sunrise.txt

This will download the photos used in the original blog post, build the binaries, and run the program to produce the
images trips (placed in the `out` directory).

### Questions:
Feel free to contact me with questions about the code [http://www.kellegous.com/about](http://kellegous.com/about).