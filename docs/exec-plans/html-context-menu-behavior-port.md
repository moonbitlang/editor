# HTML Editor Context Menu Behavior Port

Status: active
Date: 2026-07-30
Oracle: `vscode` revision `b18492a288de038fbc7643aae6de8247029d11bd`

## Scope and Mode

- Source:
  - `src/vs/editor/browser/controller/mouseHandler.ts:90-92,262-266`,
    `viewController.ts:406-408`,
    `viewUserInputEvents.ts:44-46`, and
    `browser/widget/codeEditor/codeEditorWidget.ts:179-180,1979-1983` for the
    DOM-to-editor context-menu event path.
  - `src/vs/editor/contrib/contextmenu/browser/contextmenu.ts:31-248,391-412`
    for target filtering, cursor placement, action collection, mouse and
    keyboard anchors, native-menu fallback, and Shift+F10.
  - `src/vs/platform/contextview/browser/contextMenuHandler.ts:42-164`,
    `src/vs/base/browser/ui/contextview/contextview.ts:184-279`, and
    `src/vs/base/browser/ui/menu/menu.ts:105-175,219-384,647-763,1019-1333`
    for one-menu lifetime, focus restoration, keyboard navigation, submenu
    interaction, viewport placement, roles, and HTML styling.
  - `src/vs/editor/contrib/gotoSymbol/browser/goToCommands.ts:44-49,274-312,
    343-374` for the `Go to Definition` item and
    `Peek > Peek Definition` submenu placement and preconditions.
- Local boundary/consumers:
  - `viewer/browser` and `internal/viewer/browser/controller` carry a public
    context-menu mouse event through the existing editor input pipeline.
  - Root `viewer` owns menu registration, availability, command dispatch,
    clicked-position policy, and the one per-Viewer contribution instance.
  - `internal/viewer/contrib/contextmenu/browser` owns only the DOM/CSS menu
    shell and its listener/focus lifetime.
  - Code presentation and semantic Markdown rows consume the same command
    menu; non-semantic Markdown and browser-owned widgets retain the native
    browser menu.
- Mode: behavior port for the whole selected cluster. Source representation,
  action-service interfaces, workbench menu services, and inheritance are not
  compatibility contracts.
- Adopted behavior/invariants:
  - a real `contextmenu` DOM event is hit-tested before Viewer policy runs;
  - eligible code text/empty-space clicks suppress the native menu, focus the
    editor, and move a single cursor only when the click is outside the current
    selection;
  - an eligible semantic Markdown click establishes the projected source
    position before evaluating definition commands;
  - action visibility is evaluated at show time, empty groups/submenus are
    removed, and separators appear only between nonempty groups;
  - the initial menu contains top-level `Go to Definition` and
    `Peek > Peek Definition`, with labels and keybinding hints owned by command
    registration rather than hard-coded in the DOM widget;
  - only one menu is visible per Viewer, showing a new menu replaces the old
    one, an action hides the menu before it runs, and Escape, Tab, outside
    primary pointer down, window blur, model/presentation change, and Viewer
    disposal close it;
  - focus enters the menu and returns to the previously focused element when
    the menu still owns focus on close;
  - the root menu and submenus fit the visual viewport and flip left/up when
    their preferred right/down placement would overflow;
  - menu/menuitem roles, focused-item state, Up/Down/Home/End, Enter/Space,
    Right/Left submenu navigation, and hover-open/close behavior are available
    without a mouse;
  - Shift+F10 opens the same menu from the current code cursor. The semantic
    Markdown keyboard bridge opens it from its latest valid projected source
    anchor when one exists.
- Out of scope:
  - Electron/native desktop menus and extension-contributed workbench actions;
  - clipboard, edit, refactor, source, navigation-history, and
    open-definition-to-side menu entries;
  - Monaco's scrollbar-specific context menu, injected-text actions, touch
    long-press behavior, and native-menu configuration toggle;
  - generalized public menu-registration API, mnemonics, icons, checked radio
    items, disabled visible items, and screen-reader announcements beyond the
    selected WAI-ARIA roles/state;
  - literal ports of `IContextMenuService`, `MenuId`, `ActionBar`, `Menu`, or
    `ContextView`.

## Representation Decision

The local command registry gains closed editor-menu identifiers, a submenu
description table, and optional immutable placement metadata on ordinary
commands. This is process-wide registration data, matching its existing
ownership. A root `ContextMenuContributionState` is the sole per-Viewer owner
of the active menu shell and source anchor. The browser package uses concrete
menu-entry values plus one action-id callback; it does not expose an open trait
because there is one renderer and no local alternative implementation.

