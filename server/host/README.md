# server/host

Native effect adapter and executable backend for the reference shell.

## Runtime

- `NativeServerHost` implements `server.ServerHost`: root-contained text reads,
  one-level directory reads, and polling watches (500 ms by default).
- `run_native_editor_server` serves `web/dist` over HTTP and `/protocol` over
  WebSocket. It binds to `127.0.0.1` by default. Pass `host="0.0.0.0"` to
  accept IPv4 traffic from every interface; startup output then includes the
  localhost URL and, when the operating system has a default route, the
  selected LAN URL. Each connection owns an isolated remote-server session,
  unbounded outbox, and socket writer, so closing one connection cannot dispose
  another's watches and concurrent watch/diagnostic pushes cannot interleave
  frames.
- `MoonWorkspaceLanguageProvider` implements hover with
  `moon ide hover --output-json --no-check`. Definition, references, document
  symbols currently return no result.
- `MoonCheckDiagnostics` coalesces document syncs into single-flight
  `moon check --output-json` runs, remembers the latest revision, pushes clears,
  and broadcasts per-file diagnostics to every connected session.
- URI/root validation, file watching, process execution, static serving, and
  Moon CLI output parsing are owned here; protocol policy remains in `server`.

Public entry points also include `native_server_host`, hover/check parsers, and
the configurable constructors. The `main` package accepts `--root`, `--host`,
`--port`, `--asset-dir`, and `--moon-command`.

The reusable API, direct CLI, and lower-level `just serve` recipe remain
loopback-only by default. The developer launcher instead defaults to
`HOST=0.0.0.0`, so plain `just dev` prints both the Local URL and the LAN URL
detected from the default route. Set `HOST=127.0.0.1` to bind and print only the
Local URL.

**Warning:** the reference server has no authentication and exposes workspace
source files. Use the default Just launcher only on a trusted LAN.

## Boundary and validation

This package is native-only and is not part of the reusable viewer API. It owns
concrete host/provider behavior, but not protocol packet routing or browser UI.

Run `moon test server/host`, `just build`,
or launch it with `just dev ROOT=. PORT=5173`. Use `HOST=127.0.0.1` when the
workspace must remain local to the development machine.
