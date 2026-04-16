.PHONY: all deps build clean lint deb rpm appimage dist

ARCH ?= $(shell uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')

all: build

deps:
	./scripts/install-deps.sh

build:
	ARCH_OVERRIDE=$(ARCH) ./build.sh

lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not installed"; exit 1; }
	shellcheck build.sh scripts/install-deps.sh

dist:
	@ls -la dist/ 2>/dev/null || echo "no dist/ yet — run 'make build'"

clean:
	rm -rf build dist

help:
	@echo "Targets:"
	@echo "  deps     install build dependencies (apt/dnf/pacman)"
	@echo "  build    run full build pipeline (ARCH=amd64|arm64)"
	@echo "  lint     shellcheck all shell scripts"
	@echo "  clean    remove build/ and dist/"
	@echo "  dist     show built artifacts"
