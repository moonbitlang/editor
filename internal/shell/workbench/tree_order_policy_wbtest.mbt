///|
fn entry_rank(name : String, kind : @workspace.WorkspaceEntryKind) -> Int {
  workspace_entry_rank({
    uri: try! @base_common.Uri::parse("readonly-remote://workspace/" + name),
    name,
    kind,
    children: None,
  })
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
test "explorer filename order is lexicographic rather than shortlex" {
  let root : @workspace.WorkspaceStat = {
    uri: try! @base_common.Uri::parse("readonly-remote://workspace"),
    name: "workspace",
    kind: Directory,
    children: Some([
      {
        uri: try! @base_common.Uri::parse("readonly-remote://workspace/z"),
        name: "z",
        kind: File,
        children: None,
      },
      {
        uri: try! @base_common.Uri::parse("readonly-remote://workspace/aa"),
        name: "aa",
        kind: File,
        children: None,
      },
    ]),
  }
  let ordered = order_workspace_stat_children(root)
  assert_eq(
    ordered.children.map(children => children.map(child => child.name)),
    Some(["aa", "z"]),
  )
}
