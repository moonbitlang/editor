///| White-box tests for the `setValue` flush lane (`text_model.mbt` setValue
/// region + `text_model_events.mbt`) — the plan's Phase-4 matrix rows local
/// to the model: version ids, whole-buffer equality, decoration
/// destruction, the public payload shape, the two-loop dispatch order, the
/// deferred content emitter, and the disposing guard.

///|
enum TransitionEolForm {
  TransitionLf
  TransitionCrlf
  TransitionCr
  TransitionMixed
}

///|
fn transition_text(lines : Array[String], form : TransitionEolForm) -> String {
  let sb = StringBuilder::new()
  for i, line in lines {
    if i > 0 {
      match form {
        TransitionLf => sb.write_string("\n")
        TransitionCrlf => sb.write_string("\r\n")
        TransitionCr => sb.write_string("\r")
        TransitionMixed =>
          match (i - 1) % 3 {
            0 => sb.write_string("\r\n")
            1 => sb.write_string("\r")
            _ => sb.write_string("\n")
          }
      }
    }
    sb.write_string(line)
  }
  sb.to_string()
}

///|
fn transition_normalized(lines : Array[String]) -> String {
  lines.join("\n")
}

///|
fn assert_transition_coordinates(model : TextModel) -> Unit raise {
  let length = model.get_value_length()
  for offset in 0..<=length {
    let position = model.get_position_at(offset)
    assert_eq(model.get_offset_at(position), offset)
  }
  let full = model.get_full_model_range()
  assert_eq(model.get_offset_at(full.get_end_position()), length)
}

///|
/// The complete ordered `oldForm x newForm` matrix from the EOL plan:
/// LF/CRLF/CR/mixed, once with normalized-equal content and once with changed
/// logical content. This loop executes 4 * 4 * 2 = 32 independent swaps.
test "set_value 4x4 EOL transitions cover normalized-equal and changed lanes" {
  let forms = [TransitionLf, TransitionCrlf, TransitionCr, TransitionMixed]
  let old_lines = ["alpha", "beta", "gamma", "delta"]
  let changed_lines = ["new", "logical content", "has", "changed"]
  let old_normalized = transition_normalized(old_lines)
  let changed_normalized = transition_normalized(changed_lines)
  let mut case_count = 0
  for old_form in forms {
    for new_form in forms {
      for changed in [false, true] {
        case_count += 1
        let old_input = transition_text(old_lines, old_form)
        let new_lines = if changed { changed_lines } else { old_lines }
        let new_input = transition_text(new_lines, new_form)
        let expected_new = if changed {
          changed_normalized
        } else {
          old_normalized
        }
        let model = wb_model(old_input)
        assert_eq(model.get_value(), old_normalized)
        assert_eq(model.get_eol(), "\n")
        assert_transition_coordinates(model)
        let old_full_range = model.get_full_model_range()
        let old_length = model.get_value_length()
        assert_eq(
          model.get_offset_at(old_full_range.get_end_position()),
          old_length,
        )
        let old_version = model.get_version_id()
        let events : Array[ModelContentChangedEvent] = []
        let _sub = model.on_did_change_content(e => events.push(e))
        model.set_value(new_input)
        assert_eq(events.length(), 1)
        let event = events[0]
        assert_eq(event.version_id, old_version + 1)
        assert_eq(event.eol, "\n")
        assert_eq(event.is_undoing, false)
        assert_eq(event.is_redoing, false)
        assert_eq(event.is_flush, true)
        assert_eq(event.is_eol_change, false)
        assert_eq(event.changes.length(), 1)
        let change = event.changes[0]
        assert_true(change.range == old_full_range)
        assert_eq(change.range_offset, 0)
        assert_eq(change.range_length, old_length)
        assert_eq(change.text, expected_new)
        assert_eq(model.get_version_id(), old_version + 1)
        assert_eq(model.get_value(), expected_new)
        assert_eq(model.snapshot.text, expected_new)
        assert_eq(model.get_eol(), "\n")
        assert_transition_coordinates(model)
      }
    }
  }
  assert_eq(case_count, 32)
}

