///|
struct LanguageFeatureRegistry[T] {
  entries : Array[LanguageFeatureEntry[T]]
  mut clock : Int
}

///|
priv struct LanguageFeatureEntry[T] {
  selector : @language.LanguageSelector
  provider : T
  active : Ref[Bool]
  registration_time : Int
}

///|
/// One request-start snapshot entry. `entry` is a value copy whose `active`
/// reference remains shared with the live registration, so an async request
/// never indexes the mutable registry after suspension while still being able
/// to reject a result from a registration disposed during the await.
priv struct LanguageFeatureSnapshot[T] {
  entry : LanguageFeatureEntry[T]
  provider_index : Int
  score : Int
}

///|
fn[T] LanguageFeatureRegistry::new() -> LanguageFeatureRegistry[T] {
  { entries: [], clock: 0 }
}

///|
fn[T] LanguageFeatureRegistry::register(
  self : LanguageFeatureRegistry[T],
  selector : @language.LanguageSelector,
  provider : T,
) -> @base_common.Disposable {
  let active = Ref(true)
  let registration_time = self.clock
  self.clock += 1
  let entry : LanguageFeatureEntry[T] = {
    selector,
    provider,
    active,
    registration_time,
  }
  self.entries.push(entry)
  @base_common.Disposable::from(() => {
    active.val = false
    let retained = self.entries.filter(item => item.active.val)
    self.entries.clear()
    self.entries.append(retained)
  })
}

///|
/// Captures the matching, currently active registrations in Monaco registry
/// priority: selector score descending, then registration time descending.
/// The returned array is independent of later registry compaction; each
/// captured entry retains the registration's shared liveness reference.
fn[T] LanguageFeatureRegistry::snapshot_matching(
  self : LanguageFeatureRegistry[T],
  model : @model.TextModel,
) -> Array[LanguageFeatureSnapshot[T]] {
  let result : Array[LanguageFeatureSnapshot[T]] = []
  for entry in self.entries {
    let score = entry.selector.score(model)
    if entry.active.val && score > 0 {
      result.push({ entry, provider_index: entry.registration_time, score })
    }
  }
  result.sort_by((left, right) => {
    let score_order = right.score - left.score
    if score_order != 0 {
      score_order
    } else {
      right.entry.registration_time - left.entry.registration_time
    }
  })
  result
}

///|
priv struct RegisteredMarkdownCommentProvider {
  provider : &@language.MarkdownCommentProvider
  foldable : Bool
}

///|
/// Raw result plus the registration-level presentation capability captured
/// from the same winning provider entry.
pub(all) struct MarkdownCommentProviderResult {
  blocks : Array[@language.MarkdownCommentBlock]
  foldable : Bool
}

///|
/// Public language registry for tokenization and language-feature providers.
/// Hosts normally use the process-wide `@languages.languages` value; tests and
/// embedded viewers that need isolation can create a fresh registry and pass it
/// through `ViewerServices(languages~)`.
pub struct Languages {
  priv hover_provider : LanguageFeatureRegistry[&@language.HoverProvider]
  priv definition_provider : LanguageFeatureRegistry[
    &@language.DefinitionProvider,
  ]
  priv document_symbol_provider : LanguageFeatureRegistry[
    &@language.DocumentSymbolProvider,
  ]
  priv markdown_comment_provider : LanguageFeatureRegistry[
    RegisteredMarkdownCommentProvider,
  ]
  /// Per-language comment/folding configuration — the viewer's stand-in for
  /// Monaco's `ILanguageConfigurationService` registrations.
  priv language_configurations : Map[String, LanguageConfiguration]
}

