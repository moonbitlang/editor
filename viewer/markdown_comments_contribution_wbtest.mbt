// Root integration proofs for the whole-line Markdown-comment contribution.
// Detection/normalization and renderer mechanics have their own package tests;
// this file exercises their composition through a real mounted or headless
// Viewer, including model projection and per-model browser ownership.

///|
fn markdown_contribution_block(
  start_line_number : Int,
  end_line_number_exclusive : Int,
  markdown : String,
) -> @language.MarkdownCommentBlock {
  {
    line_range: LineRange(start_line_number, end_line_number_exclusive),
    markdown,
  }
}

///|
priv struct MutableMarkdownContributionProvider {
  blocks : Ref[Array[@language.MarkdownCommentBlock]]
}

///|
impl @language.MarkdownCommentProvider for MutableMarkdownContributionProvider with fn provide_markdown_comments(
  self,
  _model,
) {
  self.blocks.val.copy()
}

///|
priv struct ReentrantMarkdownContributionProvider {
  blocks : Ref[Array[@language.MarkdownCommentBlock]]
  reenter : Ref[(() -> Unit)?]
}

///|
impl @language.MarkdownCommentProvider for ReentrantMarkdownContributionProvider with fn provide_markdown_comments(
  self,
  _model,
) {
  let callback = self.reenter.val
  // Clear first: the nested content/model transition invokes this provider
  // again synchronously and must terminate in that newer generation.
  self.reenter.val = None
  match callback {
    Some(run) => run()
    None => ()
  }
  self.blocks.val.copy()
}

///|
extern "js" fn install_markdown_contribution_test_dom() -> Unit =
  #| () => {
  #|   globalThis.__markdownContributionOriginalResizeObserver =
  #|     globalThis.ResizeObserver;
  #|   globalThis.__markdownContributionObservers = [];
  #|   globalThis.__markdownContributionDisconnectCount = 0;
  #|   const prototype = globalThis.Element.prototype;
  #|   const originalAppendChild = prototype.appendChild;
  #|   globalThis.__markdownContributionElementPrototype = prototype;
  #|   globalThis.__markdownContributionOriginalAppendChild = originalAppendChild;
  #|   globalThis.__markdownContributionOriginalReplaceChildren =
  #|     Object.getOwnPropertyDescriptor(prototype, "replaceChildren");
  #|   globalThis.__markdownContributionOriginalQuerySelectorAll =
  #|     Object.getOwnPropertyDescriptor(prototype, "querySelectorAll");
  #|   globalThis.__markdownContributionOriginalInnerHtml =
  #|     Object.getOwnPropertyDescriptor(prototype, "innerHTML");
  #|   globalThis.__markdownContributionOriginalOffsetHeight =
  #|     Object.getOwnPropertyDescriptor(prototype, "offsetHeight");
  #|   globalThis.__markdownContributionOriginalIsConnected =
  #|     Object.getOwnPropertyDescriptor(prototype, "isConnected");
  #|   prototype.appendChild = function(child) {
  #|     if (child?.nodeType === 11) {
  #|       for (const nested of Array.from(child.childNodes)) {
  #|         originalAppendChild.call(this, nested);
  #|       }
  #|       child.childNodes = [];
  #|       child.children = child.childNodes;
  #|       return child;
  #|     }
  #|     return originalAppendChild.call(this, child);
  #|   };
  #|   prototype.replaceChildren = function(...children) {
  #|     for (const child of Array.from(this.childNodes)) this.removeChild(child);
  #|     for (const child of children) this.appendChild(child);
  #|   };
  #|   prototype.querySelectorAll = function(_selector) { return []; };
  #|   const originalCreateElement = document.createElement;
  #|   globalThis.__markdownContributionDocument = document;
  #|   globalThis.__markdownContributionOriginalCreateElement =
  #|     originalCreateElement;
  #|   document.createElement = (tag) => {
  #|     const element = originalCreateElement(tag);
  #|     if (String(tag).toLowerCase() === "template") {
  #|       const content = originalCreateElement("document-fragment");
  #|       content.nodeType = 11;
  #|       content.nodeName = "#document-fragment";
  #|       element.content = content;
  #|     }
  #|     return element;
  #|   };
  #|   Object.defineProperty(prototype, "innerHTML", {
  #|     configurable: true,
  #|     get() { return this.__markdownContributionInnerHtml ?? ""; },
  #|     set(value) {
  #|       this.__markdownContributionInnerHtml = String(value);
  #|       (this.content || this).replaceChildren();
  #|     },
  #|   });
  #|   Object.defineProperty(prototype, "offsetHeight", {
  #|     configurable: true,
  #|     get() { return this.__markdownContributionOffsetHeight ?? 0; },
  #|   });
  #|   Object.defineProperty(prototype, "isConnected", {
  #|     configurable: true,
  #|     get() { return this.__markdownContributionConnected !== false; },
  #|   });
  #|   globalThis.ResizeObserver = class {
  #|     constructor(callback) {
  #|       this.callback = callback;
  #|       this.target = null;
  #|       this.active = true;
  #|       globalThis.__markdownContributionObservers.push(this);
  #|     }
  #|     observe(target) { this.target = target; }
  #|     disconnect() {
  #|       if (!this.active) return;
  #|       this.active = false;
  #|       globalThis.__markdownContributionDisconnectCount += 1;
  #|     }
  #|   };
  #| }

