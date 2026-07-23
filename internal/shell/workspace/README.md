# internal/shell/workspace

Backend-neutral readonly source, document, filesystem, and tree contracts for
host packages.

## Contracts

- `SourcePath` normalizes root-relative paths and rejects absolute paths,
  traversal, Windows drive paths, and NUL bytes. `infer_language_id` maps common
  source extensions.
- `FileSystemProvider` exposes scheme-owned text reads and watches;
  `read_document`/`watch_file` adapt it to structured results and snapshots.
- `DocumentProvider` exposes document-level `read`, `watch`, and `close`.
  Watches may invalidate, update, delete, or fail a URI.
- `DocumentSnapshot` is immutable provider/transport data: URI, metadata,
  revision, text, UTF-16 offsets, LF/CRLF/lone-CR line splitting, and 1-based
  `Position` conversion.
- `WorkspaceTreeProvider` exposes a root URI and pull-based one-level `resolve`;
  unresolved directory stats carry `children: None`.

Exact public types, error codes, helpers, and trait signatures are in
`pkg.generated.mbti`.

## Boundary and validation

This package may depend only on `base/common` and JSON support. It owns no DOM,
browser, native, server-routing, or process effects. `DocumentSnapshot` is host
data: adapters create `viewer/common/model.TextModel`; viewer core must not
import this package.

Run `moon test internal/shell/workspace --target js` and `just check`.
