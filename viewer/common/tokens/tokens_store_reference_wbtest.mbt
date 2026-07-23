// Conformance disposition for:
// vscode/src/vs/editor/test/common/model/tokensStore.test.ts
// Oracle: checked-in reference tree
//
// The source file is a sparse semantic-token and incremental-edit suite. Those
// behaviors remain owned by viewer-semantic-token-acquisition-application-parity.md;
// the readonly contiguous syntactic store is covered independently in
// contiguous_tokens_store_wbtest.mbt.
//
// SKIPPED: issue #86303 - color shifting between different tokens
// SKIPPED: deleting a newline
// SKIPPED: inserting a newline
// SKIPPED: deleting a newline 2
// SKIPPED: issue #179268: a complex edit
// SKIPPED: issue #91936: Semantic token color highlighting fails on line with selected text
// SKIPPED: issue #147944: Language id "vs.editor.nullLanguage" is not configured nor known
// SKIPPED: partial tokens 1
// SKIPPED: partial tokens 2
// SKIPPED: partial tokens 3
// SKIPPED: issue #94133: Semantic colors stick around when using (only) range provider
// SKIPPED: bug
// SKIPPED: issue #95949: Identifiers are colored in bold when targetting keywords
// SKIPPED: BUG: setPartial with startLineNumber > 1 and token removal creates invalid state
// SKIPPED: BUG: setPartial with split that creates empty first piece with invalid line numbers
// SKIPPED: addSparseTokens skips overlapping semantic tokens that produce backward endOffsets
// SKIPPED: piece with startLineNumber 0 and endLineNumber -1 after encompassing deletion
