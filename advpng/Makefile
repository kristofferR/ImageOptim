build: all

all:
	@if [ ! -f repng.cc ] || [ ! -f libdeflate/libdeflate.h ] || [ ! -f zopfli/zopfli.h ]; then \
		curl -fL https://github.com/amadvance/advancecomp/releases/download/v2.6/advancecomp-2.6.tar.gz | tar xz --strip-components=1; \
	fi

clean:

install:

.PHONY: build all install clean