///|
extern "js" fn restore_markdown_contribution_test_dom() -> Unit =
  #| () => {
  #|   const prototype = globalThis.__markdownContributionElementPrototype;
  #|   const restoreDescriptor = (name, descriptor) => {
  #|     if (descriptor === undefined) delete prototype[name];
  #|     else Object.defineProperty(prototype, name, descriptor);
  #|   };
  #|   prototype.appendChild =
  #|     globalThis.__markdownContributionOriginalAppendChild;
  #|   restoreDescriptor(
  #|     "replaceChildren",
  #|     globalThis.__markdownContributionOriginalReplaceChildren,
  #|   );
  #|   restoreDescriptor(
  #|     "querySelectorAll",
  #|     globalThis.__markdownContributionOriginalQuerySelectorAll,
  #|   );
  #|   restoreDescriptor(
  #|     "innerHTML",
  #|     globalThis.__markdownContributionOriginalInnerHtml,
  #|   );
  #|   restoreDescriptor(
  #|     "offsetHeight",
  #|     globalThis.__markdownContributionOriginalOffsetHeight,
  #|   );
  #|   restoreDescriptor(
  #|     "isConnected",
  #|     globalThis.__markdownContributionOriginalIsConnected,
  #|   );
  #|   globalThis.__markdownContributionDocument.createElement =
  #|     globalThis.__markdownContributionOriginalCreateElement;
  #|   const original = globalThis.__markdownContributionOriginalResizeObserver;
  #|   if (original === undefined) delete globalThis.ResizeObserver;
  #|   else globalThis.ResizeObserver = original;
  #|   delete globalThis.__markdownContributionOriginalResizeObserver;
  #|   delete globalThis.__markdownContributionElementPrototype;
  #|   delete globalThis.__markdownContributionOriginalAppendChild;
  #|   delete globalThis.__markdownContributionOriginalReplaceChildren;
  #|   delete globalThis.__markdownContributionOriginalQuerySelectorAll;
  #|   delete globalThis.__markdownContributionOriginalInnerHtml;
  #|   delete globalThis.__markdownContributionOriginalOffsetHeight;
  #|   delete globalThis.__markdownContributionOriginalIsConnected;
  #|   delete globalThis.__markdownContributionDocument;
  #|   delete globalThis.__markdownContributionOriginalCreateElement;
  #|   delete globalThis.__markdownContributionObservers;
  #|   delete globalThis.__markdownContributionDisconnectCount;
  #| }

