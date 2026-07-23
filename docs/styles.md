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

## Tests

- Prefer snapshots when output shape matters.
- Use `inspect` for stable `Show`, `debug_inspect` for structural `Debug`, and
  `@json.json_inspect` for JSON-shaped values.
