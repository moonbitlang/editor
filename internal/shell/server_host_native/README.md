# internal/shell/server_host_native

Native effect adapter and executable backend for the reference shell.

## Runtime

- `NativeServerHost` implements `server.ServerHost`: root-contained text reads,
  one-level directory reads, and polling watches (500 ms by default).
- `run_native_editor_server` serves `web/dist` over HTTP and `/protocol` over
  WebSocket. Each connection has one unbounded outbox and one socket writer, so
  responses and concurrent watch/diagnostic pushes cannot interleave frames.
- `MoonWorkspaceLanguageProvider` implements hover with
  `moon ide hover --output-json --no-check`. Definition, references, document
  symbols currently return no result.
- `MoonCheckDiagnostics` coalesces document syncs into single-flight
  `moon check --output-json` runs, remembers the latest revision, pushes clears,
  and broadcasts per-file diagnostics to every connected session.
- URI/root validation, file watching, process execution, static serving, and
  Moon CLI output parsing are owned here; protocol policy remains in `server`.

Public entry points also include `native_server_host`, hover/check parsers, and
the configurable constructors. The `main` package accepts `--root`, `--port`,
`--asset-dir`, and `--moon-command`.

## Boundary and validation

This package is native-only and is not part of the reusable viewer API. It owns
concrete host/provider behavior, but not protocol packet routing or browser UI.

Run `moon test internal/shell/server_host_native --target native`, `just build`,
or launch it with `just dev ROOT=. PORT=5173`.
