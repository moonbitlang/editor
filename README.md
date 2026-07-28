# Readonly MoonBit Viewer

The source checkout has two main parts. The published Mooncakes package
contains the reusable viewer; the reference shell is repository-only:

- `viewer`: the reusable MoonBit readonly viewer. It is Monaco-shaped in API
  and behavior where that helps embedders, but it stays MoonBit-owned and does
  not import Monaco, VS Code, or CodeMirror code.
- `internal/shell`: the reference app/backend used to see the viewer working
  against a real workspace. It demonstrates one host composition and must use
  the viewer through public APIs; it is not an external import surface.

Monaco/VS Code is the primary design reference. CodeMirror is a secondary
reference when its simpler state/view split is useful. Both submodules are
reference-only.

## Installation

```sh
moon add moonbitlang/editor@0.2.1
```

## Browser Runtime

Whole-line Markdown comments render exact lowercase `d2` and `diago` fences
synchronously with the bundled Diago compiler. Exact lowercase `mermaid`
fences use Mermaid's official browser implementation, loaded lazily from the
pinned `https://cdn.jsdelivr.net/npm/mermaid@11.16.0/` ESM distribution.
Mermaid is not an npm dependency and is not bundled into the viewer.

Embedders that want diagram rendering must allow `https://cdn.jsdelivr.net` in
their module-script CSP, including Mermaid's relative ESM chunks, and must
permit the inline styles used inside Mermaid SVG output. Dynamic `import()`
cannot attach SRI metadata. If the CDN is offline or blocked, or if a diagram
is invalid, the viewer keeps the safe tokenized source code visible.

## Repository Development

```sh
npm install
just check
just build
just dev ROOT=. PORT=5173
```

Open `http://127.0.0.1:5173/`. The dev server is the internal native backend
shell: it serves `web/dist` and talks to the browser workbench over the
readonly remote protocol WebSocket.

## Validation

```sh
just check
just test
just build
just test-browser-smoke
```

Current architecture lives in [docs/architecture.md](docs/architecture.md).
Browser harness behavior lives in [docs/harness.md](docs/harness.md).
