///| Faithful conformance port of the `TextModel.getLineIndentGuide` suite in
/// `vscode/src/vs/editor/test/common/model/textModelWithTokens.test.ts` in the
/// checked-in vscode source. Ports the
/// indent-guide subset of that file (18 cases, including the `tweaks` and
/// `issue #...` cases) against the `GuidesTextModelPart` port.
///
/// SKIPPED (out of scope, not silently dropped): the preceding bracket suites
/// (`TextModelWithTokens`, `TextModelWithTokens - bracket matching`, and
/// `TextModelWithTokens 2`) require bracket-pair and language-configuration
/// infrastructure. In `TextModelWithTokens regression tests`, only
/// `microsoft/monaco-editor#133: Error: Cannot read property 'modeId' of
/// undefined` and `issue #11856: Bracket matching does not work as expected if
/// the opening brace symbol is contained in the closing brace symbol` are
/// bracket cases. `microsoft/monaco-editor#122: Unhandled Exception: TypeError:
/// Unable to get property 'replace' of undefined or null reference` is a
/// tokenization case, while `issue #63822: Wrong embedded language detected for
/// empty lines` is embedded-language behavior; both require tokenization and
/// language support that remain outside this readonly guide port.
///
/// `tab_size` is Monaco's default (4); `indent_size` is the suite's per-case
/// argument; `off_side` is `false` (the test languages register no folding
/// rules).

///|
/// Mirrors the suite's `assertIndentGuides(lines, indentSize)`: each `lines`
/// entry is `(expectedIndentGuide, activeStart, activeEnd, activeIndent,
/// lineText)`. Compares the five fields per line scalar-wise (avoids the
/// deprecated `Show`-based `assert_eq` on arrays/tuples).
fn assert_indent_guides(
  lines : Array[(Int, Int, Int, Int, String)],
  indent_size : Int,
) -> Unit raise {
  let sb = StringBuilder::new()
  for i, l in lines {
    if i > 0 {
      sb.write_string("\n")
    }
    sb.write_string(l.4)
  }
  let snapshot = TextSnapshot::TextSnapshot(sb.to_string())
  let guides = @model.GuidesTextModelPart(
    snapshot,
    tab_size=4,
    indent_size~,
    off_side=false,
  )
  let line_count = snapshot.line_count()
  assert_eq(line_count, lines.length())
  let actual_indents = guides.get_lines_indent_guides(1, line_count)
  for line = 1; line <= line_count; line = line + 1 {
    let expected = lines[line - 1]
    let active = guides.get_active_indent_guide(line, 1, line_count)
    assert_eq(actual_indents[line - 1], expected.0)
    assert_eq(active.start_line_number, expected.1)
    assert_eq(active.end_line_number, expected.2)
    assert_eq(active.indent, expected.3)
    assert_eq(snapshot.line_text(line - 1), expected.4)
  }
}

///|
test "getLineIndentGuide one level 2" {
  assert_indent_guides(
    [
      (0, 2, 4, 1, "A"),
      (1, 2, 4, 1, "  A"),
      (1, 2, 4, 1, "  A"),
      (1, 2, 4, 1, "  A"),
    ],
    2,
  )
}

///|
test "getLineIndentGuide two levels" {
  assert_indent_guides(
    [
      (0, 2, 5, 1, "A"),
      (1, 2, 5, 1, "  A"),
      (1, 4, 5, 2, "  A"),
      (2, 4, 5, 2, "    A"),
      (2, 4, 5, 2, "    A"),
    ],
    2,
  )
}

///|
test "getLineIndentGuide three levels" {
  assert_indent_guides(
    [
      (0, 2, 4, 1, "A"),
      (1, 3, 4, 2, "  A"),
      (2, 4, 4, 3, "    A"),
      (3, 4, 4, 3, "      A"),
      (0, 5, 5, 0, "A"),
    ],
    2,
  )
}

///|
test "getLineIndentGuide decreasing indent" {
  assert_indent_guides(
    [(2, 1, 1, 2, "    A"), (1, 1, 1, 2, "  A"), (0, 1, 2, 1, "A")],
    2,
  )
}

///|
test "getLineIndentGuide Java" {
  assert_indent_guides(
    [
      (0, 2, 9, 1, "class A {"),
      (1, 3, 4, 2, "  void foo() {"),
      (2, 3, 4, 2, "    console.log(1);"),
      (2, 3, 4, 2, "    console.log(2);"),
      (1, 3, 4, 2, "  }"),
      (1, 2, 9, 1, ""),
      (1, 8, 8, 2, "  void bar() {"),
      (2, 8, 8, 2, "    console.log(3);"),
      (1, 8, 8, 2, "  }"),
      (0, 2, 9, 1, "}"),
      (0, 12, 12, 1, "interface B {"),
      (1, 12, 12, 1, "  void bar();"),
      (0, 12, 12, 1, "}"),
    ],
    2,
  )
}

///|
test "getLineIndentGuide Javadoc" {
  assert_indent_guides(
    [
      (0, 2, 3, 1, "/**"),
      (1, 2, 3, 1, " * Comment"),
      (1, 2, 3, 1, " */"),
      (0, 5, 6, 1, "class A {"),
      (1, 5, 6, 1, "  void foo() {"),
      (1, 5, 6, 1, "  }"),
      (0, 5, 6, 1, "}"),
    ],
    2,
  )
}