///|
extern "js" fn markdown_contribution_test_attribute(
  element : @rdom.Element,
  name : String,
) -> String = "(element, name) => element.getAttribute(name) ?? ''"

///|
extern "js" fn markdown_contribution_test_is_detached(
  element : @rdom.Element,
) -> Bool = "element => element.parentNode === null"

///|
extern "js" fn markdown_contribution_test_parent(
  element : @rdom.Element,
) -> @rdom.Element = "element => element.parentNode"

///|
extern "js" fn markdown_contribution_test_disconnect_count() -> Int = "() => globalThis.__markdownContributionDisconnectCount"

///|
extern "js" fn markdown_contribution_test_trigger_resize(
  target : @rdom.Element,
  height : Int,
  connected : Bool,
) -> Unit =
  #| (target, height, connected) => {
  #|   target.__markdownContributionOffsetHeight = height;
  #|   target.__markdownContributionConnected = connected;
  #|   for (const observer of globalThis.__markdownContributionObservers) {
  #|     if (observer.active && observer.target === target) observer.callback([]);
  #|   }
  #| }

///|
fn with_markdown_contribution_viewer(
  text : String,
  body : (Viewer, Ref[Array[@language.MarkdownCommentBlock]]) -> Unit raise,
  provider_blocks? : Array[@language.MarkdownCommentBlock],
  configure_line_comments? : Bool = false,
) -> Unit raise {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  install_markdown_contribution_test_dom()
  defer restore_markdown_contribution_test_dom()
  let registry = @languages.Languages()
  if configure_line_comments {
    registry.set_language_configuration("plaintext", {
      comments: Some({
        line_comment: Some(LineCommentRule("//")),
        block_comment: None,
      }),
      folding_rules: None,
    })
  }
  let log_service = @log.LogService()
  let blocks = Ref(provider_blocks.unwrap_or([]))
  let registration = match provider_blocks {
    Some(_) =>
      Some(
        registry.register_markdown_comment_provider(LanguageId("plaintext"), MutableMarkdownContributionProvider::{
          blocks,
        }),
      )
    None => None
  }
  defer (match registration {
    Some(disposable) => disposable.dispose()
    None => ()
  })
  let services = ViewerServices(
    languages=registry.language_handle(log_service.log_handle()),
    log_service=log_service.log_handle(),
  )
  defer services.dispose()
  let model = test_model(text)
  defer model.dispose()
  let viewer = Viewer::Viewer(services~)
  defer viewer.dispose()
  let host = @rdom.document().create_element("div")
  viewer.attach(host)
  viewer.set_model(Some(model))
  body(viewer, blocks)
}

///|
fn markdown_contribution_state(
  viewer : Viewer,
) -> MarkdownCommentContributionState {
  viewer.markdown_comment_contribution().unwrap()
}

///|
test "Markdown comments replace start middle EOF blocks while preserving model truth" {
  let source = "one\ntwo\nthree\nfour\nfive\nsix"
  let blocks = [
    markdown_contribution_block(1, 2, "# start"),
    markdown_contribution_block(3, 5, "middle"),
    markdown_contribution_block(6, 7, "EOF"),
  ]
  with_markdown_contribution_viewer(
    source,
    (viewer, _provider_blocks) => {
      let state = markdown_contribution_state(viewer)
      assert_eq(state.rendered.length(), 3)
      assert_true(state.rendered.contains("1:2"))
      assert_true(state.rendered.contains("3:5"))
      assert_true(state.rendered.contains("6:7"))
      for key in ["1:2", "3:5", "6:7"] {
        let entry = state.rendered[key]
        assert_true(entry.zone_id != "")
        assert_eq(entry.zone.suppress_mouse_down, Some(false))
        assert_eq(
          entry.zone.ignore_hidden_area_source,
          Some(markdown_comment_hidden_source),
        )
        assert_true(
          same_mounted_test_element(
            entry.zone.dom_node,
            markdown_contribution_test_parent(entry.rendered_markdown.element),
          ),
        )
      }
      assert_eq(state.rendered["1:2"].zone.after_line_number, 1)
      assert_eq(state.rendered["3:5"].zone.after_line_number, 4)
      assert_eq(state.rendered["6:7"].zone.after_line_number, 6)
      assert_eq(
        markdown_contribution_test_attribute(
          state.rendered["1:2"].zone.dom_node,
          "data-start-line",
        ),
        "1",
      )
      assert_true(
        viewer.test_view_model().get_hidden_areas() ==
        [Range(1, 1, 1, 1), Range(3, 1, 4, 1), Range(6, 1, 6, 1)],
      )
      assert_eq(viewer.test_view_model().line_count(), 2)
      assert_eq(viewer.test_view_model().get_whitespaces().length(), 3)
      assert_eq(viewer.get_value(), source)
      assert_eq(viewer.get_model().unwrap().get_line_content(3), "three")
    },
    provider_blocks=blocks,
  )
}

