///|
test "source path local file uri remains package-internal behavior" {
  let path = match SourcePath::normalize_root_relative_path("foo.mbt") {
    ParsedSourcePath(path) => path
    SourcePathError(_) => fail("unexpected path error")
  }
  assert_eq(path.file_uri().to_string(), "file:///local/foo.mbt")
}
