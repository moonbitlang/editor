default: dev

list:
    just --list

check:
    MOON_WORK=off moon check --target all --warn-list +73
    MOON_WORK=off moon fmt --check

test-moon:
    MOON_WORK=off moon test --target all

test: test-moon

build-moon-web:
    MOON_WORK=off moon run --target native scripts/build-web.mbtx

build-browser-tests: build-moon-web
    MOON_WORK=off moon run --target native scripts/build-browser-tests.mbtx -- smoke

build-browser-perf-tests: build-moon-web
    MOON_WORK=off moon run --target native scripts/build-browser-tests.mbtx -- perf

build: check build-moon-web
    MOON_WORK=off moon build --target native internal/shell/server_host_native/main

serve *args:
    sh -c 'ROOT=.; HOST=127.0.0.1; PORT=5173; ASSET_DIR=web/dist; MOON_COMMAND=moon; for arg do case "$arg" in ROOT=*) ROOT="${arg#ROOT=}";; HOST=*) HOST="${arg#HOST=}";; PORT=*) PORT="${arg#PORT=}";; ASSET_DIR=*) ASSET_DIR="${arg#ASSET_DIR=}";; MOON_COMMAND=*) MOON_COMMAND="${arg#MOON_COMMAND=}";; esac; done; case "$ROOT" in /*) ;; *) ROOT="$(cd "$ROOT" && pwd)" || exit 1;; esac; case "$ASSET_DIR" in /*) ;; *) ASSET_DIR="$(cd "$ASSET_DIR" && pwd)" || exit 1;; esac; MOON_WORK=off moon run --target native internal/shell/server_host_native/main -- --root "$ROOT" --host "$HOST" --port "$PORT" --asset-dir "$ASSET_DIR" --moon-command "$MOON_COMMAND"' sh {{ args }}

dev *args: build
    just serve HOST=0.0.0.0 {{ args }}

test-browser: test-browser-smoke

test-browser-smoke: build build-browser-tests
    ./node_modules/.bin/playwright test tests/browser/smoke tests/browser/component

test-browser-component: build build-browser-tests
    ./node_modules/.bin/playwright test tests/browser/component

test-browser-perf: build build-browser-perf-tests
    ./node_modules/.bin/playwright test tests/browser/perf