///|
fn assert_markdown_contribution_visible_fallback(viewer : Viewer) -> Unit raise {
  assert_eq(markdown_contribution_state(viewer).rendered.length(), 0)
  assert_true(viewer.test_view_model().get_hidden_areas() == [])
  assert_eq(viewer.test_view_model().get_whitespaces().length(), 0)
  assert_eq(
    viewer.test_view_model().line_count(),
    viewer.get_model().unwrap().get_line_count(),
  )
}

///|
test "Markdown comment fallbacks leave source visible for absent empty invalid and all-line results" {
  // No provider and no language comment configuration.
  with_markdown_contribution_viewer("// doc\ncode", (viewer, _) => {
    assert_markdown_contribution_visible_fallback(viewer)
  })

  // An authoritative empty provider suppresses the available configuration
  // fallback rather than hiding the detected comment.
  with_markdown_contribution_viewer(
    "// doc\ncode",
    (viewer, _) => assert_markdown_contribution_visible_fallback(viewer),
    provider_blocks=[],
    configure_line_comments=true,
  )

  // Exact-empty Markdown is discarded at the normalized contribution seam.
  with_markdown_contribution_viewer(
    "comment\ncode",
    (viewer, _) => assert_markdown_contribution_visible_fallback(viewer),
    provider_blocks=[markdown_contribution_block(1, 2, "")],
  )

  // Invalid ranges cannot create a zone or hidden source.
  with_markdown_contribution_viewer(
    "one\ntwo\nthree",
    (viewer, _) => assert_markdown_contribution_visible_fallback(viewer),
    provider_blocks=[
      markdown_contribution_block(0, 2, "before model"),
      markdown_contribution_block(3, 5, "past model"),
      markdown_contribution_block(2, 2, "empty range"),
    ],
  )

  // Several individually valid blocks that cover every model line trigger
  // the all-lines safeguard as one normalized result.
  with_markdown_contribution_viewer(
    "one\ntwo\nthree",
    (viewer, _) => assert_markdown_contribution_visible_fallback(viewer),
    provider_blocks=[
      markdown_contribution_block(1, 2, "first"),
      markdown_contribution_block(2, 4, "rest"),
    ],
  )
}

///|
test "same-key Markdown update retains the ViewZone and target identities" {
  with_markdown_contribution_viewer(
    "one\ntwo\nthree\nfour\nfive",
    (viewer, provider_blocks) => {
      let state = markdown_contribution_state(viewer)
      let first = state.rendered["2:4"]
      let first_outer = first.zone.dom_node
      let first_target = first.rendered_markdown.element
      let first_zone_id = first.zone_id
      let first_whitespace_id = viewer.test_view_model().get_whitespaces()[0].id
      assert_eq(markdown_contribution_test_disconnect_count(), 0)

      provider_blocks.val = [
        markdown_contribution_block(2, 4, "updated **body**"),
      ]
      viewer.set_value("ONE\nTWO\nTHREE\nFOUR\nFIVE")

      let updated = state.rendered["2:4"]
      assert_eq(state.rendered.length(), 1)
      assert_eq(updated.block.markdown, "updated **body**")
      assert_eq(updated.zone_id, first_zone_id)
      assert_true(same_mounted_test_element(updated.zone.dom_node, first_outer))
      assert_true(
        same_mounted_test_element(
          updated.rendered_markdown.element,
          first_target,
        ),
      )
      assert_eq(
        viewer.test_view_model().get_whitespaces()[0].id,
        first_whitespace_id,
      )
      assert_eq(markdown_contribution_test_disconnect_count(), 0)
      assert_true(
        viewer.test_view_model().get_hidden_areas() == [Range(2, 1, 3, 1)],
      )
    },
    provider_blocks=[markdown_contribution_block(2, 4, "original body")],
  )
}

