# shell/workspace

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

## SourcePath

`SourcePath` normalizes root-relative paths and rejects absolute paths,
traversal, Windows drive paths, and NUL bytes. It is the package's containment
boundary: a value of this type cannot name anything outside the workspace root.

```mbt check
///|
fn source_path(raw : String) -> String {
  match @workspace.SourcePath::normalize_root_relative_path(raw) {
    ParsedSourcePath(path) => "ok:" + path.to_string()
    SourcePathError(_) => "rejected"
  }
}

///|
test "traversal, absolute, and drive paths are rejected" {
  debug_inspect(
    [
      "src/main.mbt", "./src/main.mbt", "src//main.mbt", "../escape.mbt", "/etc/passwd",
      "C:\\Windows\\system.ini", "src/\u{0}evil.mbt",
    ].map(source_path),
    content=(
      #|[
      #|  "ok:src/main.mbt",
      #|  "ok:src/main.mbt",
      #|  "ok:src/main.mbt",
      #|  "rejected",
      #|  "rejected",
      #|  "rejected",
      #|  "rejected",
      #|]
    ),
  )
}
```

`infer_language_id` maps common source extensions. Two results are worth
knowing before you rely on it:

- an unrecognized name falls back to `moonbit` rather than to `plaintext`, so a
  `moonbit` language id is not evidence that the host recognized the file;
- `notes.mbt.md` infers `moonbit`, not `markdown`, because the `.mbt` extension
  matches first.

The second does **not** break Markdown presentation: the Viewer selects the
Markdown root from the URI's lowercase `.md` suffix (including `.mbt.md`), not
from this language id. The two mechanisms are independent on purpose.

```mbt check
///|
test "language ids are inferred from the extension" {
  debug_inspect(
    ["main.mbt", "data.json", "app.js", "README.md", "notes.mbt.md", "LICENSE"].map(
      @workspace.infer_language_id,
    ),
    content=(
      #|["moonbit", "json", "javascript", "markdown", "moonbit", "moonbit"]
    ),
  )
}
```

## DocumentSnapshot

`DocumentSnapshot` is immutable provider/transport data: URI, metadata,
revision, text, UTF-16 offsets, LF/CRLF/lone-CR line splitting, and 1-based
`Position` conversion.

It is emphatically **not** the editor model. It is what the transport carries;
an adapter turns it into a `viewer/common/model.TextModel`. Notably, it splits
CRLF and lone CR for line addressing but does **not** rewrite the stored text
the way the editor model does, so offsets here index the bytes the host sent.

```mbt check
///|
fn snapshot(text : String) -> @workspace.DocumentSnapshot raise {
  DocumentSnapshot(
    @base_common.Uri::parse("file:///workspace/src/main.mbt"),
    "main.mbt",
    "moonbit",
    "rev-1",
    text,
  )
}

///|
test "line addressing handles all three terminators" {
  let doc = snapshot("a\r\nbb\rccc\ndddd")
  debug_inspect(
    (
      doc.line_count(),
      [
        for index in 0..<doc.line_count() => doc.line_text(index)
      ],
      doc.length(),
    ),
    content=(
      #|(4, ["a", "bb", "ccc", "dddd"], 14)
    ),
  )
}
```

Offsets and 1-based positions convert in both directions, which is the
conversion the remote protocol relies on at the wire boundary.

```mbt check
///|
test "offsets and 1-based positions convert both ways" {
  let doc = snapshot("let x = 1\nlet y = 2\n")
  let position = doc.position_at_offset(12)
  debug_inspect(
    (
      position,
      doc.offset_at_position(position),
      doc.line_at_offset(12),
      doc.slice(OffsetRange(10, 13)),
    ),
    content=(
      #|({ line_number: 2, column: 3 }, 12, 1, "let")
    ),
  )
}
```

`revision_from_text` derives the revision a watch compares against, so two
identical reads produce the same revision and a changed read does not.

```mbt check
///|
test "the revision is derived from the text" {
  let first = @workspace.revision_from_text("let x = 1\n")
  let same = @workspace.revision_from_text("let x = 1\n")
  let different = @workspace.revision_from_text("let x = 2\n")
  debug_inspect(
    (first == same, first == different),
    content=(
      #|(true, false)
    ),
  )
}
```

## Boundary and validation

This package may depend only on `base/common` and JSON support. It owns no DOM,
browser, native, server-routing, or process effects. `DocumentSnapshot` is host
data: adapters create `viewer/common/model.TextModel`; viewer core must not
import this package.

Run `moon test shell/workspace --target js` and `just check`.
