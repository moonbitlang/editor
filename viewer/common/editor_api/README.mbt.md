# Editor API value contracts

This multi-target package owns DOM-free values shared by the public Viewer
facade and lower editor packages. It is dependency-bottom: imports are limited
to `base/common` and `viewer/common/core`.

It contains no behavior at all — only the vocabulary. Its reason to exist is
negative: without it, the root facade and the internal cursor/view-model/browser
packages would each define their own `CursorChangeReason` or `ScrollEvent`, and
every boundary crossing would need a translation function that can silently drop
a variant.

```d2
direction: right

api: viewer/common/editor_api {
  grid-columns: 1
  ev: cursor / model / scroll events
  en: option enums
}
consumers: consumers {
  grid-columns: 2
  root: root viewer facade
  cursor: viewer/common/cursor
  vm: viewer/common/view_model
  vl: viewer/common/view_layout
  br: internal/viewer/browser/*
  fold: contrib/folding
}

consumers -> api: "import the one declaration" {style.stroke-dash: 3}
api -> consumers: "no dependency back" {style.stroke: red}
```

## Events

`CursorChangeReason`, cursor/model/scroll events, and
`ScrolledVisiblePosition` have one declaration here. Internal cursor,
view-model, browser, and root packages consume these types directly; they do
not define facade copies or translate variants.

`CursorChangeReason` explains *why* a cursor moved, which is what lets a
listener distinguish a user gesture from a programmatic reset. `ContentFlush` is
the one a host most often cares about: it means the model's whole text was
replaced underneath the cursor.

```mbt check
///|
test "every cursor change carries a reason" {
  let reasons : Array[@editor_api.CursorChangeReason] = [
    NotSet,
    ContentFlush,
    RecoverFromMarkers,
    Explicit,
    Paste,
    Undo,
    Redo,
  ]
  debug_inspect(
    reasons,
    content=(
      #|[
      #|  NotSet,
      #|  ContentFlush,
      #|  RecoverFromMarkers,
      #|  Explicit,
      #|  Paste,
      #|  Undo,
      #|  Redo,
      #|]
    ),
  )
}
```

A selection-changed event carries both the new and the old selections plus both
model version ids, so a listener can tell a genuine selection change from one
induced by a model edit without keeping its own shadow copy.

```mbt check
///|
test "a selection event pairs new and old state with model versions" {
  let event : @editor_api.CursorSelectionChangedEvent = {
    selection: Selection(Position(2, 1), Position(2, 8)),
    secondary_selections: [],
    model_version_id: 7,
    old_selections: Some([Selection(Position(1, 1), Position(1, 1))]),
    old_model_version_id: 6,
    source: "mouse",
    reason: Explicit,
  }
  debug_inspect(
    (
      event.reason,
      event.source,
      event.model_version_id,
      event.old_model_version_id,
      event.selection.is_empty(),
      event.old_selections.map(previous => previous.length()),
    ),
    content=(
      #|(Explicit, "mouse", 7, 6, false, Some(1))
    ),
  )
}
```

`ScrollEvent` reports the new values *and* a changed flag per axis, so a
listener that only cares about vertical movement does not have to diff the
value itself.

```mbt check
///|
test "scroll events flag which axes actually moved" {
  let event : @editor_api.ScrollEvent = {
    scroll_top: 120.0,
    scroll_left: 0.0,
    scroll_width: 800.0,
    scroll_height: 4000.0,
    scroll_top_changed: true,
    scroll_left_changed: false,
    scroll_width_changed: false,
    scroll_height_changed: false,
  }
  debug_inspect(
    (
      event.scroll_top_changed,
      event.scroll_left_changed,
      // a vertical-only listener can early-out on this
      event.scroll_top_changed || event.scroll_height_changed,
    ),
    content=(
      #|(true, false, true)
    ),
  )
}
```

`ModelChangedEvent` carries both URIs as options, because either side may be
absent: attaching the first model has no old URI, and detaching has no new one.

```mbt check
///|
test "a model change has an absent side at attach and at detach" {
  let uri = @base_common.Uri::parse("file:///src/main.mbt")
  let attach : @editor_api.ModelChangedEvent = {
    old_model_url: None,
    new_model_url: Some(uri),
  }
  let detach : @editor_api.ModelChangedEvent = {
    old_model_url: Some(uri),
    new_model_url: None,
  }
  debug_inspect(
    (
      (attach.old_model_url is None, attach.new_model_url is None),
      (detach.old_model_url is None, detach.new_model_url is None),
    ),
    content=(
      #|((true, false), (false, true))
    ),
  )
}
```

`ScrolledVisiblePosition` is the answer to "where is this model position on
screen right now" — a top/left pair plus the line height, already in scrolled
coordinates.

```mbt check
///|
test "a scrolled visible position is a box in viewport coordinates" {
  let at : @editor_api.ScrolledVisiblePosition = {
    top: 42.0,
    left: 96.0,
    height: 18.0,
  }
  debug_inspect(
    (at.top, at.left, at.height),
    content=(
      #|(42, 96, 18)
    ),
  )
}
```

## Option enums

Canonical editor option enums also live here: `WrappingIndent`,
`RenderWhitespace`, `RenderLineHighlight`, `RenderValidationDecorations`, and
`ShowFoldingControls`. Rendering, view-model, and folding packages retain the
behavior that interprets those values; they import the enum contract instead
of defining a package-local copy.

```mbt check
///|
test "the five option enums and their variants" {
  let wrapping : Array[@editor_api.WrappingIndent] = [
    None,
    Same,
    Indent,
    DeepIndent,
  ]
  let whitespace : Array[@editor_api.RenderWhitespace] = [
    None,
    Boundary,
    Selection,
    Trailing,
    All,
  ]
  let line_highlight : Array[@editor_api.RenderLineHighlight] = [
    None,
    Gutter,
    Line,
    All,
  ]
  let validation : Array[@editor_api.RenderValidationDecorations] = [
    Editable,
    On,
    Off,
  ]
  let folding : Array[@editor_api.ShowFoldingControls] = [
    Always,
    Never,
    Mouseover,
  ]
  debug_inspect(
    (wrapping, whitespace, line_highlight, validation, folding),
    content=(
      #|(
      #|  [None, Same, Indent, DeepIndent],
      #|  [None, Boundary, Selection, Trailing, All],
      #|  [None, Gutter, Line, All],
      #|  [Editable, On, Off],
      #|  [Always, Never, Mouseover],
      #|)
    ),
  )
}
```

Each is a closed enum, so adding a rendering mode is a compile error at every
site that interprets it rather than a silent fall-through to a default.

## Boundaries and checks

This package must not import model, view-model, layout, contribution, DOM, or
host packages — everything above may import it. The complete API is
`pkg.generated.mbti`.

```sh
moon test --target js viewer/common/editor_api
moon test --target native viewer/common/editor_api
```
