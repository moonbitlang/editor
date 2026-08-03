///|
test "codec Debug output is the numeric-id table" {
  let codec = LanguageIdCodec()
  codec.register("rust") |> ignore
  debug_inspect(
    codec,
    content=(
      #|[
      #|  "null",
      #|  "plaintext",
      #|  "moonbit",
      #|  "javascript",
      #|  "typescript",
      #|  "json",
      #|  "rust",
      #|]
    ),
  )
}

///|
test "a fresh codec is seeded with the built-in languages" {
  let codec = LanguageIdCodec()
  debug_inspect(
    ["null", "plaintext", "moonbit", "javascript", "typescript", "json"].map(name => {
      (name, codec.encode_language_id(name))
    }),
    content=(
      #|[
      #|  ("null", 0),
      #|  ("plaintext", 1),
      #|  ("moonbit", 2),
      #|  ("javascript", 3),
      #|  ("typescript", 4),
      #|  ("json", 5),
      #|]
    ),
  )
}

///|
test "unregistered encodes to 0 until register allocates an id" {
  let codec = LanguageIdCodec()
  let before = codec.encode_language_id("rust")
  let allocated = codec.register("rust")
  let after = codec.encode_language_id("rust")
  let again = codec.register("rust")
  debug_inspect((before, allocated, after, again), content="(0, 6, 6, 6)")
}

///|
test "out-of-range ids decode to null rather than failing" {
  let codec = LanguageIdCodec()
  debug_inspect(
    (
      codec.decode_language_id(0),
      codec.decode_language_id(2),
      codec.decode_language_id(999),
      codec.decode_language_id(-1),
    ),
    content=(
      #|("null", "moonbit", "null", "null")
    ),
  )
}

///|
test "separate codecs allocate independently" {
  let first = LanguageIdCodec()
  let second = LanguageIdCodec()
  let in_first = first.register("elm")
  debug_inspect((in_first, second.encode_language_id("elm")), content="(6, 0)")
}
