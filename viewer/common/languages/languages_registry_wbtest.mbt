///|
fn test_model() -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/language-test.mbt",
    ),
    "language-test.mbt",
    "moonbit",
    7,
    "rev-7",
    "fn main {\n  value\n}\n",
  )
}

///|
async test "provider failures are logged and isolated" {
  let memory = @log.MemoryLogger()
  let log_service = @log.LogService(logger=memory)
  let languages = Languages()
  languages.register_hover_provider(LanguageId("moonbit"), FailingHoverProvider::{

  })
  |> ignore
  languages.register_hover_provider(LanguageId("moonbit"), TestHoverProvider::{

  })
  |> ignore
  let model = test_model()
  let hover = languages.hover_at(model, 3, log_service)
  assert_true(hover is Some(_))
  let entries = memory.entries()
  assert_eq(entries.length(), 1)
  assert_true(entries[0].category == "language.hover")
  assert_true(entries[0].details[2] == ("providerIndex", "0"))
}

///|
async test "language handle prebinds logging and forwards the exact capability" {
  let memory = @log.MemoryLogger()
  let languages = Languages()
  languages.set_language_configuration("moonbit", {
    comments: None,
    folding_rules: Some({ off_side: true, markers: None }),
  })
  languages.register_hover_provider(LanguageId("moonbit"), FailingHoverProvider::{

  })
  |> ignore
  languages.register_hover_provider(LanguageId("moonbit"), TestHoverProvider::{

  })
  |> ignore
  let handle = languages.language_handle(
    @log.LogService(logger=memory).log_handle(),
  )
  assert_true(
    handle.get_language_configuration("moonbit").folding_rules
    is Some({ off_side: true, markers: None }),
  )
  assert_hover_text(handle.hover_at(test_model(), 3), "provider hover")
  let entries = memory.entries()
  assert_eq(entries.length(), 1)
  assert_true(entries[0].category == "language.hover")
}

///|
test "token providers dispose only the active registration" {
  let languages = Languages()
  let first = languages.set_tokens_provider(
    "toy-dispose",
    @syntax.PlainTokenizer(),
  )
  let second = languages.set_tokens_provider(
    "toy-dispose",
    @syntax.PlainTokenizer(),
  )
  first.dispose()
  assert_true(@syntax.tokenization_registry.get("toy-dispose") is Some(_))
  second.dispose()
  assert_true(@syntax.tokenization_registry.get("toy-dispose") is None)
}

///|
async test "language provider registrations preserve order after disposal" {
  let languages = Languages()
  let first = languages.register_hover_provider(LanguageId("moonbit"), NamedHoverProvider::{
    text: "first",
  })
  let second = languages.register_hover_provider(LanguageId("moonbit"), NamedHoverProvider::{
    text: "second",
  })
  let log_service = @log.LogService()
  let model = test_model()
  assert_hover_text(languages.hover_at(model, 3, log_service), "first")
  first.dispose()
  assert_hover_text(languages.hover_at(model, 3, log_service), "second")
  second.dispose()
  assert_true(languages.hover_at(model, 3, log_service) is None)
}

