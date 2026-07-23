// Ported from `vscode/src/vs/editor/browser/config/fontMeasurements.ts` at
// checked-in source.
// Single-window: Monaco's per-window cache map (keyed by `getWindowId`)
// collapses to one cache. The `serializeFontInfo`/`restoreFontInfo`
// persistence channel is not ported.

///|
pub struct FontMeasurementsImpl {
  priv cache_keys : Array[String]
  priv cache : Map[String, @common_config.FontInfo]
  priv mut evict_untrusted_readings_pending : Bool
  priv did_change : @base_common.Emitter[Unit]
  priv read_widths : (@common_config.BareFontInfo, Array[CharWidthRequest]) -> Unit
  priv read_pixel_ratio : () -> Double
  priv schedule_timeout : (() -> Unit, Int) -> Unit
}

///|
/// Monaco's `FontMeasurements` singleton.
let instance : FontMeasurementsImpl = {
  cache_keys: [],
  cache: Map([]),
  evict_untrusted_readings_pending: false,
  did_change: Emitter(),
  read_widths: read_char_widths,
  read_pixel_ratio: @base_browser.device_pixel_ratio,
  schedule_timeout,
}

///|
fn new_font_measurements_for_test(
  read_widths : (@common_config.BareFontInfo, Array[CharWidthRequest]) -> Unit,
  read_pixel_ratio : () -> Double,
  schedule_timeout : (() -> Unit, Int) -> Unit,
) -> FontMeasurementsImpl {
  {
    cache_keys: [],
    cache: Map([]),
    evict_untrusted_readings_pending: false,
    did_change: Emitter(),
    read_widths,
    read_pixel_ratio,
    schedule_timeout,
  }
}

///|
pub fn font_measurements() -> FontMeasurementsImpl {
  instance
}

///|
/// Monaco `FontMeasurements.onDidChange`: fires when cached readings are
/// evicted (an untrusted reading re-measures after 5s, e.g. once a web font
/// finished loading) or explicitly cleared.
pub fn FontMeasurementsImpl::on_did_change(
  self : FontMeasurementsImpl,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.did_change.event(_ => listener())
}

///|
/// Monaco `clearAllFontInfos`.
pub fn FontMeasurementsImpl::clear_all_font_infos(
  self : FontMeasurementsImpl,
) -> Unit {
  self.cache.clear()
  self.cache_keys.clear()
  self.did_change.fire(())
}

///|
fn FontMeasurementsImpl::write_to_cache(
  self : FontMeasurementsImpl,
  id : String,
  value : @common_config.FontInfo,
) -> Unit {
  if !self.cache.contains(id) {
    self.cache_keys.push(id)
  }
  self.cache[id] = value
  if !value.is_trusted && !self.evict_untrusted_readings_pending {
    // Try reading again after some time.
    self.evict_untrusted_readings_pending = true
    (self.schedule_timeout)(
      () => {
        self.evict_untrusted_readings_pending = false
        self.evict_untrusted_readings()
      },
      5000,
    )
  }
}

///|
fn FontMeasurementsImpl::remove_from_cache(
  self : FontMeasurementsImpl,
  id : String,
) -> Unit {
  self.cache.remove(id)
  let retained : Array[String] = []
  for key in self.cache_keys {
    if key != id {
      retained.push(key)
    }
  }
  self.cache_keys.clear()
  self.cache_keys.append(retained)
}

///|
fn FontMeasurementsImpl::cached_values(
  self : FontMeasurementsImpl,
) -> Array[@common_config.FontInfo] {
  let result : Array[@common_config.FontInfo] = []
  for id in self.cache_keys {
    match self.cache.get(id) {
      Some(value) => result.push(value)
      None => ()
    }
  }
  result
}

///|
/// This injected constructor is consumed by the owning white-box conformance
/// suite. Keep it live in non-test checks as well.
let _font_measurements_test_seam_anchor : Unit = ignore(
  new_font_measurements_for_test,
)

///|
fn FontMeasurementsImpl::evict_untrusted_readings(
  self : FontMeasurementsImpl,
) -> Unit {
  let values = self.cached_values()
  let mut something_removed = false
  for font_info in values {
    if !font_info.is_trusted {
      something_removed = true
      self.remove_from_cache(font_info.get_id())
    }
  }
  if something_removed {
    self.did_change.fire(())
  }
}

///|
/// Monaco `readFontInfo`: the cached `FontInfo` for a `BareFontInfo`,
/// measured through `readCharWidths` on a miss. Suspicious readings (Bug
/// 14341: everything measures ~0 while a web font loads) are clamped to a
/// minimum advance and cached untrusted so they re-measure later.
pub fn FontMeasurementsImpl::read_font_info(
  self : FontMeasurementsImpl,
  bare_font_info : @common_config.BareFontInfo,
) -> @common_config.FontInfo {
  let id = bare_font_info.get_id()
  match self.cache.get(id) {
    Some(font_info) => font_info
    None => {
      let mut read_config = self.actual_read_font_info(bare_font_info)
      if read_config.typical_halfwidth_character_width <= 2.0 ||
        read_config.typical_fullwidth_character_width <= 2.0 ||
        read_config.space_width <= 2.0 ||
        read_config.max_digit_width <= 2.0 {
        // Hey, it's Bug 14341 ... we couldn't read.
        read_config = {
          ..read_config,
          typical_halfwidth_character_width: max_double(
            read_config.typical_halfwidth_character_width,
            5.0,
          ),
          typical_fullwidth_character_width: max_double(
            read_config.typical_fullwidth_character_width,
            5.0,
          ),
          space_width: max_double(read_config.space_width, 5.0),
          middot_width: max_double(read_config.middot_width, 5.0),
          wsmiddot_width: max_double(read_config.wsmiddot_width, 5.0),
          max_digit_width: max_double(read_config.max_digit_width, 5.0),
          pixel_ratio: (self.read_pixel_ratio)(),
          is_trusted: false,
        }
      }
      self.write_to_cache(id, read_config)
      read_config
    }
  }
}