///|
/// U+FEFF is ordinary Viewer content, so set_value add/remove-BOM transitions
/// use the same normalized range/length/event contract as any other code unit.
test "set_value keeps BOM as ordinary content when adding and removing it" {
  let bom = "\u{FEFF}"
  let model = wb_model(bom + "a\r\nb")
  let events : Array[ModelContentChangedEvent] = []
  let _sub = model.on_did_change_content(e => events.push(e))
  let old_range = model.get_full_model_range()
  let old_length = model.get_value_length()
  model.set_value("a\r\nb")
  assert_eq(events.length(), 1)
  assert_true(events[0].changes[0].range == old_range)
  assert_eq(events[0].changes[0].range_length, old_length)
  assert_eq(events[0].changes[0].text, "a\nb")
  assert_eq(model.get_value(), "a\nb")
  model.set_value(bom + "a\rb")
  assert_eq(events.length(), 2)
  assert_eq(events[1].changes[0].range_length, "a\nb".length())
  assert_eq(events[1].changes[0].text, bom + "a\nb")
  assert_eq(model.get_value(), bom + "a\nb")
  assert_eq(model.might_contain_non_basic_ascii(), true)
}

///|
test "set_value bumps the version id and swaps the snapshot" {
  let model = wb_model("alpha\nbravo")
  assert_eq(model.get_version_id(), 1)
  model.set_value("x\ny\nz")
  assert_eq(model.get_version_id(), 2)
  assert_eq(model.get_value(), "x\ny\nz")
  assert_eq(model.get_line_count(), 3)
  // identical content still flushes (the no-op early return is the host's,
  // per modelService.ts:370-373)
  model.set_value("x\ny\nz")
  assert_eq(model.get_version_id(), 3)
}

///|
test "set_value destroys all decorations; stale ids delta as a no-op" {
  let model = wb_model("alpha\nbravo")
  let ids = model.delta_decorations([], [
    { range: Range(1, 1, 1, 3), options: wb_options("one") },
    { range: Range(2, 1, 2, 4), options: wb_options("two") },
  ])
  assert_eq(model.get_all_decorations().length(), 2)
  model.set_value("alpha\nbravo")
  assert_eq(model.decorations.length(), 0)
  assert_eq(model.get_all_decorations().length(), 0)
  // the destroyed ids are unknown to the fresh storage: removing them is a
  // no-op and re-adding through them seeds fresh nodes
  let replaced = model.delta_decorations(ids, [
    { range: Range(1, 1, 1, 2), options: wb_options("three") },
  ])
  assert_eq(replaced.length(), 1)
  assert_eq(model.get_all_decorations().length(), 1)
}

///|
test "set_value emits one full-range public change with isFlush" {
  let model = wb_model("alpha\nbravo")
  let events : Array[ModelContentChangedEvent] = []
  let _sub = model.on_did_change_content(e => events.push(e))
  model.set_value("x\ny\nz")
  assert_eq(events.length(), 1)
  let e = events[0]
  assert_eq(e.is_flush, true)
  assert_eq(e.is_eol_change, false)
  assert_eq(e.is_undoing, false)
  assert_eq(e.is_redoing, false)
  assert_eq(e.version_id, 2)
  assert_eq(e.eol, "\n")
  assert_eq(e.changes.length(), 1)
  let change = e.changes[0]
  // the replaced range is the OLD full model range and length
  assert_true(change.range == Range(1, 1, 2, 6))
  assert_eq(change.range_offset, 0)
  assert_eq(change.range_length, "alpha\nbravo".length())
  // the text is the NEW full value (read after the buffer swap)
  assert_eq(change.text, "x\ny\nz")
}

///|
test "set_value re-seeds visible token state without a full reset event" {
  let registration = @syntax.tokenization_registry.register(
    "moonbit",
    @syntax.PlainTokenizer(),
  )
  let model = wb_model("alpha\nbravo")
  let view = model.on_before_attached()
  view.set_visible_lines([{ start_line_number: 1, end_line_number: 2 }], true)
  let to_lines : Array[Int] = []
  let _sub = model.on_did_change_tokens(e => {
    to_lines.push(e.ranges[0].to_line_number)
  })
  model.set_value("one\ntwo\nthree")
  // The shared model state sees the NEW line count before flush handling, while
  // the internal reset suppresses its whole-document event. The retained
  // visible range is refreshed and reports only lines one through two.
  assert_true(to_lines == [2])
  assert_eq(model.tokenization.get_line_tokens(3).get_line_content(), "three")
  model.on_before_detached(view)
  registration.dispose()
}