///|
test "Markdown comment reconciliation adds removes and moves blocks by stable range key" {
  with_markdown_contribution_viewer(
    "one\ntwo\nthree\nfour\nfive\nsix",
    (viewer, provider_blocks) => {
      let state = markdown_contribution_state(viewer)
      let removed_outer = state.rendered["1:2"].zone.dom_node
      let retained_outer = state.rendered["3:4"].zone.dom_node
      provider_blocks.val = [
        // The first block moved, and therefore owns a new stable key/zone.
        markdown_contribution_block(2, 3, "moved"),
        markdown_contribution_block(3, 4, "retained"),
        markdown_contribution_block(5, 6, "added"),
      ]
      viewer.set_value("ONE\nTWO\nTHREE\nFOUR\nFIVE\nSIX")

      assert_eq(state.rendered.length(), 3)
      assert_false(state.rendered.contains("1:2"))
      assert_true(state.rendered.contains("2:3"))
      assert_true(state.rendered.contains("3:4"))
      assert_true(state.rendered.contains("5:6"))
      assert_true(markdown_contribution_test_is_detached(removed_outer))
      assert_true(
        same_mounted_test_element(
          state.rendered["3:4"].zone.dom_node,
          retained_outer,
        ),
      )
      assert_false(
        same_mounted_test_element(
          state.rendered["2:3"].zone.dom_node,
          removed_outer,
        ),
      )
      assert_eq(markdown_contribution_test_disconnect_count(), 1)
      assert_true(
        viewer.test_view_model().get_hidden_areas() ==
        [Range(2, 1, 3, 1), Range(5, 1, 5, 1)],
      )
      assert_eq(viewer.test_view_model().get_whitespaces().length(), 3)
    },
    provider_blocks=[
      markdown_contribution_block(1, 2, "removed"),
      markdown_contribution_block(3, 4, "retained"),
    ],
  )
}

