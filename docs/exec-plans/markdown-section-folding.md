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

**Landed: the table of contents.** `markdown_table_of_contents` derives an
outline from the same section tree, with structural depth normalized so a level
jump or a document starting at `###` still indents from depth 1. Each row carries
the heading's reveal offset, its `section_index`, and the same `is_foldable`
answer the fold control will use, so a TOC row and a fold control cannot
disagree. DOM-free and tested; no TOC *UI* exists yet.

**Not started -- this is all of the user-visible work:** the root Viewer fold
state, the toggle affordance and its accessibility pair, the TOC sidebar or
overlay that renders these rows, scroll anchoring, CSS, and the component
scenario. Nothing in the product calls any of the functions above, so a reader
currently sees no fold control and no outline.

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

## Review outcome

Two `codex` reviews shaped this. The second was given the product context that
matters most: **this surface exists to make agent-written code interpretable to
a human reader. Humans read; agents write.** That reframed three decisions.

The governing principle, which supersedes D2 and D4:

> **P1. Silently hiding agent-written content the reader never collapsed is
> worse than losing a collapse.** Fold state is a reading convenience, not a
> durable user document. When reconciliation is uncertain, expand.

### Fixed

- Nested headings no longer bound sections (only a heading that rendered a root
  element does), so a blockquote or list heading cannot strand its container's
  following siblings.
- `is_foldable` is defined by the hideable run, not the body anchor count.
- `MarkdownBlockAnchor::heading_text` retains the **parsed inline plaintext**
  from the same pass. Heading identity is therefore markup-independent
  (`# *Title*` == `# Title` == `` # `Title` ``), a multi-line setext heading
  keeps all its words, and a literal trailing `#` stays content. The
  source-string cleaner survives only as a fallback for a projection built
  before that field existed.
- Both `pkg.generated.mbti` regenerated.

### Revised decisions

- **D2 is replaced.** Do *not* treat the heading key as durable identity across
  a source change. Reconcile instead:
  - **theme** reprojection preserves fold state exactly (the source is
    unchanged);
  - **agent source update** preserves a reader's override only for a section
    that matches *uniquely* on (inline plaintext + heading-ancestor path) **and**
    whose body fingerprint is unchanged. Changed, new, or ambiguous sections
    expand. Two identical sibling headings with different bodies still match by
    fingerprint; identical heading *and* body is ambiguous, so neither inherits.
  - **model swap** still resets (D3 stands).
  Occurrence ordinals remain useful *within* one projection and must not be used
  as cross-projection identity.
- **The state is tri-state, not a `Set[String]`:**
  `NoOverride | ExplicitExpanded | ExplicitCollapsed`. With a `Set`, a reader who
  expands an auto-collapsed section is indistinguishable from a reader with no
  opinion, and the next unrelated agent edit re-collapses it.
- **D4 (fully expanded) is retained for now but is probably not the right
  product default** — see the open question below.

### D4 replaced: the approved auto-fold policy

**Approved by the owner.** D4 ("everything expanded") is superseded by
`markdown_default_collapsed_sections`, which is implemented and tested:

- structural depths 1 and 2 always stay expanded, so the document's shape is
  visible with no interaction;
- at depth 3 or deeper, a foldable section starts collapsed when its hideable
  run has >= 6 rendered root elements **or** its body spans >= 12 source lines;
- a non-foldable section is never listed, so no control is offered for something
  that would hide nothing;
- structural depth, not literal ATX level -- a `####` heading at document root is
  depth 1 and is not collapsed as though it were deeply nested.

All three thresholds are optional parameters (`min_depth`,
`min_rendered_elements`, `min_body_lines`) so they can be tuned without touching
the policy.

Two parts of the policy remain for the wiring step, because they need state the
pure function does not have:

- keep the entire ancestor chain of an explicit navigation/reveal anchor open;
- a reader's manual expand/collapse always overrides the policy, which is why
  the state is tri-state rather than a set.

Do **not** use the ordinary editor cursor as an intent signal: in this readonly
surface it is usually just the model default `(1,1)`, not evidence of what the
reader is looking at.

### The ordering rule for hover invalidation (supersedes K3)

`layout_changed` is the right primitive; the rule is *when* to call it.

```text
Standalone collapse/expand:
  set_hidden_root_elements(final union)
  -> hover_bridge.layout_changed()

Source/theme reprojection:
  before_projection_replaced()
  -> replace the article
  -> reconcile and apply the final hidden union
  -> after_projection_replaced()
```

Do **not** call `layout_changed` while reapplying folds inside the replacement
bracket: `before_projection_replaced` has already invalidated the request, and
`after_projection_replaced` must refresh diagnostics only once final visibility
is installed. Calling it before `set_hidden_root_elements` measures stale
geometry.

No new field is needed in `MarkdownDocumentHoverRequestStamp`. The existing
checks already compose: `invalidate_pointer_request` rotates
`request_generation`, cancels timers and token ownership, hides the widget, and
clears overlays; `stamp_is_current` additionally checks model content/version,
attachment, projection generation, source-model version, block and pointer
identity, and cancellation; `accept_parts` re-checks freshness immediately
before `widget.show`.

### Still open

- **K4.** `set_hidden_root_elements` replaces and clears the whole `style` and
  `aria-hidden` attributes. Safe for current renderer output, wrong before the
  API gains a caller — use a dedicated class or data attribute instead.

## Gates

1. `moon check --target all` and `moon fmt --check` clean; `moon test` green on
   js and native.
2. `pkg.generated.mbti` reviewed for `internal/viewer/markdown` — adding a field
   to the `pub(all)` `MarkdownBlockAnchor` is a public API change.
3. A component scenario under `tests/browser/` proving, through the public
   Viewer surface, and covering **both** interleavings of the ordering rule
   above — (a) pending hover -> standalone collapse -> provider completes, and
   (b) pending hover -> agent `replace_source` -> fold reconciliation ->
   provider completes. In both, the stale result must never reach
   `widget.show`:
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
