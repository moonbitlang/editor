# viewer/common/config

DOM-free editor layout values and canonical font identities.

## Font contract

- `BareFontInfo` is the eight-axis measurement/cache identity: pixel ratio,
  family, weight, size, feature settings, variation settings, integer line
  height, and letter spacing. `get_id` joins those axes in that order.
- `BareFontInfo::create` follows Monaco's line-height normalization: `0` uses
  the platform golden ratio, nonzero values below `8` are em multipliers, the
  result is rounded and floored at `8`. The readonly viewer has no editor-zoom
  option, so Monaco's zoom multiplier is fixed at `1`.
- Variation setting `translate` preserves `normal`/`bold` as ordinary weight
  with variation `normal`. Other weights use JavaScript `parseInt(_, 10)`
  decimal-prefix semantics, emit `'wght' N`, and normalize the retained weight
  to `normal`.
- MoonBit has no class inheritance, so `FontInfo` is the flattened
  `BareFontInfo` fields plus the measured trust, monospace, half/full-width,
  arrow, space, middot, word-separator-middot, and maximum-digit facts.
  `FontInfo::equals` is Monaco's render/configuration identity: it deliberately
  ignores `pixel_ratio`, `is_trusted`, and `is_monospace`. Structural `==`
  still compares every MoonBit field; callers needing Monaco identity must use
  `equals`.
- `FontInfo::estimated` and `FontInfo::default` are untrusted headless values
  used before DOM measurement. Font-info versioning, serialization, and restore
  are absent because the viewer has no persistence channel.

`EDITOR_FONT_DEFAULTS` selects the exact Menlo stack and 12px size on macOS,
the Consolas stack and 14px size on Windows, and the Droid Sans Mono stack and
14px size elsewhere. Default weight is `normal`; raw line height and letter
spacing are zero.

This package is multi-target and depends only on `base/common`. See
`pkg.generated.mbti`; run `moon test --target js viewer/common/config` and
`moon test --target native viewer/common/config`.