///|
test "reentrant ViewZone events leave nested flush and replacement projections current" {
  // A ViewZone listener flushes the same model while the outer refresh has
  // installed its temporary zone but has not yet installed its hidden source.
  with_markdown_contribution_viewer(
    "one\ntwo\nthree\nfour\nfive",
    (viewer, provider_blocks) => {
      let state = markdown_contribution_state(viewer)
      provider_blocks.val = [
        markdown_contribution_block(2, 3, "outer generation"),
      ]
      let reentered = Ref(false)
      let saw_outer_zone = Ref(false)
      let mut zone_events = 0
      let listener = viewer.on_did_change_view_zones(() => {
        zone_events += 1
        if !reentered.val {
          reentered.val = true
          saw_outer_zone.val = state.rendered.contains("2:3")
          provider_blocks.val = [
            markdown_contribution_block(4, 5, "nested generation"),
          ]
          viewer.set_value(
            "nested one\nnested two\nnested three\nnested four\nnested five",
          )
        }
      })
      defer listener.dispose()

      viewer.refresh_markdown_comments(force_update=false)

      assert_true(reentered.val)
      assert_true(saw_outer_zone.val)
      assert_true(zone_events >= 2)
      assert_eq(state.rendered.length(), 1)
      assert_false(state.rendered.contains("2:3"))
      assert_true(state.rendered.contains("4:5"))
      assert_eq(state.rendered["4:5"].block.markdown, "nested generation")
      assert_true(
        viewer.test_view_model().get_hidden_areas() == [Range(4, 1, 4, 1)],
      )
      assert_eq(viewer.test_view_model().get_whitespaces().length(), 1)
      assert_eq(viewer.test_view_model().line_count(), 4)
      assert_eq(
        viewer.get_value(),
        "nested one\nnested two\nnested three\nnested four\nnested five",
      )
      assert_eq(viewer.get_model().unwrap().get_line_content(4), "nested four")
    },
    provider_blocks=[markdown_contribution_block(1, 2, "initial")],
  )

  // The same public event may replace the model completely. The outgoing
  // ViewModel must be cleaned, and only the replacement model's newer range
  // may survive after the stale outer stack resumes.
  with_markdown_contribution_viewer(
    "old one\nold two\nold three\nold four\nold five",
    (viewer, provider_blocks) => {
      let state = markdown_contribution_state(viewer)
      let old_view_model = viewer.test_view_model()
      let replacement = test_model(
        "new one\nnew two\nnew three\nnew four\nnew five",
      )
      provider_blocks.val = [
        markdown_contribution_block(2, 3, "stale old-model range"),
      ]
      let reentered = Ref(false)
      let saw_outer_zone = Ref(false)
      let listener = viewer.on_did_change_view_zones(() => {
        if !reentered.val {
          reentered.val = true
          saw_outer_zone.val = state.rendered.contains("2:3")
          provider_blocks.val = [
            markdown_contribution_block(4, 5, "replacement range"),
          ]
          viewer.set_model(Some(replacement))
        }
      })

      viewer.refresh_markdown_comments(force_update=false)

      assert_true(reentered.val)
      assert_true(saw_outer_zone.val)
      assert_true(viewer.get_model().unwrap().same(replacement))
      assert_true(old_view_model.get_hidden_areas() == [])
      assert_eq(old_view_model.get_whitespaces().length(), 0)
      assert_eq(state.rendered.length(), 1)
      assert_false(state.rendered.contains("2:3"))
      assert_true(state.rendered.contains("4:5"))
      assert_eq(state.rendered["4:5"].block.markdown, "replacement range")
      assert_true(
        viewer.test_view_model().get_hidden_areas() == [Range(4, 1, 4, 1)],
      )
      assert_eq(viewer.test_view_model().get_whitespaces().length(), 1)
      assert_eq(
        viewer.get_value(),
        "new one\nnew two\nnew three\nnew four\nnew five",
      )

      // End the replacement's ownership before disposing the caller-owned
      // model. The already-fired listener stays one-shot through `reentered`.
      viewer.set_model(None)
      listener.dispose()
      replacement.dispose()
    },
    provider_blocks=[markdown_contribution_block(1, 2, "initial")],
  )
}

