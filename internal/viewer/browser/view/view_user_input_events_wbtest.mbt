///|
fn view_user_input_test_fixture() -> (@view_model.ViewModel, @model.TextModel) {
  let model = @model.TextModel(
    @base_common.Uri::file("/view-user-input-events.mbt"),
    "view-user-input-events.mbt",
    "plaintext",
    1,
    "view-user-input-events-rev-1",
    "abcdefgh",
  )
  let view_model = @view_model.ViewModel::with_options(
    model,
    @view_model.ViewModelOptions::soft_wrap(4),
  )
  (view_model, model)
}

///|
fn assert_view_user_input_position(
  position : @base_common.Position,
) -> Unit raise {
  assert_true(position == Position(1, 6))
}

///|
fn assert_view_user_input_range(range : @base_common.Range) -> Unit raise {
  assert_true(range == Range(1, 5, 1, 7))
}

///|
/// `ViewUserInputEvents.convertViewToModelMouseTarget`
/// (`viewUserInputEvents.ts:96-108`) branch matrix. The wrapped second view
/// line maps back into model line 1; widget targets remain unchanged because
/// they carry no model/view positions.
test "convertViewToModelMouseTarget converts every target arm" {
  let (view_model, model) = view_user_input_test_fixture()
  let converter = view_model.coordinates_converter()
  let view_position = @base_common.Position(2, 2)
  let view_range = @base_common.Range(2, 1, 2, 3)
  let margin_detail : @editor_browser.MouseTargetMarginData = {
    is_after_lines: false,
    glyph_margin_left: 0.0,
    glyph_margin_width: 0.0,
    line_numbers_width: 12.0,
    offset_x: 3.0,
  }
  let text_detail : @editor_browser.MouseTargetContentTextData = {
    might_be_foreign_element: false,
    injected_text: None,
  }
  let empty_detail : @editor_browser.MouseTargetContentEmptyData = {
    is_after_lines: false,
    horizontal_distance_to_text: Some(7.0),
  }

  match
    convert_view_to_model_mouse_target(
      MouseTargetUnknown(
        element=None,
        mouse_column=2,
        position=Some(view_position),
        range=Some(view_range),
      ),
      converter,
    ) {
    MouseTargetUnknown(position=Some(position), range=Some(range), ..) => {
      assert_view_user_input_position(position)
      assert_view_user_input_range(range)
    }
    _ => fail("expected converted unknown target")
  }
  match
    convert_view_to_model_mouse_target(
      MouseTargetUnknown(
        element=None,
        mouse_column=2,
        position=None,
        range=None,
      ),
      converter,
    ) {
    MouseTargetUnknown(position=None, range=None, ..) => ()
    _ => fail("expected absent unknown coordinates to stay absent")
  }
  match
    convert_view_to_model_mouse_target(
      MouseTargetMargin(
        type_=GutterLineNumbers,
        element=None,
        mouse_column=2,
        position=view_position,
        range=view_range,
        detail=margin_detail,
      ),
      converter,
    ) {
    MouseTargetMargin(position~, range~, detail~, ..) => {
      assert_view_user_input_position(position)
      assert_view_user_input_range(range)
      assert_true(detail == margin_detail)
    }
    _ => fail("expected converted margin target")
  }
  match
    convert_view_to_model_mouse_target(
      MouseTargetViewZone(
        type_=ContentViewZone,
        element=None,
        mouse_column=2,
        position=view_position,
        range=view_range,
        detail={
          view_zone_id: "zone-1",
          position_before: Some(view_position),
          position_after: None,
          position: view_position,
          after_line_number: 1,
        },
      ),
      converter,
    ) {
    MouseTargetViewZone(position~, range~, detail~, ..) => {
      assert_view_user_input_position(position)
      assert_view_user_input_range(range)
      assert_true(detail.position_before == Some(Position(1, 6)))
      assert_true(detail.position_after is None)
      assert_view_user_input_position(detail.position)
      assert_eq(detail.after_line_number, 1)
    }
    _ => fail("expected converted view-zone target")
  }
  match
    convert_view_to_model_mouse_target(
      MouseTargetContentText(
        element=None,
        mouse_column=2,
        position=view_position,
        range=view_range,
        detail=text_detail,
      ),
      converter,
    ) {
    MouseTargetContentText(position~, range~, detail~, ..) => {
      assert_view_user_input_position(position)
      assert_view_user_input_range(range)
      assert_false(detail.might_be_foreign_element)
      assert_true(detail.injected_text is None)
    }
    _ => fail("expected converted content-text target")
  }
  match
    convert_view_to_model_mouse_target(
      MouseTargetContentEmpty(
        element=None,
        mouse_column=2,
        position=view_position,
        range=view_range,
        detail=empty_detail,
      ),
      converter,
    ) {
    MouseTargetContentEmpty(position~, range~, detail~, ..) => {
      assert_view_user_input_position(position)
      assert_view_user_input_range(range)
      assert_true(detail == empty_detail)
    }
    _ => fail("expected converted content-empty target")
  }
  match
    convert_view_to_model_mouse_target(
      MouseTargetContentWidget(element=None, mouse_column=2, detail="content"),
      converter,
    ) {
    MouseTargetContentWidget(mouse_column=2, detail="content", ..) => ()
    _ => fail("expected unchanged content-widget target")
  }
  match
    convert_view_to_model_mouse_target(
      MouseTargetOverlayWidget(element=None, mouse_column=2, detail="overlay"),
      converter,
    ) {
    MouseTargetOverlayWidget(mouse_column=2, detail="overlay", ..) => ()
    _ => fail("expected unchanged overlay-widget target")
  }
  match
    convert_view_to_model_mouse_target(
      MouseTargetScrollbar(
        element=None,
        mouse_column=2,
        position=view_position,
        range=view_range,
      ),
      converter,
    ) {
    MouseTargetScrollbar(position~, range~, ..) => {
      assert_view_user_input_position(position)
      assert_view_user_input_range(range)
    }
    _ => fail("expected converted scrollbar target")
  }
  match
    convert_view_to_model_mouse_target(
      MouseTargetOutsideEditor(
        mouse_column=2,
        position=view_position,
        range=view_range,
        outside_position=Below,
        outside_distance=9.0,
      ),
      converter,
    ) {
    MouseTargetOutsideEditor(
      position~,
      range~,
      outside_position=Below,
      outside_distance=9.0,
      ..
    ) => {
      assert_view_user_input_position(position)
      assert_view_user_input_range(range)
    }
    _ => fail("expected converted outside-editor target")
  }
  view_model.dispose()
  model.dispose()
}