///|
/// Opaque production-language capability used by Viewer contributions. The
/// logging policy is prebound when the handle is derived, so consumers cannot
/// recover either the mutable registry or its concrete LogService.
pub struct LanguageHandle {
  priv get_language_configuration_callback : (String) -> LanguageConfiguration
  priv markdown_comment_provider_result_callback : (@model.TextModel) -> MarkdownCommentProviderResult?
  priv hover_at_callback : async (
    @model.TextModel,
    Int,
    @language.CancellationToken,
  ) -> @language.Hover? noraise
  priv definition_at_callback : async (
    @model.TextModel,
    Int,
    @language.CancellationToken,
    async (Array[async () -> Unit]) -> Unit,
  ) -> Array[@language.Location] noraise
  priv has_definition_provider_callback : (@model.TextModel) -> Bool
}

///|
/// Creates an isolated language registry.
#alias(new, deprecated)
pub fn Languages::Languages() -> Languages {
  {
    hover_provider: LanguageFeatureRegistry::new(),
    definition_provider: LanguageFeatureRegistry::new(),
    document_symbol_provider: LanguageFeatureRegistry::new(),
    markdown_comment_provider: LanguageFeatureRegistry::new(),
    language_configurations: Map([]),
  }
}

///|
/// Derives the minimal language capability used by folding, Markdown comments,
/// and hover. The handle owns no registry or logging state; its callbacks retain
/// the selected backings for as long as the host retains the handle.
pub fn Languages::language_handle(
  self : Languages,
  log_service : @log.LogHandle,
) -> LanguageHandle {
  {
    get_language_configuration_callback: language_id => {
      self.get_language_configuration(language_id)
    },
    markdown_comment_provider_result_callback: model => {
      self.markdown_comment_provider_result_with_log_handle(model, log_service)
    },
    hover_at_callback: (model, offset, token) => {
      self.hover_at_with_log_handle(model, offset, log_service, token~)
    },
    definition_at_callback: (model, offset, token, run_tasks) => {
      self.definition_at_with_log_handle(
        model,
        offset,
        log_service,
        token~,
        run_tasks~,
      )
    },
    has_definition_provider_callback: model => {
      self.has_definition_provider(model)
    },
  }
}

///|
/// Returns the first matching Markdown-comment provider's raw result. `None`
/// means that no provider matched; `Some([])` is an authoritative empty result
/// and must not be confused with absence.
pub fn LanguageHandle::markdown_comment_provider_result(
  self : LanguageHandle,
  model : @model.TextModel,
) -> Array[@language.MarkdownCommentBlock]? {
  match (self.markdown_comment_provider_result_callback)(model) {
    Some(result) => Some(result.blocks)
    None => None
  }
}

///|
/// Returns the first matching provider's blocks and registration-level
/// foldability from one captured registry entry.
pub fn LanguageHandle::markdown_comment_provider_render_result(
  self : LanguageHandle,
  model : @model.TextModel,
) -> MarkdownCommentProviderResult? {
  (self.markdown_comment_provider_result_callback)(model)
}

///|
pub fn LanguageHandle::get_language_configuration(
  self : LanguageHandle,
  language_id : String,
) -> LanguageConfiguration {
  (self.get_language_configuration_callback)(language_id)
}

///|
pub async fn LanguageHandle::hover_at(
  self : LanguageHandle,
  model : @model.TextModel,
  offset : Int,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
) -> @language.Hover? noraise {
  (self.hover_at_callback)(model, offset, token)
}

///|
/// Resolves definitions through every matching provider and concatenates their
/// live results in Monaco registry priority (selector score, then newest
/// registration). An injected runner must return only after every task has
/// terminated.
pub async fn LanguageHandle::definition_at(
  self : LanguageHandle,
  model : @model.TextModel,
  offset : Int,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
  run_tasks? : async (Array[async () -> Unit]) -> Unit = @base_common.run_async_tasks_sequentially,
) -> Array[@language.Location] noraise {
  (self.definition_at_callback)(model, offset, token, run_tasks)
}

///|
/// Reports whether the model currently has a matching live definition
/// provider registration.
pub fn LanguageHandle::has_definition_provider(
  self : LanguageHandle,
  model : @model.TextModel,
) -> Bool {
  (self.has_definition_provider_callback)(model)
}

///|
/// Default process-wide language registry used by `ViewerServices()`.
pub let languages : Languages = Languages()