///|
fn create_request(
  chr : String,
  request_type : CharWidthRequestType,
  all : Array[CharWidthRequest],
  monospace : Array[CharWidthRequest]?,
) -> CharWidthRequest {
  let result = CharWidthRequest::new(chr, request_type)
  all.push(result)
  match monospace {
    Some(monospace) => monospace.push(result)
    None => ()
  }
  result
}

///|
fn FontMeasurementsImpl::actual_read_font_info(
  self : FontMeasurementsImpl,
  bare_font_info : @common_config.BareFontInfo,
) -> @common_config.FontInfo {
  let all : Array[CharWidthRequest] = []
  let monospace : Array[CharWidthRequest] = []
  let typical_halfwidth_character = create_request(
    "n",
    Regular,
    all,
    Some(monospace),
  )
  // U+FF4D - FULLWIDTH LATIN SMALL LETTER M
  let typical_fullwidth_character = create_request(
    "\u{ff4d}",
    Regular,
    all,
    None,
  )
  let space = create_request(" ", Regular, all, Some(monospace))
  let digits = [
    create_request("0", Regular, all, Some(monospace)),
    create_request("1", Regular, all, Some(monospace)),
    create_request("2", Regular, all, Some(monospace)),
    create_request("3", Regular, all, Some(monospace)),
    create_request("4", Regular, all, Some(monospace)),
    create_request("5", Regular, all, Some(monospace)),
    create_request("6", Regular, all, Some(monospace)),
    create_request("7", Regular, all, Some(monospace)),
    create_request("8", Regular, all, Some(monospace)),
    create_request("9", Regular, all, Some(monospace)),
  ]
  // monospace test: used for whitespace rendering.
  let rightwards_arrow = create_request("→", Regular, all, Some(monospace))
  let halfwidth_rightwards_arrow = create_request("￫", Regular, all, None)
  // U+00B7 - MIDDLE DOT
  let middot = create_request("·", Regular, all, Some(monospace))
  // U+2E31 - WORD SEPARATOR MIDDLE DOT
  let wsmiddot = create_request("\u{2e31}", Regular, all, None)
  // monospace test: some characters.
  let monospace_test_chars = ["|", "/", "-", "_", "i", "l", "m", "%"]
  for chr in monospace_test_chars {
    create_request(chr, Regular, all, Some(monospace)) |> ignore
    create_request(chr, Italic, all, Some(monospace)) |> ignore
    create_request(chr, Bold, all, Some(monospace)) |> ignore
  }
  (self.read_widths)(bare_font_info, all)
  let mut max_digit_width = 0.0
  for digit in digits {
    max_digit_width = max_double(max_digit_width, digit.width)
  }
  let mut is_monospace = bare_font_info.font_feature_settings ==
    @common_config.editor_font_ligatures_off
  let reference_width = monospace[0].width
  for index in 1..<monospace.length() {
    if !is_monospace {
      break
    }
    let diff = reference_width - monospace[index].width
    if diff < -0.001 || diff > 0.001 {
      is_monospace = false
    }
  }
  let mut can_use_halfwidth_rightwards_arrow = true
  if is_monospace && halfwidth_rightwards_arrow.width != reference_width {
    // Using a halfwidth rightwards arrow would break monospace...
    can_use_halfwidth_rightwards_arrow = false
  }
  if halfwidth_rightwards_arrow.width > rightwards_arrow.width {
    // Using a halfwidth rightwards arrow would paint a larger arrow than a
    // regular rightwards arrow.
    can_use_halfwidth_rightwards_arrow = false
  }
  {
    pixel_ratio: (self.read_pixel_ratio)(),
    font_family: bare_font_info.font_family,
    font_weight: bare_font_info.font_weight,
    font_size: bare_font_info.font_size,
    font_feature_settings: bare_font_info.font_feature_settings,
    font_variation_settings: bare_font_info.font_variation_settings,
    line_height: bare_font_info.line_height,
    letter_spacing: bare_font_info.letter_spacing,
    is_trusted: true,
    is_monospace,
    typical_halfwidth_character_width: typical_halfwidth_character.width,
    typical_fullwidth_character_width: typical_fullwidth_character.width,
    can_use_halfwidth_rightwards_arrow,
    space_width: space.width,
    middot_width: middot.width,
    wsmiddot_width: wsmiddot.width,
    max_digit_width,
  }
}

///|
fn max_double(left : Double, right : Double) -> Double {
  if left > right {
    left
  } else {
    right
  }
}

///|
fn schedule_timeout(callback : () -> Unit, ms : Int) -> Unit {
  @base_browser.schedule_timeout(callback, ms) |> ignore
}