Menu availability and command execution remain in root Viewer so Code and
semantic Markdown share policy without making the browser shell depend on
models, language features, Peek, or presentations. The browser package owns
DOM nodes, temporary listeners, timers, focus, and geometry because those are
browser resources.

## Evidence Map

| Behavior or invariant | Source | MoonBit disposition | Evidence |
|---|---|---|---|
| DOM event is hit-tested and emitted with prevent/stop control | `mouseHandler.ts:90-92,262-266` and widget event forwarding | add the omitted `onContextMenu` path beside existing mouse events | focused controller and Viewer white-box tests |
| Eligible target filtering and cursor placement | `contextmenu.ts:60-133` | Code content text/empty only; semantic Markdown uses a projected row; native widgets and ordinary Markdown fall through | Viewer white-box tests plus Chromium Code/Markdown cases |
| Live grouped command menu with empty-submenu removal | `contextmenu.ts:164-226`, `goToCommands.ts:44-49,274-312,343-374` | closed menu IDs and command placements; definition preconditions evaluated for each show | registry white-box tests and Chromium visibility cases |
| One active menu, hide-before-run, outside/blur close, focus restore | `contextMenuHandler.ts:42-164`, `contextview.ts:184-279` | concrete per-Viewer menu widget and exactly-once disposal | mounted Viewer white-box tests and Chromium lifecycle case |
| Viewport fit and submenu flip | `contextview.ts:184-279`, `menu.ts:647-763` | fixed-position root/submenu measurement and clamping | pure geometry tests plus Chromium edge-placement case |
| ARIA and keyboard/submenu navigation | `menu.ts:105-175,219-384,647-763` | menu/menuitem DOM roles and selected key transitions | mounted Viewer DOM checks plus Chromium Shift+F10 case |
| Monaco-like HTML surface | `menu.ts:1019-1333` | scoped CSS using local `--vscode-menu-*`, shadow, and corner variables | Chromium computed-style/layout assertions |
| Definition action semantics | `goToCommands.ts:274-312,343-374` | reuse existing reveal/Peek command implementations and availability | existing definition suites plus new right-click action cases |
| Scrollbar context menu | `contextmenu.ts:99-105` | N-A (no local mutable scrollbar actions); retain native browser menu | Chromium native-fallback assertion |
| Clipboard/edit/refactor and extension actions | workbench/editor menu registrations outside selected cluster | DEFERRED (requires separate command capabilities and public extension policy) | explicit scope boundary |

## Behavioral Deviations

- Monaco can disable the custom editor context menu and can render a dedicated
  scrollbar menu. The readonly Viewer has no corresponding option or mutable
  scrollbar commands, so eligible editor text always uses the HTML menu and
  scrollbars retain the browser menu.
- Monaco's full editor context menu includes actions registered by many
  services and extensions. This port intentionally renders only locally
  registered, currently available definition actions. Keyboard copy/select
  behavior remains available, but those commands are not duplicated in this
  first menu surface.
- Monaco exposes disabled actions in some menus. The selected definition
  actions disappear when their preconditions fail, so the local entry model
  does not yet include disabled rows.
- VS Code's application `IContextMenuService` serializes menus across editors.
  The reusable facade deliberately keeps no process-global browser service, so
  replacement is per independent Viewer.

## Test Matrix

- Branches/boundaries:
  - content text, content empty, selected and unselected positions, injected
    text/widget/scrollbar, ordinary Markdown, valid semantic Markdown, and
    stale Markdown projection;
  - zero/one/multiple definition providers and recursive Peek suppression;
  - center, right edge, bottom edge, and bottom-right submenu placement;
  - action, Escape, Tab, outside pointer, blur, replacement, model change,
    presentation change, and Viewer disposal;
  - mouse invocation and Shift+F10 invocation.
- Meaningful interactions:
  - menu command availability after the clicked source anchor changes;
  - submenu hover and keyboard open followed by command execution;
  - Peek action while another Peek is active;
  - focus restoration when the editor versus another element owned focus.
- Harness layers:
  - DOM-free MoonBit white-box tests for registration, grouping, command
    preconditions, dispatch, and geometry;
  - mounted Viewer white-box tests for menu registration, replacement, DOM
    roles, lifecycle, and command dispatch;
  - focused Chromium component cases for actual hit-testing, CSS, native
    fallback, edge placement, Code navigation, semantic Markdown navigation,
    and Peek.

## Exit Gate

- [x] scope, mode, and source revision recorded
- [x] representation decision reviewed
- [x] behaviors/invariants accounted for
- [x] deferrals, exclusions, and skips explicit
- [x] focused evidence green
- [ ] relevant repository checks green
