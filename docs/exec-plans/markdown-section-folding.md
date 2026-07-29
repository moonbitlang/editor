# Markdown section folding

Collapse a heading's subtree in the readonly Markdown document presentation,
without disturbing the `.mbt.md` semantic-fence contract.

## Why this is not "add a folding range provider"

Folding today cannot reach Markdown, for two independent reasons:

- `Viewer::folding_on_model_changed` (`viewer/folding_host.mbt`) begins with
  `guard self.is_code_presentation() else { return }`, so no folding model,
  decoration provider, or hidden-range model is ever built for a Markdown model.
- Folding terminates in `ViewModel::set_hidden_areas`, which suppresses *view
  lines*. `internal/viewer/browser/markdown_document` renders no view lines; it
  owns a replaceable article of root HTML elements.

An exact lowercase `.md`/`.mbt.md` URI-path suffix or the exact `markdown`
language id always selects the Markdown presentation, so there is no reachable
"Markdown model in a Code view" case to fall back on. This is a new mechanism
over the rendered article, not a new provider behind the existing one.

Routing this through hidden areas is **rejected**: it would force the Markdown
root to project view lines and invert the presentation split.

## The invariant that makes semantic fences keep working

`markdown_semantic_pointer_hit`
(`internal/viewer/contrib/hover/browser/markdown_document_hover.mbt`) resolves a
pointer without consulting layout for the mapping:

1. `caretPositionFromPoint` yields a text node plus offset;
2. it walks the retained `MarkdownDocumentView::semantic_code_lines()`, pairing
   each retained line element with its `MarkdownCodeLine`;
3. it requires the caret node to be a DOM descendant of that line element;
4. `markdown_text_units_before_node` counts text units — a DOM-tree walk, not a
   geometry query;
5. `MarkdownCodeLine::source_offset_at_displayed_boundary` maps that boundary to
   a source offset.

`MarkdownDocumentHoverRequestStamp` covers request, model identity, caller and
internal model version, content, URI, revision, attach generation,
`projection_generation`, source model version, and `block_index`. It contains
**no DOM visibility or geometry identity**.

Therefore:

> **I1. Collapse is a visibility operation over retained nodes. It sets
> `display:none` on already-rendered root elements. It never re-renders, never
> rebuilds the projection, and never increments `projection_generation`.**

Under I1, source offsets stay absolute and per-line boundary maps stay valid, so
a fence in a visible section resolves correctly no matter what else is
collapsed, and a fence revealed by expanding resolves immediately with no
recomputation.

> **I2. `visibility:hidden` and `height:0; overflow:hidden` are forbidden as the
> collapse mechanism.** Both leave hidden content hit-testable with live client
> rects, which would let `markdown_pointer_inside_line_y` match invisible text
> and produce a hover on content the reader cannot see. `display:none` removes
> the subtree from hit testing, so `caretPositionFromPoint` cannot return a node
> inside it and the descendant check in step 3 fails closed.

## Section model

A heading anchor at level `L` opens a section whose body runs to the anchor
before the next anchor with `heading_level <= L`, or to the end of the document.
Nesting follows from a level stack. A heading immediately followed by a
same-or-higher-level heading has an empty body and is **not** foldable.

