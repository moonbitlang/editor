# base/common

Host-neutral primitives at the bottom of the editor dependency graph.

## Surface and contracts

- `Uri` stores decoded `scheme`, `authority`, `path`, `query`, and `fragment`;
  `parse`, `from`, and `with_` raise `UriError` on invalid input. `ExtUri`,
  `resources.mbt`, and `uri_to_fs_path` provide resource comparison, joining,
  normalization, and filesystem conversion.
- `Posix`/`Win32`, `path.mbt`, and `extpath.mbt` provide path operations without
  depending on the host filesystem. Platform and process facts have target-specific
  JS/fallback implementations.
- `Position`, `Range`, and `LineRange` use 1-based UTF-16 line/column coordinates.
  `OffsetRange` is a 0-based half-open UTF-16 span. `TextSnapshot` in
  `viewer/common/model` owns conversion between those spaces. Unlike Monaco,
  `OffsetRange` normalizes inverted constructor input instead of throwing.
  `LineRange::join_many` unions arrays of sorted ranges into a copied, normalized
  result without mutating caller arrays.
- `Disposable` is idempotent. `Emitter` delivers listeners in registration order
  from a snapshot. `MicrotaskEmitter` merges queued events; its default scheduler
  flushes inline, so browser hosts must inject a real microtask scheduler when that
  timing matters.
- `run_async_tasks_sequentially` is the host-neutral default for a closed task
  set. Browser owners may inject a concurrent runner at the call boundary
  without coupling shared packages to a particular coroutine runtime.
- String, character-classification, RTL/full-width, and line-splitting helpers are
  shared here so higher layers do not duplicate coordinate-sensitive logic.

## Monaco map

The pinned `vscode/` counterparts are the named files under
`src/vs/base/common/`, plus `src/vs/editor/common/core/position.ts`, `range.ts`,
`characterClassifier.ts`, and `core/ranges/{lineRange,offsetRange}.ts`.

This package must not import product, viewer, DOM, server, workspace, or host-effect
packages. Use `Uri`, not a workspace-owned alias or an unparsed string, for resource
identity. The exhaustive public surface is `pkg.generated.mbti`; focused coverage is
`moon test --target js base/common`.