///|
test "reentrant provider reserves the nested content generation before returning" {
  install_mounted_test_browser()
  defer restore_mounted_test_browser()
  install_markdown_contribution_test_dom()
  defer restore_markdown_contribution_test_dom()
  let registry = @languages.Languages()
  let log_service = @log.LogService()
  let provider_blocks = Ref([markdown_contribution_block(1, 2, "initial")])
  let reenter : Ref[(() -> Unit)?] = Ref(None)
  let registration = registry.register_markdown_comment_provider(
    LanguageId("plaintext"),
    ReentrantMarkdownContributionProvider::{ blocks: provider_blocks, reenter },
  )
  defer registration.dispose()
  let services = ViewerServices(
    languages=registry.language_handle(log_service.log_handle()),
    log_service=log_service.log_handle(),
  )
  defer services.dispose()
  let model = test_model("one\ntwo\nthree\nfour\nfive")
  defer model.dispose()
  let viewer = Viewer::Viewer(services~)
  defer viewer.dispose()
  let host = @rdom.document().create_element("div")
  viewer.attach(host)
  viewer.set_model(Some(model))
  let state = markdown_contribution_state(viewer)
  let outer_generation = state.generation + 1
  provider_blocks.val = [
    markdown_contribution_block(2, 3, "outer provider result"),
  ]
  reenter.val = Some(() => {
    provider_blocks.val = [
      markdown_contribution_block(4, 5, "nested provider result"),
    ]
    viewer.set_value(
      "provider one\nprovider two\nprovider three\nprovider four\nprovider five",
    )
  })

  viewer.refresh_markdown_comments(force_update=false)

  assert_true(state.generation > outer_generation)
  assert_true(reenter.val is None)
  assert_eq(state.rendered.length(), 1)
  assert_false(state.rendered.contains("2:3"))
  assert_true(state.rendered.contains("4:5"))
  assert_eq(state.rendered["4:5"].block.markdown, "nested provider result")
  assert_true(
    viewer.test_view_model().get_hidden_areas() == [Range(4, 1, 4, 1)],
  )
  assert_eq(viewer.test_view_model().get_whitespaces().length(), 1)
  assert_eq(
    viewer.get_value(),
    "provider one\nprovider two\nprovider three\nprovider four\nprovider five",
  )
}

///|
test "Markdown comment model detach replacement reattach and Viewer disposal release ownership" {
  with_markdown_contribution_viewer(
    "one\ntwo\nthree",
    (viewer, _provider_blocks) => {
      let state = markdown_contribution_state(viewer)
      let first_view_model = viewer.test_view_model()
      let first_outer = state.rendered["2:3"].zone.dom_node
      viewer.set_model(None)
      assert_eq(state.rendered.length(), 0)
      assert_true(first_view_model.get_hidden_areas() == [])
      assert_eq(first_view_model.get_whitespaces().length(), 0)
      assert_true(markdown_contribution_test_is_detached(first_outer))
      assert_eq(markdown_contribution_test_disconnect_count(), 1)

      // Reattach after the explicit no-model state creates fresh per-model
      // ViewZone/DOM ownership under the same Viewer-lived contribution.
      let second_model = test_model("second one\nsecond two\nsecond three")
      defer second_model.dispose()
      viewer.set_model(Some(second_model))
      let second_view_model = viewer.test_view_model()
      let second_outer = state.rendered["2:3"].zone.dom_node
      assert_eq(state.rendered.length(), 1)
      assert_false(same_mounted_test_element(first_outer, second_outer))
      assert_true(second_view_model.get_hidden_areas() == [Range(2, 1, 2, 1)])

      // A direct replacement clears the outgoing source/resources before
      // installing a third model's fresh entry.
      let third_model = test_model("third one\nthird two\nthird three")
      defer third_model.dispose()
      viewer.set_model(Some(third_model))
      let third_view_model = viewer.test_view_model()
      let third_outer = state.rendered["2:3"].zone.dom_node
      assert_true(second_view_model.get_hidden_areas() == [])
      assert_eq(second_view_model.get_whitespaces().length(), 0)
      assert_true(markdown_contribution_test_is_detached(second_outer))
      assert_false(same_mounted_test_element(second_outer, third_outer))
      assert_eq(markdown_contribution_test_disconnect_count(), 2)

      viewer.dispose()
      assert_eq(state.rendered.length(), 0)
      assert_true(third_view_model.get_hidden_areas() == [])
      assert_eq(third_view_model.get_whitespaces().length(), 0)
      assert_true(markdown_contribution_test_is_detached(third_outer))
      assert_eq(markdown_contribution_test_disconnect_count(), 3)
      assert_true(viewer.markdown_comment_contribution() is None)
    },
    provider_blocks=[markdown_contribution_block(2, 3, "comment")],
  )
}

