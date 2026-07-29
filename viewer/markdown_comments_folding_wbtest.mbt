// Foldable API-documentation coverage lives separately from the general
// Markdown contribution tests so presentation changes can evolve independently.

///|
test "Markdown comment folded previews require provider opt-in" {
  assert_eq(markdown_comment_folded_preview("---", true), None)
  assert_eq(markdown_comment_folded_preview("---\n\nOnly summary", true), None)
  assert_eq(
    markdown_comment_folded_preview(
      "---\n\n# Summary\n\nMore **documentation**.\n\n- detail", true,
    ),
    Some("---\n\n# Summary"),
  )
  assert_eq(
    markdown_comment_folded_preview(
      "---\r\n\r\nWindows summary\r\n\r\nWindows details", true,
    ),
    Some("---\n\nWindows summary"),
  )
  assert_eq(
    markdown_comment_folded_preview(
      "---\rClassic summary\r\rClassic details", true,
    ),
    Some("---\n\nClassic summary"),
  )
  assert_eq(
    markdown_comment_folded_preview(
      "---\n\nSummary\n\nOrdinary Markdown stays expanded.", false,
    ),
    None,
  )
  assert_eq(
    markdown_comment_folded_preview("First line\nSecond line", true),
    None,
  )
  assert_eq(
    markdown_comment_folded_preview(
      "```mermaid\nflowchart LR\nA --> B\n```", true,
    ),
    None,
  )
  assert_eq(markdown_comment_folded_preview("\n\nOnly line\n\n", true), None)
}

///|
test "foldable Markdown comments start collapsed and preserve state across body replacement" {
  with_markdown_contribution_viewer(
    "one\ntwo\nthree",
    (viewer, provider_blocks) => {
      let state = markdown_contribution_state(viewer)
      let entry = state.rendered["1:2"]
      guard entry.preview_rendered_markdown is Some(first_preview) else {
        fail("expected a one-line preview renderer")
      }
      assert_false(entry.fold_expanded.val)
      assert_eq(
        markdown_contribution_test_attribute(
          entry.dom.outer,
          "data-documentation-expanded",
        ),
        "false",
      )
      assert_true(
        same_mounted_test_element(first_preview.element, entry.dom.preview),
      )

      markdown_contribution_test_dispatch(entry.dom.toggle, "click")
      assert_true(entry.fold_expanded.val)
      assert_eq(
        markdown_contribution_test_attribute(entry.dom.toggle, "aria-expanded"),
        "true",
      )

      provider_blocks.val = [
        markdown_contribution_block(
          1, 2, "---\n\nUpdated summary\n\nUpdated details",
        ),
      ]
      viewer.set_value("ONE\nTWO\nTHREE")
      let updated = state.rendered["1:2"]
      assert_true(updated.fold_expanded.val)
      assert_eq(
        markdown_contribution_test_attribute(
          updated.dom.outer,
          "data-documentation-expanded",
        ),
        "true",
      )
      assert_true(updated.preview_rendered_markdown is Some(_))
    },
    provider_blocks=[
      markdown_contribution_block(
        1, 2, "---\n\nSummary line\n\nFull documentation",
      ),
    ],
    provider_foldable=true,
  )
}

///|
test "separator-only and one-line foldable Markdown comments have no control" {
  with_markdown_contribution_viewer(
    "one\ntwo\nthree",
    (viewer, _provider_blocks) => {
      let state = markdown_contribution_state(viewer)
      for key in ["1:2", "2:3"] {
        let entry = state.rendered[key]
        assert_true(entry.preview_rendered_markdown is None)
        assert_true(entry.fold_lifetime is None)
        assert_eq(
          markdown_contribution_test_attribute(
            entry.dom.outer,
            "data-documentation-foldable",
          ),
          "false",
        )
      }
    },
    provider_blocks=[
      markdown_contribution_block(1, 2, "---"),
      markdown_contribution_block(2, 3, "---\n\nOne line"),
    ],
    provider_foldable=true,
  )
}

///|
test "ordinary providers cannot opt in by beginning Markdown with a separator" {
  with_markdown_contribution_viewer(
    "one\ntwo",
    (viewer, _provider_blocks) => {
      let entry = markdown_contribution_state(viewer).rendered["1:2"]
      assert_true(entry.preview_rendered_markdown is None)
      assert_true(entry.fold_lifetime is None)
      assert_eq(
        markdown_contribution_test_attribute(
          entry.dom.outer,
          "data-documentation-foldable",
        ),
        "false",
      )
    },
    provider_blocks=[
      markdown_contribution_block(
        1, 2, "---\n\nOrdinary summary\n\nOrdinary details",
      ),
    ],
  )
}
