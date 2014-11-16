CFLAGS=-Wall $(shell pkg-config --cflags opencv exiv2)
LDFLAGS=$(shell pkg-config --libs opencv exiv2) -framework Cocoa -lcurl

OBJS=util.o status.o gr.o

URL=https://dl.dropboxusercontent.com/u/4920373/morning-on-the-charles.tar

ALL: photos/10035.JPG strip

%.o: %.cc %.h
	g++ $(CFLAGS) -c -o $@ $<

gr.o: gr.mm gr.h
	g++ $(CFLAGS) -c -o $@ $<

strip.o: strip.mm strip.h
	g++ $(CFLAGS) -c -o $@ $<

strip: strip.o $(OBJS)
	g++ $(LDFLAGS) -o $@ strip.o $(OBJS)

photos/10035.JPG:
	mkdir -p photos
	curl --silent $(URL) | tar x -mC photos

clean:
	rm -f $(OBJS) strip