///|
test "headless Markdown contribution never hides source without replacement DOM" {
  let registry = @languages.Languages()
  let log_service = @log.LogService()
  let provider_blocks = Ref([
    markdown_contribution_block(2, 4, "headless comment"),
  ])
  let registration = registry.register_markdown_comment_provider(
    LanguageId("plaintext"),
    MutableMarkdownContributionProvider::{ blocks: provider_blocks },
  )
  defer registration.dispose()
  let services = ViewerServices(
    languages=registry.language_handle(log_service.log_handle()),
    log_service=log_service.log_handle(),
  )
  defer services.dispose()
  let model = test_model("one\ntwo\nthree\nfour\nfive")
  defer model.dispose()
  let viewer = Viewer::Viewer(services~)
  defer viewer.dispose()
  viewer.set_model(Some(model))
  assert_eq(markdown_contribution_state(viewer).rendered.length(), 0)
  assert_true(viewer.test_view_model().get_hidden_areas() == [])
  assert_eq(viewer.test_view_model().line_count(), 5)
  assert_eq(viewer.get_value(), "one\ntwo\nthree\nfour\nfive")

  provider_blocks.val = [markdown_contribution_block(1, 2, "changed")]
  viewer.set_value("ONE\nTWO\nTHREE\nFOUR\nFIVE")
  assert_eq(markdown_contribution_state(viewer).rendered.length(), 0)
  assert_true(viewer.test_view_model().get_hidden_areas() == [])
  assert_eq(viewer.test_view_model().line_count(), 5)
}

///|
test "Markdown comment height callbacks ignore zero disconnected stale and disposed observations" {
  with_markdown_contribution_viewer(
    "one\ntwo\nthree\nfour",
    (viewer, provider_blocks) => {
      let state = markdown_contribution_state(viewer)
      let entry = state.rendered["2:3"]
      let target = entry.rendered_markdown.element
      // Discard the fixture's ordinary pending paint. Executing a live Viewer
      // paint would enter font measurement, which is intentionally outside
      // this narrow observer/generation test DOM.
      viewer.cancel_render_frame()
      if mounted_test_frame_count() > 0 {
        run_one_mounted_test_frame()
      }

      markdown_contribution_test_trigger_resize(target, 0, true)
      run_one_mounted_test_frame()
      assert_eq(entry.measured_height, 0.0)
      assert_true(entry.zone.height_in_px is None)

      markdown_contribution_test_trigger_resize(target, 30, false)
      run_one_mounted_test_frame()
      assert_eq(entry.measured_height, 0.0)
      assert_true(entry.zone.height_in_px is None)

      viewer.apply_markdown_comment_height(
        state,
        "2:3",
        entry.zone_id,
        entry.generation,
        24,
      )
      assert_eq(entry.measured_height, 24.0)
      assert_eq(entry.zone.height_in_px, Some(24.0))
      assert_eq(viewer.test_view_model().get_whitespaces()[0].height, 24)
      viewer.cancel_render_frame()
      if mounted_test_frame_count() > 0 {
        run_one_mounted_test_frame()
      }

      viewer.apply_markdown_comment_height(
        state,
        "2:3",
        entry.zone_id,
        Ref(state.generation - 1),
        40,
      )
      viewer.apply_markdown_comment_height(
        state,
        "2:3",
        entry.zone_id + "-stale",
        entry.generation,
        40,
      )
      assert_eq(entry.measured_height, 24.0)
      assert_eq(entry.zone.height_in_px, Some(24.0))

      provider_blocks.val = []
      viewer.set_value("ONE\nTWO\nTHREE\nFOUR")
      viewer.cancel_render_frame()
      if mounted_test_frame_count() > 0 {
        run_one_mounted_test_frame()
      }
      assert_eq(state.rendered.length(), 0)
      assert_eq(markdown_contribution_test_disconnect_count(), 1)
      assert_eq(mounted_test_frame_count(), 0)
      markdown_contribution_test_trigger_resize(target, 50, true)
      assert_eq(mounted_test_frame_count(), 0)
    },
    provider_blocks=[markdown_contribution_block(2, 3, "comment")],
  )
}
