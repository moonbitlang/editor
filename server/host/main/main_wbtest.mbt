///|
test "server arguments keep loopback default" {
  let config = parse_args([])
  assert_eq(config.host, "127.0.0.1")
  assert_eq(config.port, 5173)
}

///|
test "server arguments accept wildcard host" {
  let config = parse_args([
    "--root", "/workspace", "--host", "0.0.0.0", "--port", "4173", "--asset-dir",
    "/assets", "--moon-command", "/tools/moon",
  ])
  assert_eq(config.root, "/workspace")
  assert_eq(config.host, "0.0.0.0")
  assert_eq(config.port, 4173)
  assert_eq(config.asset_dir, "/assets")
  assert_eq(config.moon_command, "/tools/moon")
}
