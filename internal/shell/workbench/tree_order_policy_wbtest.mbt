///|
fn entry_stat(
  name : String,
  kind : @workspace.WorkspaceEntryKind,
) -> @workspace.WorkspaceStat {
  {
    uri: try! @base_common.Uri::parse("readonly-remote://workspace/" + name),
    name,
    kind,
    children: None,
  }
}

///|
fn entry_rank(name : String, kind : @workspace.WorkspaceEntryKind) -> Int {
  workspace_entry_rank(entry_stat(name, kind))
}

///|
test "explorer order pins package overview files above the default" {
  // README leads the level, then the generated interface, then moon.pkg,
  // followed by the widget default (directories, then the remaining files).
  assert_true(
    entry_rank("README.md", File) < entry_rank("pkg.generated.mbti", File),
  )
  assert_true(
    entry_rank("pkg.generated.mbti", File) < entry_rank("moon.pkg", File),
  )
  assert_true(entry_rank("moon.pkg", File) < entry_rank("src", Directory))
  assert_eq(entry_rank("src", Directory), entry_rank("other.txt", File))

  // The pin follows the README whatever its extension, and names that merely
  // start the same way are ordinary files.
  assert_eq(entry_rank("README.mbt.md", File), entry_rank("README.md", File))
  assert_eq(entry_rank("README", File), entry_rank("README.md", File))
  assert_eq(entry_rank("READMEISH.txt", File), entry_rank("other.txt", File))
  assert_eq(entry_rank("readme.md", File), entry_rank("other.txt", File))

  // Directories keep the default rank even when named like an overview file.
  assert_eq(entry_rank("README", Directory), entry_rank("src", Directory))
}

///|
test "one explorer comparator composes pins kind and lexical name" {
  let entries = [
    entry_stat("z", File),
    entry_stat("viewer", Directory),
    entry_stat("aa", File),
    entry_stat("base", Directory),
    entry_stat("moon.pkg", File),
    entry_stat("pkg.generated.mbti", File),
    entry_stat("README.md", File),
  ]
  entries.sort_by(workspace_entry_compare)
  assert_eq(entries.map(entry => entry.name), [
    "README.md", "pkg.generated.mbti", "moon.pkg", "base", "viewer", "aa", "z",
  ])
}
