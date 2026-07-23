///| Faithful 1:1 port of vscode's encoded token metadata helpers.
///
/// Source: `src/vs/editor/common/encodedTokenAttributes.ts` (pinned `vscode/`
/// submodule). Ports the `MetadataConsts` bit layout, the `FontStyle`/`ColorId`/
/// `StandardTokenType` enums, and the `TokenMetadata` decoders. The 32-bit
/// metadata word is held as `UInt` (Monaco packs it into a `Uint32Array`); the
/// background field occupies the top byte, so an `Int` cannot hold a fully
/// populated word.
///
/// Placement: Monaco keeps this file at the `editor/common/` root. The
/// `viewer/common` root package imports `view_model`, which sits above this
/// code in the import graph, so a root placement would cycle; it lives one
/// directory down with its primary consumer (`lineTokens.ts` is in
/// `common/tokens/` in Monaco too).

///|
/// `FontStyle` — values are 2^x so a bit mask can be used.
pub const FONT_STYLE_NOT_SET : Int = -1

///|
pub const FONT_STYLE_NONE : Int = 0

///|
pub const FONT_STYLE_ITALIC : Int = 1

///|
pub const FONT_STYLE_BOLD : Int = 2

///|
pub const FONT_STYLE_UNDERLINE : Int = 4

///|
pub const FONT_STYLE_STRIKETHROUGH : Int = 8

///|
/// `ColorId` — open ended at runtime.
pub const COLOR_ID_NONE : Int = 0

///|
pub const COLOR_ID_DEFAULT_FOREGROUND : Int = 1

///|
pub const COLOR_ID_DEFAULT_BACKGROUND : Int = 2

///|
/// `StandardTokenType`.
pub const STANDARD_TOKEN_TYPE_OTHER : Int = 0

///|
pub const STANDARD_TOKEN_TYPE_COMMENT : Int = 1

///|
pub const STANDARD_TOKEN_TYPE_STRING : Int = 2

///|
pub const STANDARD_TOKEN_TYPE_REGEX : Int = 3

// The binary metadata format (see encodedTokenAttributes.ts):
//   bbbb bbbb ffff ffff fFFF FBTT LLLL LLLL
//   L = LanguageId (8), T = StandardTokenType (2), B = Balanced bracket (1),
//   F = FontStyle (4), f = foreground (9), b = background (8)

///|
const METADATA_LANGUAGEID_MASK : UInt = 0x0000_00FFU

///|
const METADATA_TOKEN_TYPE_MASK : UInt = 0x0000_0300U

///|
const METADATA_BALANCED_BRACKETS_MASK : UInt = 0x0000_0400U

///|
const METADATA_FONT_STYLE_MASK : UInt = 0x0000_7800U

///|
const METADATA_FOREGROUND_MASK : UInt = 0x00FF_8000U

///|
const METADATA_BACKGROUND_MASK : UInt = 0xFF00_0000U

// The shift offsets are exposed (Monaco's public `MetadataConsts.*_OFFSET`) so
// callers can build metadata words as `field << OFFSET`, as the suite does.

///|
pub const METADATA_LANGUAGEID_OFFSET : Int = 0

///|
pub const METADATA_TOKEN_TYPE_OFFSET : Int = 8

///|
pub const METADATA_BALANCED_BRACKETS_OFFSET : Int = 10

///|
pub const METADATA_FONT_STYLE_OFFSET : Int = 11

///|
pub const METADATA_FOREGROUND_OFFSET : Int = 15

///|
pub const METADATA_BACKGROUND_OFFSET : Int = 24

///|
/// Namespace holder mirroring Monaco's static `TokenMetadata` class. Uninhabited
/// — it only carries the static metadata decoders below.
enum TokenMetadata {}

///|
pub fn TokenMetadata::get_language_id(metadata : UInt) -> Int {
  ((metadata & METADATA_LANGUAGEID_MASK) >> METADATA_LANGUAGEID_OFFSET).reinterpret_as_int()
}

///|
pub fn TokenMetadata::get_token_type(metadata : UInt) -> Int {
  ((metadata & METADATA_TOKEN_TYPE_MASK) >> METADATA_TOKEN_TYPE_OFFSET).reinterpret_as_int()
}

///|
pub fn TokenMetadata::contains_balanced_brackets(metadata : UInt) -> Bool {
  (metadata & METADATA_BALANCED_BRACKETS_MASK) != 0
}

///|
pub fn TokenMetadata::get_font_style(metadata : UInt) -> Int {
  ((metadata & METADATA_FONT_STYLE_MASK) >> METADATA_FONT_STYLE_OFFSET).reinterpret_as_int()
}

///|
pub fn TokenMetadata::get_foreground(metadata : UInt) -> Int {
  ((metadata & METADATA_FOREGROUND_MASK) >> METADATA_FOREGROUND_OFFSET).reinterpret_as_int()
}

///|
pub fn TokenMetadata::get_background(metadata : UInt) -> Int {
  ((metadata & METADATA_BACKGROUND_MASK) >> METADATA_BACKGROUND_OFFSET).reinterpret_as_int()
}

///|
pub fn TokenMetadata::get_class_name_from_metadata(metadata : UInt) -> String {
  let foreground = TokenMetadata::get_foreground(metadata)
  let mut class_name = "mtk" + foreground.to_string()
  let font_style = TokenMetadata::get_font_style(metadata)
  if (font_style & FONT_STYLE_ITALIC) != 0 {
    class_name = class_name + " mtki"
  }
  if (font_style & FONT_STYLE_BOLD) != 0 {
    class_name = class_name + " mtkb"
  }
  if (font_style & FONT_STYLE_UNDERLINE) != 0 {
    class_name = class_name + " mtku"
  }
  if (font_style & FONT_STYLE_STRIKETHROUGH) != 0 {
    class_name = class_name + " mtks"
  }
  class_name
}

///|
pub fn TokenMetadata::get_inline_style_from_metadata(
  metadata : UInt,
  color_map : Array[String],
) -> String {
  let foreground = TokenMetadata::get_foreground(metadata)
  let font_style = TokenMetadata::get_font_style(metadata)
  let mut result = "color: " + color_map[foreground] + ";"
  if (font_style & FONT_STYLE_ITALIC) != 0 {
    result = result + "font-style: italic;"
  }
  if (font_style & FONT_STYLE_BOLD) != 0 {
    result = result + "font-weight: bold;"
  }
  let mut text_decoration = ""
  if (font_style & FONT_STYLE_UNDERLINE) != 0 {
    text_decoration = text_decoration + " underline"
  }
  if (font_style & FONT_STYLE_STRIKETHROUGH) != 0 {
    text_decoration = text_decoration + " line-through"
  }
  if text_decoration != "" {
    result = result + "text-decoration:" + text_decoration + ";"
  }
  result
}

///|
/// Presentation extracted from a metadata word.
pub struct TokenPresentation {
  foreground : Int
  italic : Bool
  bold : Bool
  underline : Bool
  strikethrough : Bool
}

///|
pub fn TokenMetadata::get_presentation_from_metadata(
  metadata : UInt,
) -> TokenPresentation {
  let foreground = TokenMetadata::get_foreground(metadata)
  let font_style = TokenMetadata::get_font_style(metadata)
  {
    foreground,
    italic: (font_style & FONT_STYLE_ITALIC) != 0,
    bold: (font_style & FONT_STYLE_BOLD) != 0,
    underline: (font_style & FONT_STYLE_UNDERLINE) != 0,
    strikethrough: (font_style & FONT_STYLE_STRIKETHROUGH) != 0,
  }
}
