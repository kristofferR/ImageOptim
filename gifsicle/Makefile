build: all

all: orig/src
	ln -sfn orig gifsicle

orig/src: ../.gitmodules
	../scripts/fetch-submodule orig && touch orig/src

clean:
	-rm -rf gifsicle

.PHONY: build all install clean
