///|
fn computer_test_model() -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/hover-test.mbt",
    ),
    "hover-test.mbt",
    "moonbit",
    7,
    "rev-7",
    "fn main {\n  value\n}\n",
  )
}

///|
async test "content hover computer separates sync markers from async markdown" {
  let languages = @languages.Languages()
  let markers = @markers.MarkerService()
  let marker_decorations = @markers.MarkerDecorationsService(
    markers.marker_service_handle(),
  )
  let model = computer_test_model()
  marker_decorations.on_model_added(model)
  markers.set_diagnostics("diagnostics:0", model.uri, [
    {
      range: Range(2, 3, 2, 8),
      severity: Warning,
      message: "marker hover",
      tags: None,
    },
  ])
  languages.register_hover_provider(LanguageId("moonbit"), ComputerHoverProvider::{

  })
  |> ignore
  let services : HoverParticipantServices = {
    languages: languages.language_handle(@log.LogService().log_handle()),
    marker_decorations: marker_decorations.marker_decorations_handle(),
  }
  let computer = ContentHoverComputer(services)
  let anchor : HoverAnchor = HoverRangeAnchor(
    priority=0,
    range=Range(2, 3, 2, 8),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
  let sync_hover = computer.compute_sync(model, anchor)
  match sync_hover {
    Some(hover) => {
      assert_eq(hover.parts.length(), 1)
      assert_true(hover.parts[0] is MarkerHover(_))
    }
    None => fail("expected marker hover")
  }
  let async_hover = computer.compute_async(model, anchor)
  match async_hover {
    Some(hover) => {
      assert_eq(hover.parts.length(), 1)
      assert_true(hover.parts[0] is MarkdownHover(_))
    }
    None => fail("expected markdown hover")
  }
}

///|
priv struct ComputerHoverProvider {}

///|
impl @language.HoverProvider for ComputerHoverProvider with fn provide_hover(
  _self,
  model,
  position,
  _token,
) {
  let offset = model.get_offset_at(position)
  Some({
    range: model.snapshot.range_of(OffsetRange(offset, offset + 1)),
    contents: [PlainText("provider hover")],
  })
}

///|
priv struct RecordingHoverProvider {
  calls : Ref[Int]
  seen_token : Ref[@language.CancellationToken?]
}

///|
impl @language.HoverProvider for RecordingHoverProvider with fn provide_hover(
  self,
  model,
  position,
  token,
) {
  self.calls.val += 1
  self.seen_token.val = Some(token)
  let offset = model.get_offset_at(position)
  Some({
    range: model.snapshot.range_of(OffsetRange(offset, offset + 1)),
    contents: [PlainText("recorded provider hover")],
  })
}

///|
fn computer_services_with_languages(
  languages : @languages.Languages,
) -> HoverParticipantServices {
  let markers = @markers.MarkerService()
  let marker_decorations = @markers.MarkerDecorationsService(
    markers.marker_service_handle(),
  )
  {
    languages: languages.language_handle(@log.LogService().log_handle()),
    marker_decorations: marker_decorations.marker_decorations_handle(),
  }
}

///|
async test "caller cancellation token reaches the language provider unchanged" {
  let languages = @languages.Languages()
  let calls = Ref(0)
  let seen_token : Ref[@language.CancellationToken?] = Ref(None)
  languages.register_hover_provider(LanguageId("moonbit"), RecordingHoverProvider::{
    calls,
    seen_token,
  })
  |> ignore
  let computer = ContentHoverComputer(
    computer_services_with_languages(languages),
  )
  let model = computer_test_model()
  let anchor : HoverAnchor = HoverRangeAnchor(
    priority=0,
    range=Range(2, 3, 2, 3),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
  let token = @language.CancellationToken::new()
  assert_true(computer.compute_async(model, anchor, token~) is Some(_))
  assert_eq(calls.val, 1)
  match seen_token.val {
    Some(provider_token) => {
      assert_true(physical_equal(provider_token, token))
      token.cancel()
      // Cancellation through the caller's value is observable through the
      // exact token value retained by the provider.
      assert_true(provider_token.is_cancellation_requested())
    }
    None => fail("expected provider token")
  }
}

///|
async test "pre-canceled async computation never launches a participant provider" {
  let languages = @languages.Languages()
  let calls = Ref(0)
  let seen_token : Ref[@language.CancellationToken?] = Ref(None)
  languages.register_hover_provider(LanguageId("moonbit"), RecordingHoverProvider::{
    calls,
    seen_token,
  })
  |> ignore
  let computer = ContentHoverComputer(
    computer_services_with_languages(languages),
  )
  let model = computer_test_model()
  let anchor : HoverAnchor = HoverRangeAnchor(
    priority=0,
    range=Range(2, 3, 2, 3),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
  let token = @language.CancellationToken::new()
  token.cancel()
  assert_true(computer.compute_async(model, anchor, token~) is None)
  assert_eq(calls.val, 0)
  assert_true(seen_token.val is None)
}

///|
fn selected_has(
  decorations : Array[@model.ModelDecoration],
  class_name : String,
) -> Bool {
  decorations.any(decoration => decoration.options.class_name == class_name)
}

///|
test "line-decoration selector covers whole strict relaxed and crossing ranges" {
  let model = computer_test_model()
  model.delta_decorations([], [
    {
      range: Range(2, 8, 2, 8),
      options: ModelDecorationOptions("whole", is_whole_line=true),
    },
    { range: Range(2, 3, 2, 6), options: ModelDecorationOptions("ordinary") },
    {
      range: Range(2, 3, 2, 6),
      options: ModelDecorationOptions("relaxed", show_if_collapsed=true),
    },
    { range: Range(1, 9, 2, 4), options: ModelDecorationOptions("cross-start") },
    { range: Range(2, 6, 3, 2), options: ModelDecorationOptions("cross-end") },
  ])
  |> ignore
  let at = column => {
    hover_line_decorations(
      model,
      HoverRangeAnchor(
        priority=0,
        range=Range(2, column, 2, column),
        initial_mouse_pos_x=None,
        initial_mouse_pos_y=None,
      ),
    )
  }

  let left_relaxed = at(2)
  assert_true(selected_has(left_relaxed, "whole"))
  assert_false(selected_has(left_relaxed, "ordinary"))
  assert_true(selected_has(left_relaxed, "relaxed"))
  // Crossing from line 1 uses start-column fallback 1.
  assert_true(selected_has(left_relaxed, "cross-start"))
  assert_false(selected_has(left_relaxed, "cross-end"))

  let inside = at(3)
  assert_true(selected_has(inside, "ordinary"))
  let right_relaxed = at(7)
  assert_false(selected_has(right_relaxed, "ordinary"))
  assert_true(selected_has(right_relaxed, "relaxed"))
  // Crossing into line 3 uses the anchor line's max-column fallback.
  assert_true(selected_has(right_relaxed, "cross-end"))
  assert_false(selected_has(at(1), "relaxed"))
  assert_false(selected_has(at(8), "relaxed"))

  let invalid = HoverRangeAnchor(
    priority=0,
    range=Range(4, 1, 4, 1),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
  assert_eq(hover_line_decorations(model, invalid).length(), 0)
  let unsupported_foreign = HoverForeignElementAnchor(
    priority=10,
    owner=HoverParticipantOwner(),
    injected_text_index=0,
    range=Range(2, 3, 2, 3),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
    supports_marker_hover=false,
  )
  assert_eq(hover_line_decorations(model, unsupported_foreign).length(), 0)
}

///|
priv struct ParticipantProbe {
  async_calls : Ref[Int]
  sync_sources : Array[HoverStartSource]
  async_sources : Array[HoverStartSource]
}

///|
fn ParticipantProbe::new() -> ParticipantProbe {
  { async_calls: Ref(0), sync_sources: [], async_sources: [] }
}

///|
priv struct ControlledHoverParticipant {
  ordinal_value : Int
  text : String
  probe : ParticipantProbe
}

///|
fn ControlledHoverParticipant::hover_participant_handle(
  self : ControlledHoverParticipant,
) -> HoverParticipantHandle {
  HoverParticipantHandle(
    self.ordinal_value,
    ctx => {
      self.probe.sync_sources.push(ctx.source)
      [
        MarkdownHover(
          range=ctx.anchor.range(),
          contents=[PlainText(self.text)],
          ordinal=self.ordinal_value,
        ),
      ]
    },
    compute_async=(ctx, _token) => {
      self.probe.async_calls.val += 1
      self.probe.async_sources.push(ctx.source)
      [
        MarkdownHover(
          range=ctx.anchor.range(),
          contents=[PlainText(self.text)],
          ordinal=self.ordinal_value,
        ),
      ]
    },
    create_loading_message=anchor => {
      Some(LoadingHover(range=anchor.range(), message=self.text))
    },
  )
}

///|
fn controlled_participant_with_probe(
  ordinal_value : Int,
  text : String,
  probe : ParticipantProbe,
) -> HoverParticipantHandle {
  ControlledHoverParticipant::{ ordinal_value, text, probe }.hover_participant_handle()
}

///|
fn controlled_participant(
  ordinal_value : Int,
  text : String,
) -> HoverParticipantHandle {
  controlled_participant_with_probe(
    ordinal_value,
    text,
    ParticipantProbe::new(),
  )
}

///|
fn first_plain_text(parts : Array[HoverPart]) -> String {
  guard parts.get(0) is Some(MarkdownHover(contents~, ..)) else { return "" }
  match contents.get(0) {
    Some(PlainText(text)) => text
    _ => ""
  }
}

///|
fn async_test_anchor() -> HoverAnchor {
  HoverRangeAnchor(
    priority=0,
    range=Range(2, 3, 2, 3),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
}

///|
async fn run_hover_tasks_in_reverse(tasks : Array[async () -> Unit]) -> Unit {
  let mut index = tasks.length()
  while index > 0 {
    index -= 1
    tasks[index]()
  }
}

///|
/// Starts every participant task before waiting for the group. The per-
/// participant semaphores below control completion independently, so the test
/// can observe one emitted result while its sibling is still suspended.
async fn run_hover_test_tasks_concurrently(
  tasks : Array[async () -> Unit],
) -> Unit {
  @async.with_task_group() <| group => {
    for task in tasks {
      group.spawn_bg(task)
    }
  }
}

///|
priv struct SuspendedHoverParticipant {
  ordinal_value : Int
  text : String
  started : @async.Semaphore
  release_gate : @async.Semaphore
  finished : Ref[Bool]
}

///|
fn SuspendedHoverParticipant::hover_participant_handle(
  self : SuspendedHoverParticipant,
) -> HoverParticipantHandle {
  HoverParticipantHandle(self.ordinal_value, _ctx => [], compute_async=(
    ctx,
    _token,
  ) => {
    self.started.release()
    self.release_gate.acquire() catch {
      _ => return []
    }
    self.finished.val = true
    [
      MarkdownHover(
        range=ctx.anchor.range(),
        contents=[PlainText(self.text)],
        ordinal=self.ordinal_value,
      ),
    ]
  })
}

///|
async test "async-each eagerly builds tasks and preserves A then B completion" {
  let a = ParticipantProbe::new()
  let b = ParticipantProbe::new()
  let computer : ContentHoverComputer = {
    participants: [
      controlled_participant_with_probe(10, "a", a),
      controlled_participant_with_probe(20, "b", b),
    ],
  }
  let emitted : Array[String] = []
  computer.compute_async_each(
    computer_test_model(),
    async_test_anchor(),
    run_tasks=tasks => {
      // Every participant producer exists before the runner starts any one.
      assert_eq(tasks.length(), 2)
      assert_eq(a.async_calls.val, 0)
      assert_eq(b.async_calls.val, 0)
      for task in tasks {
        task()
      }
    },
    emit=parts => emitted.push(first_plain_text(parts)),
  )
  assert_eq(emitted.join(","), "a,b")
  assert_eq(a.async_calls.val, 1)
  assert_eq(b.async_calls.val, 1)
}

///|
async test "async-each skips participants without an async callback" {
  let computer : ContentHoverComputer = {
    participants: [HoverParticipantHandle(10, _ctx => [])],
  }
  let runner_called = Ref(false)
  let emitted = Ref(0)
  computer.compute_async_each(
    computer_test_model(),
    async_test_anchor(),
    run_tasks=tasks => {
      runner_called.val = true
      assert_true(tasks.is_empty())
    },
    emit=_parts => emitted.val += 1,
  )
  assert_true(runner_called.val)
  assert_eq(emitted.val, 0)
}

///|
async test "async-each injected runner preserves B then A completion" {
  let computer : ContentHoverComputer = {
    participants: [
      controlled_participant(10, "a"),
      controlled_participant(20, "b"),
    ],
  }
  let emitted : Array[String] = []
  computer.compute_async_each(
    computer_test_model(),
    async_test_anchor(),
    run_tasks=run_hover_tasks_in_reverse,
    emit=parts => emitted.push(first_plain_text(parts)),
  )
  assert_eq(emitted.join(","), "b,a")
}

///|
async test "async-each emits B while A remains suspended then preserves B-to-A arrival order" {
  let started = @async.Semaphore(2, initial_value=0)
  let release_a = @async.Semaphore(1, initial_value=0)
  let release_b = @async.Semaphore(1, initial_value=0)
  let emitted_signal = @async.Semaphore(2, initial_value=0)
  let finished_a = Ref(false)
  let finished_b = Ref(false)
  let computer : ContentHoverComputer = {
    participants: [
      SuspendedHoverParticipant::{
        ordinal_value: 10,
        text: "a",
        started,
        release_gate: release_a,
        finished: finished_a,
      }.hover_participant_handle(),
      SuspendedHoverParticipant::{
        ordinal_value: 20,
        text: "b",
        started,
        release_gate: release_b,
        finished: finished_b,
      }.hover_participant_handle(),
    ],
  }
  let emitted : Array[String] = []
  @async.with_task_group() <| group => {
    let request = group.spawn(() => {
      computer.compute_async_each(
        computer_test_model(),
        async_test_anchor(),
        run_tasks=run_hover_test_tasks_concurrently,
        emit=parts => {
          emitted.push(first_plain_text(parts))
          emitted_signal.release()
        },
      )
    })

    // Both producers have started and are suspended on independent gates.
    started.acquire()
    started.acquire()
    assert_false(finished_a.val)
    assert_false(finished_b.val)

    // B completes first. Its partial result is observable while A remains
    // blocked, proving emission does not wait for the whole participant set.
    release_b.release()
    emitted_signal.acquire()
    assert_true(finished_b.val)
    assert_false(finished_a.val)
    assert_eq(emitted.join(","), "b")

    release_a.release()
    emitted_signal.acquire()
    request.wait()
    assert_true(finished_a.val)
    assert_eq(emitted.join(","), "b,a")
  }
}

///|
async test "sync async and async-each propagate the exact hover start source" {
  let sync_probe = ParticipantProbe::new()
  let async_probe = ParticipantProbe::new()
  let each_probe = ParticipantProbe::new()
  let model = computer_test_model()
  let anchor = async_test_anchor()

  let sync_computer : ContentHoverComputer = {
    participants: [controlled_participant_with_probe(10, "sync", sync_probe)],
  }
  assert_true(
    sync_computer.compute_sync(model, anchor, source=HoverStartClick) is Some(_),
  )
  assert_eq(sync_probe.sync_sources.length(), 1)
  assert_true(sync_probe.sync_sources[0] is HoverStartClick)

  let async_computer : ContentHoverComputer = {
    participants: [controlled_participant_with_probe(10, "async", async_probe)],
  }
  assert_true(
    async_computer.compute_async(model, anchor, source=HoverStartKeyboard)
    is Some(_),
  )
  assert_eq(async_probe.async_sources.length(), 1)
  assert_true(async_probe.async_sources[0] is HoverStartKeyboard)

  let each_computer : ContentHoverComputer = {
    participants: [controlled_participant_with_probe(10, "each", each_probe)],
  }
  each_computer.compute_async_each(model, anchor, source=HoverStartClick, emit=_parts => {
    ()
  })
  assert_eq(each_probe.async_sources.length(), 1)
  assert_true(each_probe.async_sources[0] is HoverStartClick)
}

///|
async test "async-each drops later completions after caller cancellation" {
  let computer : ContentHoverComputer = {
    participants: [
      controlled_participant(10, "a"),
      controlled_participant(20, "b"),
    ],
  }
  let emitted : Array[String] = []
  let token = @language.CancellationToken::new()
  computer.compute_async_each(
    computer_test_model(),
    async_test_anchor(),
    token~,
    run_tasks=run_hover_tasks_in_reverse,
    emit=parts => {
      emitted.push(first_plain_text(parts))
      token.cancel()
    },
  )
  assert_eq(emitted.join(","), "b")
}

///|
async test "async-each drops later completions after generation guard changes" {
  let computer : ContentHoverComputer = {
    participants: [
      controlled_participant(10, "a"),
      controlled_participant(20, "b"),
    ],
  }
  let emitted : Array[String] = []
  let current = Ref(true)
  computer.compute_async_each(
    computer_test_model(),
    async_test_anchor(),
    is_current=() => current.val,
    run_tasks=run_hover_tasks_in_reverse,
    emit=parts => {
      emitted.push(first_plain_text(parts))
      current.val = false
    },
  )
  assert_eq(emitted.join(","), "b")
}

///|
test "registry get_all aliases backing factories and build_all sorts ordinals" {
  let registry = HoverParticipantRegistry()
  let backing = registry.get_all()
  registry.register(_services => controlled_participant(30, "thirty"))
  assert_eq(backing.length(), 1)
  backing.push(_services => controlled_participant(10, "ten-a"))
  registry.register(_services => controlled_participant(10, "ten-b"))
  assert_eq(registry.get_all().length(), 3)
  let built = registry.build_all(computer_services_with_languages(Languages()))
  assert_eq(built.length(), 3)
  assert_eq(built[0].ordinal, 10)
  assert_eq(built[1].ordinal, 10)
  assert_eq(built[2].ordinal, 30)
  guard built[0].create_loading_message is Some(first_loading_message) else {
    fail("expected first loading-message callback")
  }
  match first_loading_message(async_test_anchor()) {
    Some(LoadingHover(message~, ..)) => assert_eq(message, "ten-a")
    _ => fail("expected first equal-ordinal participant")
  }
  guard built[1].create_loading_message is Some(second_loading_message) else {
    fail("expected second loading-message callback")
  }
  match second_loading_message(async_test_anchor()) {
    Some(LoadingHover(message~, ..)) => assert_eq(message, "ten-b")
    _ => fail("expected second equal-ordinal participant")
  }
}

///|
test "participant loading-message contract is explicit" {
  let services = computer_services_with_languages(Languages())
  let anchor = async_test_anchor()
  let markdown = MarkdownHoverParticipant(services.languages).hover_participant_handle()
  guard markdown.create_loading_message is Some(markdown_loading_message) else {
    fail("expected markdown loading-message callback")
  }
  assert_true(markdown_loading_message(anchor) is Some(LoadingHover(_)))
  let marker = MarkerHoverParticipant(services.marker_decorations).hover_participant_handle()
  assert_true(marker.create_loading_message is None)

  let absent : ContentHoverComputer = { participants: [] }
  assert_true(absent.create_loading_message(anchor) is None)
  let first_present : ContentHoverComputer = {
    participants: [
      controlled_participant(10, "first"),
      controlled_participant(20, "second"),
    ],
  }
  match first_present.create_loading_message(anchor) {
    Some(LoadingHover(message~, ..)) => assert_eq(message, "first")
    _ => fail("expected first participant loading message")
  }
}
