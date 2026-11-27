PREFIX ?= /usr/local
BIN := $(shell swift build -c release --show-bin-path)/testid-inject

.PHONY: build install uninstall test

build:
	swift build -c release

install: build
	install -d "$(PREFIX)/bin"
	install -m 755 "$(BIN)" "$(PREFIX)/bin/testid-inject"

uninstall:
	rm -f "$(PREFIX)/bin/testid-inject"

test:
	swift test