///|
pub fn default_languages() -> Languages {
  languages
}

///|
/// Registers or replaces the tokenizer for `language_id` in the process-wide
/// `@syntax.tokenization_registry`, exactly monaco-editor's standalone
/// `monaco.languages.setTokensProvider` forwarding into
/// `TokenizationRegistry.register`. Tokenizers are global even for isolated
/// `Languages` instances, as in Monaco; disposing the returned handle clears
/// the provider only if it is still the active registration.
pub fn Languages::set_tokens_provider(
  _self : Languages,
  language_id : String,
  tokenizer : &@syntax.LineTokenizer,
) -> @base_common.Disposable {
  @syntax.tokenization_registry.register(language_id, tokenizer)
}

///|
/// Registers an ordered hover provider.
pub fn Languages::register_hover_provider(
  self : Languages,
  selector : @language.LanguageSelector,
  provider : &@language.HoverProvider,
) -> @base_common.Disposable {
  self.hover_provider.register(selector, provider)
}

///|
/// Registers an ordered definition provider.
pub fn Languages::register_definition_provider(
  self : Languages,
  selector : @language.LanguageSelector,
  provider : &@language.DefinitionProvider,
) -> @base_common.Disposable {
  self.definition_provider.register(selector, provider)
}

///|
/// Registers an ordered document-symbol provider.
pub fn Languages::register_document_symbol_provider(
  self : Languages,
  selector : @language.LanguageSelector,
  provider : &@language.DocumentSymbolProvider,
) -> @base_common.Disposable {
  self.document_symbol_provider.register(selector, provider)
}

///|
/// Registers an ordered whole-line Markdown-comment provider.
pub fn Languages::register_markdown_comment_provider(
  self : Languages,
  selector : @language.LanguageSelector,
  provider : &@language.MarkdownCommentProvider,
  foldable? : Bool = false,
) -> @base_common.Disposable {
  self.markdown_comment_provider.register(selector, { provider, foldable })
}

///|
/// Returns the first matching Markdown-comment provider's raw result. Provider
/// failure is logged and remains authoritative as `Some([])`.
pub fn Languages::markdown_comment_provider_result(
  self : Languages,
  model : @model.TextModel,
  log_service : @log.LogService,
) -> Array[@language.MarkdownCommentBlock]? {
  match
    self.markdown_comment_provider_result_with_log_handle(
      model,
      log_service.log_handle(),
    ) {
    Some(result) => Some(result.blocks)
    None => None
  }
}

///|
fn Languages::markdown_comment_provider_result_with_log_handle(
  self : Languages,
  model : @model.TextModel,
  log_service : @log.LogHandle,
) -> MarkdownCommentProviderResult? {
  let providers = self.markdown_comment_provider.snapshot_matching(model)
  guard providers is [captured, ..] else { return None }
  let blocks = captured.entry.provider.provider.provide_markdown_comments(model) catch {
    _ => {
      log_provider_failure(
        log_service,
        "language.markdownComments",
        model,
        captured.provider_index,
      )
      []
    }
  }
  Some({ blocks, foldable: captured.entry.provider.foldable })
}

///|
/// Returns the first non-empty hover answer in registry priority.
pub async fn Languages::hover_at(
  self : Languages,
  model : @model.TextModel,
  offset : Int,
  log_service : @log.LogService,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
) -> @language.Hover? noraise {
  self.hover_at_with_log_handle(model, offset, log_service.log_handle(), token~)
}

