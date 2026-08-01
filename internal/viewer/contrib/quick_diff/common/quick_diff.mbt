// Port of `vscode/src/vs/workbench/contrib/scm/common/quickDiff.ts` (vscode
// checked-in submodule): the change
// classification and the quick-diff service.
//
// Parity ledger (source members):
// - `ChangeType` / `getChangeType` — PORTED.
// - `IQuickDiffService` — PORTED REDUCED as `QuickDiffService`: the viewer
//   has no SCM, so the provider registry (`QuickDiffProvider`, `QuickDiff`,
//   `addQuickDiffProvider`, `getQuickDiffs`, provider visibility toggling,
//   `onDidChangeQuickDiffProviders`) collapses to a per-resource *original
//   content* store the host fills directly (`set_original_content`), with
//   one change event. A stored original is the single implicit `primary`
//   provider; everything keyed off non-primary providers upstream
//   (secondary decorations, overlap filtering) is N-A.
// - `getChangeTypeColor` — N-A (no theme service; colors live in
//   `quick_diff.css` theme variables).
// - `compareChanges`, `getChangeHeight`, `getModifiedEndLineNumber`,
//   `isQuickDiff` — DEFERRED (consumers are the peek widget and
//   multi-provider merge, neither ported).

///|
/// `ChangeType` (`quickDiff.ts:115`).
pub(all) enum ChangeType {
  Modify
  Add
  Delete
} derive(Eq, Debug)

///|
pub impl Show for ChangeType with fn output(self, logger) {
  logger.write_string(
    match self {
      Modify => "Modify"
      Add => "Add"
      Delete => "Delete"
    },
  )
}

///|
/// `getChangeType` (`quickDiff.ts:121`).
pub fn get_change_type(change : @diff.Change) -> ChangeType {
  if change.original_end_line_number == 0 {
    Add
  } else if change.modified_end_line_number == 0 {
    Delete
  } else {
    Modify
  }
}

///|
/// The quick-diff data hub — `IQuickDiffService` reduced to a per-resource
/// original-content store (see the file header). Hosts push the baseline
/// text (e.g. the git `HEAD` version of the file) with
/// `set_original_content`; the editor contribution recomputes gutter
/// decorations from it.
pub struct QuickDiffService {
  priv originals : Map[String, String]
  priv did_change_original : @base_common.Emitter[@base_common.Uri]
}

///|
#alias(new)
pub fn QuickDiffService::QuickDiffService() -> QuickDiffService {
  { originals: Map([]), did_change_original: Emitter() }
}

///|
/// Adapts this concrete baseline store to the dependency-bottom capability
/// consumed by the viewer. The concrete service remains caller-owned.
pub fn QuickDiffService::quick_diff_handle(
  self : QuickDiffService,
) -> @quick_diff_api.QuickDiffHandle {
  QuickDiffHandle(
    get_original_content=resource => self.get_original_content(resource),
    on_did_change_original=listener => self.on_did_change_original(listener),
  )
}

///|
/// Stores (or, with `None`, clears) the original content for `resource` and
/// fires the change event.
pub fn QuickDiffService::set_original_content(
  self : QuickDiffService,
  resource : @base_common.Uri,
  content : String?,
) -> Unit {
  let key = resource.to_string()
  match content {
    Some(text) => self.originals[key] = text
    None => self.originals.remove(key)
  }
  self.did_change_original.fire(resource)
}

///|
pub fn QuickDiffService::get_original_content(
  self : QuickDiffService,
  resource : @base_common.Uri,
) -> String? {
  self.originals.get(resource.to_string())
}

///|
pub fn QuickDiffService::on_did_change_original(
  self : QuickDiffService,
  handler : (@base_common.Uri) -> Unit,
) -> @base_common.Disposable {
  self.did_change_original.event(handler)
}