///|
test "markdown comment providers preserve order disposal and authoritative empty" {
  let languages = Languages()
  let model = test_model()
  let log_service = @log.LogService()
  assert_true(
    languages.markdown_comment_provider_result(model, log_service) is None,
  )

  let unmatched_calls = Ref(0)
  let unmatched = languages.register_markdown_comment_provider(
    LanguageId("javascript"),
    RecordingMarkdownCommentProvider::{
      blocks: [markdown_comment_block("unmatched")],
      calls: unmatched_calls,
    },
  )
  let empty_calls = Ref(0)
  let empty = languages.register_markdown_comment_provider(
    LanguageId("moonbit"),
    RecordingMarkdownCommentProvider::{ blocks: [], calls: empty_calls },
  )
  let second_calls = Ref(0)
  let second = languages.register_markdown_comment_provider(
    LanguageId("moonbit"),
    RecordingMarkdownCommentProvider::{
      blocks: [markdown_comment_block("second")],
      calls: second_calls,
    },
  )

  guard languages.markdown_comment_provider_result(model, log_service)
    is Some(first_result) else {
    fail("expected an authoritative empty provider result")
  }
  assert_eq(first_result.length(), 0)
  assert_eq(unmatched_calls.val, 0)
  assert_eq(empty_calls.val, 1)
  assert_eq(second_calls.val, 0)

  empty.dispose()
  guard languages.markdown_comment_provider_result(model, log_service)
    is Some(second_result) else {
    fail("expected the retained second provider")
  }
  assert_eq(second_result, [markdown_comment_block("second")])
  assert_eq(second_calls.val, 1)

  second.dispose()
  assert_true(
    languages.markdown_comment_provider_result(model, log_service) is None,
  )
  unmatched.dispose()
}

///|
test "language handle logs failed markdown provider as authoritative empty" {
  let languages = Languages()
  let failed = languages.register_markdown_comment_provider(
    LanguageId("moonbit"),
    FailingMarkdownCommentProvider::{  },
  )
  let later_calls = Ref(0)
  let later = languages.register_markdown_comment_provider(
    LanguageId("moonbit"),
    RecordingMarkdownCommentProvider::{
      blocks: [markdown_comment_block("later")],
      calls: later_calls,
    },
  )
  let memory = @log.MemoryLogger()
  let handle = languages.language_handle(
    @log.LogService(logger=memory).log_handle(),
  )
  guard handle.markdown_comment_provider_result(test_model()) is Some(result) else {
    fail("failed provider must remain authoritative")
  }
  assert_eq(result.length(), 0)
  assert_eq(later_calls.val, 0)
  let entries = memory.entries()
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].category, "language.markdownComments")
  assert_true(entries[0].details[2] == ("providerIndex", "0"))
  failed.dispose()
  later.dispose()
}

///|
priv struct TestHoverProvider {}

///|
impl @language.HoverProvider for TestHoverProvider with fn provide_hover(
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
priv struct NamedHoverProvider {
  text : String
}

///|
fn markdown_comment_block(markdown : String) -> @language.MarkdownCommentBlock {
  { line_range: LineRange(1, 2), markdown }
}

///|
priv struct RecordingMarkdownCommentProvider {
  blocks : Array[@language.MarkdownCommentBlock]
  calls : Ref[Int]
}

///|
impl @language.MarkdownCommentProvider for RecordingMarkdownCommentProvider with fn provide_markdown_comments(
  self,
  _model,
) {
  self.calls.val += 1
  self.blocks.copy()
}

///|
priv struct FailingMarkdownCommentProvider {}

///|
impl @language.MarkdownCommentProvider for FailingMarkdownCommentProvider with fn provide_markdown_comments(
  _self,
  _model,
) {
  raise TestProviderError
}

///|
impl @language.HoverProvider for NamedHoverProvider with fn provide_hover(
  self,
  model,
  position,
  _token,
) {
  let offset = model.get_offset_at(position)
  Some({
    range: model.snapshot.range_of(OffsetRange(offset, offset + 1)),
    contents: [PlainText(self.text)],
  })
}

///|
fn assert_hover_text(hover : @language.Hover?, expected : String) -> Unit raise {
  match hover {
    Some(hover) =>
      match hover.contents[0] {
        PlainText(text) => assert_eq(text, expected)
        Markdown(_) => fail("expected plaintext hover")
      }
    None => fail("expected hover")
  }
}

///|
priv suberror TestProviderError {
  TestProviderError
}

///|
priv struct FailingHoverProvider {}

///|
impl @language.HoverProvider for FailingHoverProvider with fn provide_hover(
  _self,
  _model,
  _position,
  _token,
) {
  raise TestProviderError
}