///|
async fn Languages::hover_at_with_log_handle(
  self : Languages,
  model : @model.TextModel,
  offset : Int,
  log_service : @log.LogHandle,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
) -> @language.Hover? noraise {
  if token.is_cancellation_requested() {
    return None
  }
  let position = model.get_position_at(offset)
  let providers = self.hover_provider.snapshot_matching(model)
  for captured in providers {
    if token.is_cancellation_requested() {
      return None
    }
    let entry = captured.entry
    if !entry.active.val {
      continue
    }
    match
      (entry.provider.provide_hover(model, position, token) catch {
        _ => {
          if !token.is_cancellation_requested() {
            log_provider_failure(
              log_service,
              "language.hover",
              model,
              captured.provider_index,
            )
          }
          None
        }
      }) {
      Some(hover) =>
        if token.is_cancellation_requested() {
          return None
        } else if entry.active.val && hover.contents.length() > 0 {
          return Some(hover)
        }
      None => ()
    }
  }
  None
}

///|
/// Returns all live definition answers concatenated in registry priority. An
/// injected runner must return only after every task has terminated.
pub async fn Languages::definition_at(
  self : Languages,
  model : @model.TextModel,
  offset : Int,
  log_service : @log.LogService,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
  run_tasks? : async (Array[async () -> Unit]) -> Unit = @base_common.run_async_tasks_sequentially,
) -> Array[@language.Location] noraise {
  self.definition_at_with_log_handle(
    model,
    offset,
    log_service.log_handle(),
    token~,
    run_tasks~,
  )
}

///|
async fn Languages::definition_at_with_log_handle(
  self : Languages,
  model : @model.TextModel,
  offset : Int,
  log_service : @log.LogHandle,
  token? : @language.CancellationToken = @language.CancellationToken::none(),
  run_tasks? : async (Array[async () -> Unit]) -> Unit = @base_common.run_async_tasks_sequentially,
) -> Array[@language.Location] noraise {
  if token.is_cancellation_requested() {
    return []
  }
  let position = model.get_position_at(offset)
  let providers = self.definition_provider.snapshot_matching(model)
  let provider_results : Array[Array[@language.Location]?] = [
    for _ in 0..<providers.length() => None
  ]
  let tasks : Array[async () -> Unit] = []
  for result_index, captured in providers {
    tasks.push(() => {
      let entry = captured.entry
      if token.is_cancellation_requested() || !entry.active.val {
        return
      }
      let result = entry.provider.provide_definition(model, position, token) catch {
        _ => {
          if !token.is_cancellation_requested() {
            log_provider_failure(
              log_service,
              "language.definition",
              model,
              captured.provider_index,
            )
          }
          []
        }
      }
      provider_results[result_index] = Some(result)
    })
  }
  run_tasks(tasks) catch {
    _ => ()
  }
  if token.is_cancellation_requested() {
    return []
  }
  let locations : Array[@language.Location] = []
  for index, result in provider_results {
    match result {
      Some(result) =>
        if providers[index].entry.active.val {
          locations.append(result)
        }
      None => ()
    }
  }
  locations
}

///|
/// Reports whether the model currently has a matching live definition
/// provider registration.
pub fn Languages::has_definition_provider(
  self : Languages,
  model : @model.TextModel,
) -> Bool {
  !self.definition_provider.snapshot_matching(model).is_empty()
}

///|
/// Concatenates document-symbol results from every provider.
pub async fn Languages::document_symbols(
  self : Languages,
  model : @model.TextModel,
  log_service : @log.LogService,
) -> Array[@language.DocumentSymbol] noraise {
  let symbols : Array[@language.DocumentSymbol] = []
  let token = @language.CancellationToken::none()
  let log_handle = log_service.log_handle()
  for captured in self.document_symbol_provider.snapshot_matching(model) {
    let entry = captured.entry
    let result = entry.provider.provide_document_symbols(model, token) catch {
      _ => {
        log_provider_failure(
          log_handle,
          "language.documentSymbols",
          model,
          captured.provider_index,
        )
        []
      }
    }
    if entry.active.val {
      symbols.append(result)
    }
  }
  symbols
}

///|
fn log_provider_failure(
  log_service : @log.LogHandle,
  category : String,
  model : @model.TextModel,
  index : Int,
) -> Unit {
  log_service.warn(category, "provider failed", details=[
    ("model", model.uri.to_string()),
    ("revision", model.revision),
    ("providerIndex", index.to_string()),
  ])
}
