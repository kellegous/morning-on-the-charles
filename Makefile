CFLAGS=-Wall $(shell pkg-config --cflags opencv)
LDFLAGS=$(shell pkg-config --libs opencv) -framework Cocoa -lcurl

OBJS=util.o status.o gr.o

ALL: strip

%.o: %.cc %.h
	g++ $(CFLAGS) -c -o $@ $<

gr.o: gr.mm gr.h
	g++ $(CFLAGS) -c -o $@ $<

strip.o: strip.mm strip.h
	g++ $(CFLAGS) -c -o $@ $<

strip: strip.o $(OBJS)
	g++ $(LDFLAGS) -o $@ strip.o $(OBJS)

clean:
	rm -f $(OBJS) strip