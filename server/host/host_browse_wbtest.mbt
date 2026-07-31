///|
async test "host directory listing keeps directories and flags repositories" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="editor-host-browse")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.mkdir(root + "/alpha", recursive=true)
    @fs.write_file(
      root + "/alpha/moon.mod",
      "name = \"alpha\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.mkdir(root + "/beta", recursive=true)
    @fs.mkdir(root + "/gamma/.git", recursive=true)
    @fs.mkdir(root + "/.hidden", recursive=true)
    @fs.write_file(root + "/notes.txt", "text\n", create_mode=CreateOrTruncate)
    let real_root = realpath_or_normalized(root)
    match resolve_host_directory_listing(root) {
      HostDirectoryListOk(listing) => {
        assert_eq(listing.path, real_root)
        // A tmpdir is never the filesystem root, so a parent must exist.
        assert_true(listing.parent is Some(_))
        // Directories only, sorted, dot-entries dropped, files dropped.
        assert_eq(listing.entries.map(entry => entry.name), [
          "alpha", "beta", "gamma",
        ])
        assert_eq(listing.entries[0].path, real_root + "/alpha")
        assert_true(listing.entries[0].is_workspace)
        assert_false(listing.entries[1].is_workspace)
        // A `.git` marker also reads as a repository root.
        assert_true(listing.entries[2].is_workspace)
      }
      HostDirectoryListError(_, message) => fail(message)
    }
    match resolve_host_directory_listing(root + "/missing") {
      HostDirectoryListError(code, _) => assert_true(code == FileNotFound)
      HostDirectoryListOk(_) => fail("expected missing directory error")
    }
    match resolve_host_directory_listing(root + "/notes.txt") {
      HostDirectoryListError(code, _) => assert_true(code == FileNotADirectory)
      HostDirectoryListOk(_) => fail("expected non-directory error")
    }
  }
}

///|
async test "switch target validation realpaths directories and rejects others" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="editor-host-switch")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.mkdir(root + "/repo", recursive=true)
    @fs.write_file(root + "/file.txt", "x\n", create_mode=CreateOrTruncate)
    match resolve_switch_target(root + "/repo") {
      HostSwitchTarget(real) =>
        assert_eq(real, realpath_or_normalized(root + "/repo"))
      HostSwitchError(_, message) => fail(message)
    }
    match resolve_switch_target("") {
      HostSwitchError(code, _) => assert_true(code == InvalidUri)
      HostSwitchTarget(_) => fail("expected empty path rejection")
    }
    match resolve_switch_target(root + "/missing") {
      HostSwitchError(code, _) => assert_true(code == FileNotFound)
      HostSwitchTarget(_) => fail("expected missing directory rejection")
    }
    match resolve_switch_target(root + "/file.txt") {
      HostSwitchError(code, _) => assert_true(code == FileNotADirectory)
      HostSwitchTarget(_) => fail("expected non-directory rejection")
    }
  }
}

///|
test "host path helpers" {
  assert_eq(parent_host_path("/"), None)
  assert_eq(parent_host_path("/repos"), Some("/"))
  assert_eq(parent_host_path("/repos/demo"), Some("/repos"))
  assert_eq(host_basename("/repos/demo"), "demo")
  assert_eq(host_basename("/"), "/")
  assert_eq(join_host_path("/", "repos"), "/repos")
  assert_eq(join_host_path("/repos", "demo"), "/repos/demo")
}