///|
test "getLineIndentGuide Whitespace" {
  assert_indent_guides(
    [
      (0, 2, 7, 1, "class A {"),
      (1, 2, 7, 1, ""),
      (1, 4, 5, 2, "  void foo() {"),
      (2, 4, 5, 2, "    "),
      (2, 4, 5, 2, "    return 1;"),
      (1, 4, 5, 2, "  }"),
      (1, 2, 7, 1, "      "),
      (0, 2, 7, 1, "}"),
    ],
    2,
  )
}

///|
test "getLineIndentGuide Tabs" {
  assert_indent_guides(
    [
      (0, 2, 7, 1, "class A {"),
      (1, 2, 7, 1, "\t\t"),
      (1, 4, 5, 2, "\tvoid foo() {"),
      (2, 4, 5, 2, "\t \t//hello"),
      (2, 4, 5, 2, "\t    return 2;"),
      (1, 4, 5, 2, "  \t}"),
      (1, 2, 7, 1, "      "),
      (0, 2, 7, 1, "}"),
    ],
    4,
  )
}

///|
test "getLineIndentGuide checker.ts" {
  assert_indent_guides(
    [
      (0, 1, 1, 0, "/// <reference path=\"binder.ts\"/>"),
      (0, 2, 2, 0, ""),
      (0, 3, 3, 0, "/* @internal */"),
      (0, 5, 16, 1, "namespace ts {"),
      (1, 5, 16, 1, "    let nextSymbolId = 1;"),
      (1, 5, 16, 1, "    let nextNodeId = 1;"),
      (1, 5, 16, 1, "    let nextMergeId = 1;"),
      (1, 5, 16, 1, "    let nextFlowId = 1;"),
      (1, 5, 16, 1, ""),
      (1, 11, 15, 2, "    export function getNodeId(node: Node): number {"),
      (2, 12, 13, 3, "        if (!node.id) {"),
      (3, 12, 13, 3, "            node.id = nextNodeId;"),
      (3, 12, 13, 3, "            nextNodeId++;"),
      (2, 12, 13, 3, "        }"),
      (2, 11, 15, 2, "        return node.id;"),
      (1, 11, 15, 2, "    }"),
      (0, 5, 16, 1, "}"),
    ],
    4,
  )
}

///|
test "issue #8425 - Missing indentation lines for first level indentation" {
  assert_indent_guides(
    [
      (1, 2, 3, 2, "\tindent1"),
      (2, 2, 3, 2, "\t\tindent2"),
      (2, 2, 3, 2, "\t\tindent2"),
      (1, 2, 3, 2, "\tindent1"),
    ],
    4,
  )
}

///|
test "issue #8952 - Indentation guide lines going through text on .yml file" {
  assert_indent_guides(
    [
      (0, 2, 5, 1, "properties:"),
      (1, 3, 5, 2, "    emailAddress:"),
      (2, 3, 5, 2, "        - bla"),
      (2, 5, 5, 3, "        - length:"),
      (3, 5, 5, 3, "            max: 255"),
      (0, 6, 6, 0, "getters:"),
    ],
    4,
  )
}

///|
test "issue #11892 - Indent guides look funny" {
  assert_indent_guides(
    [
      (0, 2, 7, 1, "function test(base) {"),
      (1, 3, 6, 2, "\tswitch (base) {"),
      (2, 4, 4, 3, "\t\tcase 1:"),
      (3, 4, 4, 3, "\t\t\treturn 1;"),
      (2, 6, 6, 3, "\t\tcase 2:"),
      (3, 6, 6, 3, "\t\t\treturn 2;"),
      (1, 2, 7, 1, "\t}"),
      (0, 2, 7, 1, "}"),
    ],
    4,
  )
}

///|
test "issue #12398 - Problem in indent guidelines" {
  assert_indent_guides(
    [
      (2, 2, 2, 3, "\t\t.bla"),
      (3, 2, 2, 3, "\t\t\tlabel(for)"),
      (0, 3, 3, 0, "include script"),
    ],
    4,
  )
}

///|
test "issue #49173" {
  let text = (
    [
      "class A {", "\tpublic m1(): void {", "\t}", "\tpublic m2(): void {", "\t}",
      "\tpublic m3(): void {", "\t}", "\tpublic m4(): void {", "\t}", "\tpublic m5(): void {",
      "\t}", "}",
    ] : Array[String]).join("\n")
  let snapshot = TextSnapshot::TextSnapshot(text)
  let guides = @model.GuidesTextModelPart(snapshot, tab_size=4, indent_size=4)
  let actual = guides.get_active_indent_guide(2, 4, 9)
  assert_eq(actual.start_line_number, 2)
  assert_eq(actual.end_line_number, 9)
  assert_eq(actual.indent, 1)
}

///|
test "tweaks - no active" {
  assert_indent_guides([(0, 1, 1, 0, "A"), (0, 2, 2, 0, "A")], 2)
}

///|
test "tweaks - inside scope" {
  assert_indent_guides([(0, 2, 2, 1, "A"), (1, 2, 2, 1, "  A")], 2)
}

///|
test "tweaks - scope start" {
  assert_indent_guides(
    [(0, 2, 2, 1, "A"), (1, 2, 2, 1, "  A"), (0, 2, 2, 1, "A")],
    2,
  )
}

///|
test "tweaks - empty line" {
  assert_indent_guides(
    [
      (0, 2, 4, 1, "A"),
      (1, 2, 4, 1, "  A"),
      (1, 2, 4, 1, ""),
      (1, 2, 4, 1, "  A"),
      (0, 2, 4, 1, "A"),
    ],
    2,
  )
}
