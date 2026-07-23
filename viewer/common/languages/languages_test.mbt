///|
test "public languages facade registers hover providers" {
  let disposable = @languages.languages.register_hover_provider(
    LanguageId("moonbit"),
    PublicHoverProvider::{  },
  )
  disposable.dispose()
}

///|
test "public languages facade registers markdown comment providers" {
  let disposable = @languages.languages.register_markdown_comment_provider(
    LanguageId("moonbit"),
    PublicMarkdownCommentProvider::{  },
  )
  disposable.dispose()
}

///|
priv struct PublicHoverProvider {}

///|
impl @language.HoverProvider for PublicHoverProvider with fn provide_hover(
  _self,
  _document,
  _position,
  _token,
) {
  None
}

///|
priv struct PublicMarkdownCommentProvider {}

///|
impl @language.MarkdownCommentProvider for PublicMarkdownCommentProvider with fn provide_markdown_comments(
  _self,
  _document,
) {
  []
}
