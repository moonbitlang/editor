# Style Notes

## Documentation

- Document current behavior, ownership, invariants, and caller obligations; do
  not narrate implementation history or restate signatures.
- Put cross-package rules in `docs/architecture.md`, local contracts/checks in
  package READMEs, and future multi-package work in `docs/exec-plans/`.
- After a plan lands, update current contracts and fold its historical record
  into `docs/exec-plans/HISTORY.md`; Git retains the detailed artifact.
- Exported contracts need prose. Private declarations need it only for a
  non-obvious invariant, algorithm, source mapping, coordinate/host boundary,
  freshness rule, or wire/DOM contract. Bare `///|` is only a separator.

## MoonBit

- Use `fn Type::Type(...) -> Type` for the primary constructor; reserve names
  such as `empty` and `from_array` for alternate construction paths.
- Constructors may validate, normalize, or derive hidden fields.
- Use a bare `struct` for an opaque type that public functions expose, and a
  `priv struct` when the type itself is package-private. Reserve `pub struct`
  for contracts whose field visibility is intentionally public instead of
  spelling an opaque representation as a public struct with every field
  marked `priv`.
- An opaque public type may retain `derive(Debug)`, but its promoted `to_repr`
  convenience method belongs in the package's `extends.mbt` as a deprecated,
  documentation-hidden extension. Callers should use `Debug` through the trait
  or `Repr(value)` instead of treating `Type::to_repr` as ordinary API.

## Tests

- Prefer snapshots when output shape matters.
- Use `inspect` for stable `Show`, `debug_inspect` for structural `Debug`, and
  `@json.json_inspect` for JSON-shaped values.
