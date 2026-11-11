APP := build/Floater.app

.PHONY: build run dev watch install uninstall demo clean help

## build: build build/Floater.app
build:
	./build.sh

## run: build and launch, floating the image on the clipboard
run: build
	open -n $(APP)

## dev: rebuild and relaunch, restoring the last image, position and size
dev: build
	open -n $(APP) --args --restore

## watch: run `make dev` whenever a source file changes (needs entr: brew install entr)
watch:
	@command -v entr >/dev/null || { echo "make watch needs entr: brew install entr"; exit 1; }
	find Sources Package.swift | entr -d $(MAKE) dev

## install: build and copy to /Applications
install: build
	rm -rf /Applications/Floater.app
	cp -R $(APP) /Applications/
	@echo "Installed /Applications/Floater.app"

## uninstall: remove /Applications/Floater.app
uninstall:
	rm -rf /Applications/Floater.app

## demo: re-render docs/demo.gif (needs Pillow and ffmpeg; see docs/demo/GUIDE.md)
demo:
	python3 docs/demo/demo.py

## clean: remove build output
clean:
	rm -rf .build build

## help: list targets
help:
	@grep '^## ' Makefile | sed 's/^## /  /'
