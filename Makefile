.POSIX:
CC        = clang
OBJCFLAGS = -fobjc-arc -Wall -O3
LDLIBS    = -framework Cocoa -framework Foundation
PREFIX    = /usr/local

all: copyfile

install: copyfile
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	mkdir -p $(DESTDIR)$(PREFIX)/share/man/man1
	cp -f copyfile $(DESTDIR)$(PREFIX)/bin
	gzip < copyfile.1 > $(DESTDIR)$(PREFIX)/share/man/man1/copyfile.1.gz

copyfile: copyfile.o
	$(CC) $(OBJCFLAGS) $(LDFLAGS) -o copyfile copyfile.o $(LDLIBS)

copyfile.o: copyfile.m

clean:
	rm -f copyfile copyfile.o