///|
test "no content event is emitted while disposing" {
  let model = wb_model("alpha")
  let mut content_events = 0
  let _sub = model.on_did_change_content(_ => {
    content_events = content_events + 1
  })
  let _will = model.on_will_dispose(() => model.set_value("ghost"))
  model.dispose()
  // the swap and version bump still happened; only the events are
  // suppressed (`textModel.ts:468-471`)
  assert_eq(content_events, 0)
  assert_eq(model.get_value(), "ghost")
  assert_eq(model.get_version_id(), 2)
}

///|
test "equals_text_snapshot compares the normalized whole buffer" {
  let model = wb_model("alpha\r\nbravo")
  assert_eq(model.equals_text_snapshot(TextSnapshot("alpha\r\nbravo")), true)
  assert_eq(model.equals_text_snapshot(TextSnapshot("alpha\nbravo")), true)
  model.set_value("x")
  assert_eq(model.equals_text_snapshot(TextSnapshot("x")), true)
  assert_eq(TextSnapshot("a").equals(TextSnapshot("a")), true)
  assert_eq(TextSnapshot("a").equals(TextSnapshot("b")), false)
  assert_eq(TextSnapshot("a\r\nb").equals(TextSnapshot("a\nb")), true)
}

///|
test "DidChangeContentEmitter merges flushes inside a deferred bracket" {
  let model = wb_model("a")
  let events : Array[ModelContentChangedEvent] = []
  let _sub = model.on_did_change_content(e => events.push(e))
  model.event_emitter.begin_deferred_emit()
  model.set_value("b")
  model.set_value("c\nd")
  assert_eq(events.length(), 0)
  model.event_emitter.end_deferred_emit()
  assert_eq(events.length(), 1)
  let e = events[0]
  // merged: both changes, the LAST version id, isFlush sticky-true
  assert_eq(e.changes.length(), 2)
  assert_eq(e.version_id, 3)
  assert_eq(e.is_flush, true)
  assert_eq(e.changes[1].text, "c\nd")
}

///|
test "two-loop dispatch: every structural update precedes every emit" {
  let log : Array[String] = []
  let model = wb_model("x")
  let registration_a = model.register_view_model(
    _e => log.push("a:structure"),
    _e => log.push("a:emit"),
  )
  let registration_b = model.register_view_model(
    _e => log.push("b:structure"),
    _e => log.push("b:emit"),
  )
  // the public emitter fires only after both loops (`textModel.ts:480-481`)
  let _sub = model.on_did_change_content(_ => log.push("public"))
  model.set_value("y")
  assert_true(
    log == ["a:structure", "b:structure", "a:emit", "b:emit", "public"],
  )
  // the registration handle removes exactly its callbacks and is idempotent
  registration_a.dispose()
  registration_a.dispose()
  log.clear()
  model.set_value("z")
  assert_true(log == ["b:structure", "b:emit", "public"])
  registration_b.dispose()
}

///|
test "raw change union carries the tier-2 shape (contains_event, merge)" {
  let flush_only : ModelRawContentChangedEvent = {
    changes: [ModelRawFlush],
    version_id: 2,
    is_undoing: false,
    is_redoing: false,
  }
  assert_eq(flush_only.contains_event(Flush), true)
  assert_eq(flush_only.contains_event(LinesInserted), false)
  let inserted : ModelRawContentChangedEvent = {
    changes: [
      ModelRawLinesInserted(
        from_line_number=1,
        from_line_number_post_edit=1,
        count=2,
      ),
    ],
    version_id: 3,
    is_undoing: true,
    is_redoing: false,
  }
  let merged = ModelRawContentChangedEvent::merge(flush_only, inserted)
  assert_eq(merged.changes.length(), 2)
  assert_eq(merged.version_id, 3)
  assert_eq(merged.is_undoing, true)
  assert_eq(merged.is_redoing, false)
  assert_eq(merged.contains_event(Flush), true)
  assert_eq(merged.contains_event(LinesInserted), true)
}
