// Foldable API-documentation coverage lives separately from the general
// Markdown contribution tests so presentation changes can evolve independently.

///|
test "Markdown comment folded previews require provider opt-in" {
  assert_eq(markdown_comment_folded_preview("---", true), None)
  assert_eq(
    markdown_comment_folded_preview(
      (
        #|---
        #|
        #|Only summary
      ),
      true,
    ),
    None,
  )
  assert_eq(
    markdown_comment_folded_preview(
      (
        #|---
        #|
        #|# Summary
        #|
        #|More **documentation**.
        #|
        #|- detail
      ),
      true,
    ),
    Some(
      (
        #|---
        #|
        #|# Summary
      ),
    ),
  )
  assert_eq(
    markdown_comment_folded_preview(
      "---\r\n\r\nWindows summary\r\n\r\nWindows details", true,
    ),
    Some(
      (
        #|---
        #|
        #|Windows summary
      ),
    ),
  )
  assert_eq(
    markdown_comment_folded_preview(
      "---\rClassic summary\r\rClassic details", true,
    ),
    Some(
      (
        #|---
        #|
        #|Classic summary
      ),
    ),
  )
  assert_eq(
    markdown_comment_folded_preview(
      (
        #|---
        #|
        #|Summary
        #|
        #|Ordinary Markdown stays expanded.
      ),
      false,
    ),
    None,
  )
  assert_eq(
    markdown_comment_folded_preview("First line\nSecond line", true),
    None,
  )
  assert_eq(
    markdown_comment_folded_preview(
      (
        #|```mermaid
        #|flowchart LR
        #|A --> B
        #|```
      ),
      true,
    ),
    None,
  )
  assert_eq(
    markdown_comment_folded_preview(
      (
        #|
        #|
        #|Only line
        #|
        #|
      ),
      true,
    ),
    None,
  )
}

///|
test "foldable Markdown comments start collapsed and preserve state across body replacement" {
  with_markdown_contribution_viewer(
    (
      #|one
      #|two
      #|three
    ),
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

      let toggle = markdown_contribution_test_descendant_with_class(
        entry.dom.outer,
        "moonbit-viewer-markdown-comment-toggle",
      )
      markdown_contribution_test_dispatch(toggle, "click")
      assert_true(entry.fold_expanded.val)
      assert_eq(
        markdown_contribution_test_attribute(toggle, "aria-expanded"),
        "true",
      )

      provider_blocks.val = [
        markdown_contribution_block(
          1,
          2,
          (
            #|---
            #|
            #|Updated summary
            #|
            #|Updated details
          ),
        ),
      ]
      viewer.set_value(
        (
          #|ONE
          #|TWO
          #|THREE
        ),
      )
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
        1,
        2,
        (
          #|---
          #|
          #|Summary line
          #|
          #|Full documentation
        ),
      ),
    ],
    provider_foldable=true,
  )
}

///|
test "separator-only and one-line foldable Markdown comments have no control" {
  with_markdown_contribution_viewer(
    (
      #|one
      #|two
      #|three
    ),
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
      markdown_contribution_block(
        2,
        3,
        (
          #|---
          #|
          #|One line
        ),
      ),
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
        1,
        2,
        (
          #|---
          #|
          #|Ordinary summary
          #|
          #|Ordinary details
        ),
      ),
    ],
  )
}
