default: dev

list:
    just --list


test-moon:
    moon test --target all

test: test-moon

# Compilation is plain moon build; the js entry points land under
# _build/js/debug/build/ and scripts/build-web.mbtx stages them from there.
# Assemble editor.mjs, embed.mjs, style.css, codicon.ttf, and the HTML pages into web/dist
build-moon-web:
    moon build
    moon run --target native scripts/build-web.mbtx

# Stage the browser-correctness scenario bundles into web/dist/browser-tests
build-browser-tests: build-moon-web
    moon run --target native scripts/build-browser-tests.mbtx -- smoke

# Stage the perf scenarios plus the pinned Monaco oracle into web/dist/browser-tests
build-browser-perf-tests: build-moon-web
    moon run --target native scripts/build-browser-tests.mbtx -- perf

# Web assets and the native server binary (moon build covers the server member)
build: build-moon-web

# ---------------------------------------------------------------------------
# Serving. Override any variable by listing it BEFORE the recipe name
# (just's native override syntax):
#
#   just dev                            # build, then serve this repo on the LAN
#   just HOST=127.0.0.1 dev             # loopback only
#   just PORT=8080 serve                # serve without rebuilding
#   just ROOT=~/git/other-repo dev      # browse ANOTHER MoonBit repo with this
#                                       # viewer: readonly file tree, syntax
#                                       # highlighting, and `moon ide` hover /
#                                       # `moon check` diagnostics run in that
#                                       # repo's root (via MOON_COMMAND)
#
# `serve` defaults to loopback; `dev` defaults to 0.0.0.0 for trusted LANs.
# The reference server has no authentication and exposes ROOT's source files.
# ---------------------------------------------------------------------------

ROOT := "."
HOST := ""
PORT := "5173"
ASSET_DIR := "web/dist"
MOON_COMMAND := "moon"

serve:
    moon run server/host/main -- \
      --root "$(cd '{{ ROOT }}' && pwd)" \
      --host "{{ if HOST == '' { '127.0.0.1' } else { HOST } }}" \
      --port {{ PORT }} \
      --asset-dir "$(cd '{{ ASSET_DIR }}' && pwd)" \
      --moon-command "{{ MOON_COMMAND }}"

dev: build
    just ROOT='{{ ROOT }}' PORT='{{ PORT }}' ASSET_DIR='{{ ASSET_DIR }}' \
      MOON_COMMAND='{{ MOON_COMMAND }}' \
      HOST='{{ if HOST == '' { '0.0.0.0' } else { HOST } }}' serve

test-browser: test-browser-smoke

test-browser-smoke: build build-browser-tests
    ./node_modules/.bin/playwright test tests/browser/smoke tests/browser/component

test-browser-component: build build-browser-tests
    ./node_modules/.bin/playwright test tests/browser/component

test-browser-perf: build build-browser-perf-tests
    ./node_modules/.bin/playwright test tests/browser/perf
