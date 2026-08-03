// Conformance port of the in-scope members' suites from
// `vs/base/test/common/extpath.test.ts` in the checked-in vscode source:
// toSlashes, getRoot, isWindowsDriveLetter. The other suites
// cover DEFERRED members (isUNC, isValidBasename, sanitizeFilePath, …).
// `toPosixPath` and the string `isEqualOrParent` have no upstream suite;
// they are pinned here from their documented arithmetic.

///|
test "toForwardSlashes" {
  assert_eq(
    to_slashes("\\\\server\\share\\some\\path"),
    "//server/share/some/path",
  )
  assert_eq(to_slashes("c:\\test"), "c:/test")
  assert_eq(to_slashes("foo\\bar"), "foo/bar")
  assert_eq(to_slashes("/user/far"), "/user/far")
}

///|
test "getRoot" {
  assert_eq(get_root("/user/far"), "/")
  assert_eq(get_root("\\\\server\\share\\some\\path"), "//server/share/")
  assert_eq(get_root("//server/share/some/path"), "//server/share/")
  assert_eq(get_root("//server/share"), "/")
  assert_eq(get_root("//server"), "/")
  assert_eq(get_root("//server//"), "/")
  assert_eq(get_root("c:/user/far"), "c:/")
  assert_eq(get_root("c:user/far"), "c:")
  assert_eq(get_root("http://www"), "")
  assert_eq(get_root("http://www/"), "http://www/")
  assert_eq(get_root("file:///foo"), "file:///")
  assert_eq(get_root("file://foo"), "")
}

///|
test "isWindowsDriveLetter" {
  assert_false(is_windows_drive_letter(0))
  assert_false(is_windows_drive_letter(-1))
  assert_true(is_windows_drive_letter('A'.to_int()))
  assert_true(is_windows_drive_letter('z'.to_int()))
}

///|
test "toPosixPath (pinned, no upstream suite)" {
  assert_eq(to_posix_path("c:\\foo\\bar"), "/c:/foo/bar")
  assert_eq(to_posix_path("c:"), "/c:")
  assert_eq(to_posix_path("c:/foo"), "/c:/foo")
  // a path that already contains '/' keeps its backslashes
  assert_eq(to_posix_path("a/b\\c"), "a/b\\c")
  assert_eq(to_posix_path("foo\\bar"), "foo/bar")
  assert_eq(to_posix_path("/usr/far"), "/usr/far")
}

///|
test "isEqualOrParent, string variant (pinned, no upstream suite)" {
  // posix-forced semantics (the shape ExtUri uses for non-file schemes)
  assert_true(
    is_equal_or_parent("/a/b/c", "/a/b", false, force_posix_semantics=true),
  )
  assert_true(
    is_equal_or_parent("/a/b/c", "/a/b/", false, force_posix_semantics=true),
  )
  assert_true(
    is_equal_or_parent("/a/b/c", "/a/b/c", false, force_posix_semantics=true),
  )
  assert_false(
    is_equal_or_parent("/a/bc", "/a/b", false, force_posix_semantics=true),
  )
  assert_false(
    is_equal_or_parent("/a/b", "/a/b/c", false, force_posix_semantics=true),
  )
  // ignore-case branch incl. the separator-boundary check
  assert_true(
    is_equal_or_parent("/a/B/c", "/A/b", true, force_posix_semantics=true),
  )
  assert_true(
    is_equal_or_parent("/a/B", "/A/b", true, force_posix_semantics=true),
  )
  assert_false(
    is_equal_or_parent("/a/Bc", "/A/b", true, force_posix_semantics=true),
  )
  // `..` normalization gate
  assert_false(
    is_equal_or_parent(
      "/home/user/projects/../../../tmp/folder",
      "/home/user/projects",
      false,
      force_posix_semantics=true,
    ),
  )
  // platform-selected separator via the D8 seam
  set_is_windows_for_testing(value=true)
  assert_true(is_equal_or_parent("c:\\a\\b", "c:\\a", false))
  assert_false(is_equal_or_parent("c:\\ab", "c:\\a", false))
  assert_true(is_equal_or_parent("c:\\A\\b", "C:\\a", true))
  set_is_windows_for_testing(value=false)
  assert_true(is_equal_or_parent("/a/b", "/a", false))
  set_is_windows_for_testing()
}
