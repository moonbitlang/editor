default:
    just --list

check:
    moon check --target all --warn-list +73
    moon fmt --check

test-moon:
    moon test --target all

test: test-moon

build-moon-web:
    moon run --target native scripts/build-web.mbtx

build: check build-moon-web
    moon build --target native internal/shell/server_host_native/main

dev *args: build
    sh -c 'ROOT=.; PORT=5173; ASSET_DIR=web/dist; MOON_COMMAND=moon; for arg do case "$arg" in ROOT=*) ROOT="${arg#ROOT=}";; PORT=*) PORT="${arg#PORT=}";; ASSET_DIR=*) ASSET_DIR="${arg#ASSET_DIR=}";; MOON_COMMAND=*) MOON_COMMAND="${arg#MOON_COMMAND=}";; esac; done; moon run --target native internal/shell/server_host_native/main -- --root "$ROOT" --port "$PORT" --asset-dir "$ASSET_DIR" --moon-command "$MOON_COMMAND"' sh {{ args }}

test-browser: build
    ./node_modules/.bin/playwright test

test-browser-smoke: build
    ./node_modules/.bin/playwright test tests/browser/smoke

test-browser-component: build
    ./node_modules/.bin/playwright test tests/browser/component

test-browser-perf: build
    ./node_modules/.bin/playwright test tests/browser/perf
