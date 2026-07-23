# internal/shell/web

JS main package for the reference workbench. `main` calls
`workbench.start_app`; it exports no API and imports only the workbench package.

Application composition, browser FFI, URL/protocol selection, viewer mounting,
and harness behavior stay in `internal/shell/workbench`. This package must remain
an entrypoint rather than a shared domain layer.

`scripts/build-web.mbtx` bundles it as `web/dist/editor.mjs`, generates the HTML,
and assembles owner-adjacent CSS into `web/dist/style.css`; the native server
serves those assets. Run `just build-moon-web` (or `just build`). Browser harness
contracts are documented in `../../../docs/harness.md`.