The heading level must be retained during the existing single parse. Deriving
sections from a second scan would create a third coordinate space beside the
HTML and the source projection, which the package explicitly forbids ("one parse
with `layout=true` and `locs=true` supplies both safe HTML and a
`MarkdownDocumentProjection`, so the rendered document and its source facts
cannot describe different parses").

## Ownership

| Layer | Owns |
|---|---|
| `internal/viewer/markdown` | `heading_level` on `MarkdownBlockAnchor`; pure `markdown_sections()`. DOM-free, js+native, covered by `mbt check` blocks in its `README.mbt.md` and focused tests. |
| `internal/viewer/browser/markdown_document` | Hiding a contiguous run of root elements by `rendered_element_index`; the toggle DOM and its listeners; per-target disposal. Owns no fold *policy*. |
| root `viewer` | The fold state, its stable keys, reconciliation across reprojection, and disposal ordering — symmetric with the Markdown-comment contribution. |

## Decisions taken

Recorded so they can be overruled deliberately rather than rediscovered:

- **D1. Collapse mechanism** is `display:none` on retained root elements (I1/I2).
- **D2. Fold-state key** is `(heading level, normalized heading text,
  occurrence ordinal among identical keys)`. Element identity is unusable
  because reprojection replaces the article wholesale.
- **D3. Fold state is model-scoped.** A model swap resets it, matching the
  Markdown-comment entry's model-scoped stable-key map.
- **D4. Default is fully expanded.** No auto-fold heuristic.
- **D5. Empty-body headings get no control**, mirroring how
  separator-only or one-line API blocks remain expanded without a toggle.

## Deferred

- **Diagnostic indicator on a collapsed heading.** VS Code surfaces a marker on
  a folded region. Deferred: it needs a marker-to-section projection, and the
  fold header is not a decoration host today.
- **Persisting fold state across a model swap on the same URI** (see D3).
- **Keyboard-driven fold/unfold-all commands.** The central command and
  keybinding tables are Code-path today.

## Status

**Landed: the model half.** `internal/viewer/markdown` retains
`MarkdownBlockAnchor::heading_level` from the existing parse and derives the
section tree (`markdown_sections`), the hideable run
(`MarkdownSection::body_rendered_element_indexes`), and the reconciliation keys
(`markdown_section_keys`). All of it is DOM-free, runs on js and native, and is
covered by focused tests plus `mbt check` blocks in the package README.

**Landed but unproven: the view-level collapse operation.**
`MarkdownDocumentView::set_hidden_root_elements` / `hidden_root_elements` apply
and read back `display:none` over retained root elements. It compiles and
carries no caller yet, so **no browser test exercises it**. It must not be
considered done until gate 3 below passes.

**Not started:** the root Viewer fold state, the toggle affordance and its
accessibility pair, scroll anchoring, and the component scenario.

### Next executor: start here

1. Add the fold state to `MarkdownBrowserData` (`viewer/model_data.mbt`) as a
   `Set[String]` of collapsed keys from `markdown_section_keys`.
2. Re-apply it at the two reprojection points that already exist —
   `MarkdownBrowserData::replace_source` and `::apply_theme`, both of which
   already bracket their work with
   `hover_bridge.before_projection_replaced()` / `after_projection_replaced()`.
   The fold re-application belongs inside that bracket, after the view has
   re-rendered.
3. Expose a public toggle on `Viewer` keyed by heading source offset
   (`markdown_section_at_source_offset` resolves it), plus a read-back for
   tests.
4. Only then add the toggle DOM and the accessible button, following the
   Markdown-comment entry's chevron/in-content-button pair.

## Gates

1. `moon check --target all` and `moon fmt --check` clean; `moon test` green on
   js and native.
2. `pkg.generated.mbti` reviewed for `internal/viewer/markdown` — adding a field
   to the `pub(all)` `MarkdownBlockAnchor` is a public API change.
3. A component scenario under `tests/browser/` proving, through the public
   Viewer surface:
   - collapsing a section hides exactly its body run;
   - a fence in a *sibling visible* section still resolves to the correct source
     offset while another section is collapsed;
   - expanding, then hovering inside the previously collapsed fence, resolves —
     with `MarkdownDocumentView::projection_generation()` **unchanged** across
     the whole sequence, which is the executable form of I1;
   - disposal retains no toggle, listener, or observer.

## Coordination

`origin/agent/fold-api-docs` (`e8e8c33`, not yet on `main`) makes API
documentation ViewZones foldable in **Code** presentation. Different feature,
adjacent machinery: its toggle lifetime, stable-key map, and the
`request_measure` -> `Viewer::apply_markdown_comment_height` invalidation chain
are the patterns to follow. Neither feature may introduce a second fold-state
owner.
