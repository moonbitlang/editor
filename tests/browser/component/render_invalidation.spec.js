import { expect, test } from '../support/test.js';

const editorSelector =
  '.render-invalidation-host > .monaco-editor.readonly-editor';
const contentHighlightSelector =
  '.render-invalidation-host .view-overlays .current-line';
const marginHighlightSelector =
  '.render-invalidation-host .margin-view-overlays .current-line-margin';
const visibleHoverSelector =
  '.render-invalidation-host [data-content-widget="editor.contrib.resizableContentHoverWidget"] .monaco-hover:not(.hidden)';
const contentWidgetSelector =
  '.render-invalidation-host [data-content-widget="editor.contrib.resizableContentHoverWidget"]';

async function settle(page) {
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      ),
  );
}

async function mountFixture(page) {
  await page.goto('/browser-tests/component.html?renderInvalidation=1');
  await page.waitForFunction(() => Boolean(globalThis.__renderInvalidationControls));
  await expect(page.locator(editorSelector)).toContainText('prefix anchor target');
  await expect(
    page.locator('.render-invalidation-host .cdr.squiggly-warning'),
  ).toHaveCount(1);
  await settle(page);
}

async function update(page, method, value) {
  await page.evaluate(
    ([name, nextValue]) =>
      globalThis.__renderInvalidationControls[name](nextValue),
    [method, value],
  );
  await settle(page);
}

async function probeUpdate(page, callback) {
  await page.evaluate(() => globalThis.__renderInvalidationControls.start_probe());
  await callback();
  // Do not use requestAnimationFrame to observe this interval: the fixture
  // counts every scheduled frame, including frames requested by test code.
  await page.waitForTimeout(120);
  return page.evaluate(() =>
    globalThis.__renderInvalidationControls.stop_probe(),
  );
}

async function pointForText(page, needle) {
  const point = await page
    .locator('.render-invalidation-host .view-lines')
    .evaluate((root, text) => {
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const index = node.textContent.indexOf(text);
        if (index < 0) continue;
        const range = document.createRange();
        range.setStart(node, index);
        range.setEnd(node, index + text.length);
        const rect = range.getBoundingClientRect();
        return {
          x: rect.x + rect.width / 2,
          y: rect.y + rect.height / 2,
        };
      }
      return null;
    }, needle);
  expect(point).not.toBeNull();
  return point;
}

test('runtime whitespace and control-character options replace rendered DOM immediately', async ({
  page,
}) => {
  await mountFixture(page);
  const whitespace = page.locator('.render-invalidation-host .view-line .mtkw');
  const control = page.locator(
    '.render-invalidation-host .view-line .mtkcontrol',
  );

  await expect(whitespace).toHaveCount(0);
  await expect(control).toHaveCount(0);

  await update(page, 'set_whitespace', 'all');
  await expect(whitespace.first()).toBeVisible();
  await update(page, 'set_whitespace', 'none');
  await expect(whitespace).toHaveCount(0);

  await update(page, 'set_control', true);
  await expect(control).toHaveCount(1);
  await expect(control).toHaveText('[U+202E]');
  await update(page, 'set_control', false);
  await expect(control).toHaveCount(0);
  await expect(page.locator(editorSelector)).not.toContainText('[U+202E]');
});

test('same-frame A to B to A remains an eventful frame and converges to the final snapshot', async ({
  page,
}) => {
  await mountFixture(page);
  const whitespace = page.locator('.render-invalidation-host .view-line .mtkw');
  await expect(whitespace).toHaveCount(0);
  const roundTrip = await probeUpdate(page, () =>
    page.evaluate(() =>
      globalThis.__renderInvalidationControls.whitespace_round_trip(),
    ),
  );
  expect(roundTrip.frames).toBe(1);
  await expect(whitespace).toHaveCount(0);
  const converged = await probeUpdate(page, () => Promise.resolve());
  expect(converged.frames).toBe(0);
  expect(converged.writes).toEqual([]);
});

test('dynamic tab size and wrap mapping repaint without unrelated input', async ({
  page,
}) => {
  await mountFixture(page);
  const beforeTab = await pointForText(page, 'tab-stop');
  const tabChanged = await probeUpdate(page, () =>
    page.evaluate(() =>
      globalThis.__renderInvalidationControls.set_tab_size(4),
    ),
  );
  const afterTab = await pointForText(page, 'tab-stop');
  expect(tabChanged.frames).toBe(1);
  expect(afterTab.x).toBeGreaterThan(beforeTab.x + 5);

  const physicalLines = 4;
  await expect(page.locator('.render-invalidation-host .view-line')).toHaveCount(
    physicalLines,
  );
  const wrapped = await probeUpdate(page, () =>
    page.evaluate(() => globalThis.__renderInvalidationControls.set_wrap(true)),
  );
  expect(wrapped.frames).toBe(1);
  expect(
    await page.locator('.render-invalidation-host .view-line').count(),
  ).toBeGreaterThan(physicalLines);
  const unwrapped = await probeUpdate(page, () =>
    page.evaluate(() => globalThis.__renderInvalidationControls.set_wrap(false)),
  );
  expect(unwrapped.frames).toBe(1);
  await expect(page.locator('.render-invalidation-host .view-line')).toHaveCount(
    physicalLines,
  );
});

test('visible content widget reprojects its retained anchor on a real wrap mapping', async ({
  page,
}) => {
  await mountFixture(page);
  // Keep the hover on the short final model line; wrapping the long preceding
  // line shifts its view-line anchor without moving the model position.
  await page.evaluate(() =>
    globalThis.__renderInvalidationControls.set_position(4, 1),
  );
  await settle(page);
  const mappingTarget = await pointForText(page, 'mapping-target');
  await page.mouse.move(mappingTarget.x, mappingTarget.y);
  await expect(page.locator(visibleHoverSelector)).toContainText(
    'render invalidation hover',
  );
  const visibleHover = page.locator(visibleHoverSelector);
  const hoverBox = await visibleHover.boundingBox();
  expect(hoverBox).not.toBeNull();
  // Keep the pointer inside the editor-owned hover while the text mapping
  // moves underneath it; the widget's source mouseleave branch keeps it open
  // as long as the pointer remains inside the editor root.
  await page.mouse.move(hoverBox.x + 4, hoverBox.y + 4);
  await settle(page);
  const widget = page.locator(contentWidgetSelector);
  await expect(widget).toBeVisible();
  const before = await widget.boundingBox();
  const beforeTop = await widget.evaluate((element) =>
    Number.parseFloat(element.style.top),
  );
  const beforeMaxWidth = await widget.evaluate((element) =>
    Number.parseFloat(element.style.maxWidth),
  );
  expect(before).not.toBeNull();
  expect(beforeMaxWidth).toBe(await page.evaluate(() => window.innerWidth));

  const mapped = await probeUpdate(page, () =>
    page.evaluate(() => globalThis.__renderInvalidationControls.set_wrap(true)),
  );
  const afterTop = await widget.evaluate((element) =>
    Number.parseFloat(element.style.top),
  );
  const afterMaxWidth = await widget.evaluate((element) =>
    Number.parseFloat(element.style.maxWidth),
  );
  expect(mapped.frames).toBeGreaterThanOrEqual(1);
  expect(mapped.frames).toBeLessThanOrEqual(2);
  expect(mapped.writes).toContain('contentWidget');
  expect(Math.abs(afterTop - beforeTop)).toBeGreaterThan(5);
  expect(afterMaxWidth).toBe(beforeMaxWidth);

  const converged = await probeUpdate(page, () => Promise.resolve());
  expect(converged.frames).toBe(0);
  expect(converged.writes).toEqual([]);
});

test('line fill gutter and focus-only variants invalidate independently', async ({
  page,
}) => {
  await mountFixture(page);
  const content = page.locator(contentHighlightSelector);
  const margin = page.locator(marginHighlightSelector);

  await expect(content).toHaveCount(0);
  await expect(margin).toHaveCount(0);

  await update(page, 'set_highlight', 'gutter');
  await expect(content).toHaveCount(0);
  await expect(margin).toHaveCount(1);

  await update(page, 'set_highlight', 'line');
  await expect(content).toHaveCount(1);
  await expect(margin).toHaveCount(0);

  await update(page, 'set_highlight', 'all');
  await expect(content).toHaveCount(1);
  await expect(margin).toHaveCount(1);

  // Focus-only is a separate configuration bit. It removes both halves while
  // blurred, restores them on focus, and removes them again on focus loss.
  await update(page, 'set_focus_only', true);
  await expect(content).toHaveCount(0);
  await expect(margin).toHaveCount(0);
  await page.evaluate(() => globalThis.__renderInvalidationControls.focus());
  await settle(page);
  await expect(page.locator(editorSelector)).toHaveClass(/focused/);
  await expect(content).toHaveCount(1);
  await expect(margin).toHaveCount(1);
  await page.evaluate(() => globalThis.__renderInvalidationControls.blur());
  await settle(page);
  await expect(page.locator(editorSelector)).not.toHaveClass(/focused/);
  await expect(content).toHaveCount(0);
  await expect(margin).toHaveCount(0);

  await update(page, 'set_focus_only', false);
  await expect(content).toHaveCount(1);
  await expect(margin).toHaveCount(1);
  await update(page, 'set_highlight', 'none');
  await expect(content).toHaveCount(0);
  await expect(margin).toHaveCount(0);
});

test('validation decoration visibility follows runtime On Editable and Off without another interaction', async ({
  page,
}) => {
  await mountFixture(page);
  const validation = page.locator(
    '.render-invalidation-host .cdr.squiggly-warning',
  );
  await expect(validation).toHaveCount(1);

  await update(page, 'set_validation', 'off');
  await expect(validation).toHaveCount(0);
  await update(page, 'set_validation', 'on');
  await expect(validation).toHaveCount(1);
  // Editable filters validation decorations in this readonly viewer.
  await update(page, 'set_validation', 'editable');
  await expect(validation).toHaveCount(0);
  await update(page, 'set_validation', 'on');
  await expect(validation).toHaveCount(1);
});

test('ordinary spacing decoration alone recomputes a stationary cursor and content widget', async ({
  page,
}) => {
  await mountFixture(page);
  await page.evaluate(() => globalThis.__renderInvalidationControls.focus());
  await settle(page);
  const cursor = page.locator('.render-invalidation-host .cursor').first();
  await expect(cursor).toBeVisible();

  const anchor = await pointForText(page, 'anchor');
  await page.mouse.move(anchor.x, anchor.y);
  await expect(page.locator(visibleHoverSelector)).toContainText(
    'render invalidation hover',
  );
  await settle(page);
  const widget = page.locator(contentWidgetSelector);
  await expect(widget).toBeVisible();

  const initialCursorBox = await cursor.boundingBox();
  const initialWidgetBox = await widget.boundingBox();
  const initialPosition = await page.evaluate(() =>
    globalThis.__renderInvalidationControls.position(),
  );
  expect(initialCursorBox).not.toBeNull();
  expect(initialWidgetBox).not.toBeNull();
  expect(initialPosition).toEqual({ line: 1, column: 21 });

  const added = await probeUpdate(page, () =>
    page.evaluate(() =>
      globalThis.__renderInvalidationControls.add_spacing_decoration(),
    ),
  );
  expect(added.frames).toBe(1);
  expect(added.targets).toContain('viewLine');
  expect(added.writes).toContain('cursor');
  expect(added.writes).toContain('contentWidget');
  await expect(
    page.locator('.render-invalidation-host .render-invalidation-spacing'),
  ).toHaveCount(1);
  const decoratedCursorBox = await cursor.boundingBox();
  expect(decoratedCursorBox).not.toBeNull();
  // Cursor geometry already uses a live DOM Range. The spacing decoration is
  // before the unchanged model position, so a recomputation visibly moves it.
  expect(decoratedCursorBox.x).toBeGreaterThan(initialCursorBox.x + 20);
  expect(
    await page.evaluate(() => globalThis.__renderInvalidationControls.position()),
  ).toEqual(initialPosition);
  await expect(widget).toBeVisible();

  const removed = await probeUpdate(page, () =>
    page.evaluate(() =>
      globalThis.__renderInvalidationControls.remove_spacing_decoration(),
    ),
  );
  expect(removed.frames).toBe(1);
  expect(removed.targets).toContain('viewLine');
  expect(removed.writes).toContain('cursor');
  expect(removed.writes).toContain('contentWidget');
  await expect(
    page.locator('.render-invalidation-host .render-invalidation-spacing'),
  ).toHaveCount(0);
  const restoredCursorBox = await cursor.boundingBox();
  expect(restoredCursorBox).not.toBeNull();
  expect(Math.abs(restoredCursorBox.x - initialCursorBox.x)).toBeLessThanOrEqual(
    1,
  );
  expect(
    await page.evaluate(() => globalThis.__renderInvalidationControls.position()),
  ).toEqual(initialPosition);
  await expect(widget).toBeVisible();
});

test('token ranges invalidate token consumers without touching content widgets', async ({
  page,
}) => {
  await mountFixture(page);
  await update(page, 'set_wrap', true);
  const viewLines = page.locator('.render-invalidation-host .view-line');
  expect(await viewLines.count()).toBeGreaterThan(4);
  await page.evaluate(() =>
    globalThis.__renderInvalidationControls.set_position(4, 10),
  );
  await settle(page);
  const cursor = page.locator('.render-invalidation-host .cursor').first();
  const cursorBox = await cursor.boundingBox();
  const finalViewLineBox = await viewLines.last().boundingBox();
  expect(cursorBox).not.toBeNull();
  expect(finalViewLineBox).not.toBeNull();
  expect(Math.abs(cursorBox.y - finalViewLineBox.y)).toBeLessThan(5);
  await page.evaluate(() => globalThis.__renderInvalidationControls.focus());
  await settle(page);
  const anchor = await pointForText(page, 'anchor');
  await page.mouse.move(anchor.x, anchor.y);
  await expect(page.locator(visibleHoverSelector)).toContainText(
    'render invalidation hover',
  );
  await settle(page);

  const changed = await probeUpdate(page, () =>
    page.evaluate(() =>
      globalThis.__renderInvalidationControls.recolor_tokens(),
    ),
  );
  // Provider replacement first invalidates the old full range, then the
  // already-stabilized visible demand synchronously publishes its bounded
  // grammar tokens. Both token-scoped invalidations coalesce into one frame;
  // no redundant second DOM pass is needed.
  expect(changed.frames).toBe(1);
  expect(changed.targets).toContain('viewLine');
  expect(changed.writes).toContain('cursor');
  expect(changed.writes).not.toContain('contentWidget');
  await expect(
    page.locator('.render-invalidation-host .view-line .mtk3').first(),
  ).toBeVisible();
  // The final model line maps beyond raw model line number 4 once the long
  // preceding line wraps; its trailing token proves model→view range mapping.
  await expect(
    page
      .locator('.render-invalidation-host .view-line')
      .last()
      .locator('.mtk3')
      .last(),
  ).toBeVisible();
  await expect(page.locator(contentWidgetSelector)).toBeVisible();
});

test('multiple same-frame decoration changes preserve delivery and final convergence', async ({
  page,
}) => {
  await mountFixture(page);
  await page.evaluate(() => globalThis.__renderInvalidationControls.focus());
  await settle(page);
  const anchor = await pointForText(page, 'anchor');
  await page.mouse.move(anchor.x, anchor.y);
  await expect(page.locator(visibleHoverSelector)).toContainText(
    'render invalidation hover',
  );
  await settle(page);

  const roundTrip = await probeUpdate(page, () =>
    page.evaluate(() =>
      globalThis.__renderInvalidationControls.decoration_round_trip(),
    ),
  );
  expect(roundTrip.frames).toBe(1);
  expect(roundTrip.writes).toContain('cursor');
  expect(roundTrip.writes).toContain('contentWidget');
  await expect(
    page.locator('.render-invalidation-host .render-invalidation-spacing'),
  ).toHaveCount(0);
  const converged = await probeUpdate(page, () => Promise.resolve());
  expect(converged.frames).toBe(0);
  expect(converged.writes).toEqual([]);
});

test('changed updates converge in one frame while exact no-ops schedule and write nothing', async ({
  page,
}) => {
  await mountFixture(page);

  const changed = await probeUpdate(page, () =>
    page.evaluate(() =>
      globalThis.__renderInvalidationControls.set_whitespace('all'),
    ),
  );
  expect(changed.frames).toBe(1);
  expect(changed.mutations).toBeGreaterThan(0);
  await expect(
    page.locator('.render-invalidation-host .view-line .mtkw').first(),
  ).toBeVisible();

  const noOp = await probeUpdate(page, () =>
    page.evaluate(() =>
      globalThis.__renderInvalidationControls.set_whitespace('all'),
    ),
  );
  expect(noOp).toEqual({ frames: 0, mutations: 0, targets: [], writes: [] });

  // A quiet interval after the changed frame proves the loop did not leave a
  // part permanently dirty and continue scheduling itself. DOM mutations not
  // associated with an animation frame are outside the render-loop assertion;
  // no frame and no ViewPart position write may occur.
  const converged = await probeUpdate(page, () => Promise.resolve());
  expect(converged.frames).toBe(0);
  expect(converged.writes).toEqual([]);
});

test('compensated layout lanes still emit LayoutInfo and repaint their independent widths', async ({
  page,
}) => {
  await mountFixture(page);
  const lineNumber = page
    .locator('.render-invalidation-host .margin-view-overlays .line-numbers')
    .first();
  const beforeBox = await lineNumber.boundingBox();
  const before = await page.evaluate(() =>
    globalThis.__renderInvalidationControls.layout(),
  );
  expect(beforeBox).not.toBeNull();

  const changed = await probeUpdate(page, () =>
    page.evaluate(() =>
      globalThis.__renderInvalidationControls.set_compensated_layout(),
    ),
  );
  const after = await page.evaluate(() =>
    globalThis.__renderInvalidationControls.layout(),
  );
  const afterBox = await lineNumber.boundingBox();
  expect(changed.frames).toBe(1);
  expect(after.contentLeft).toBe(before.contentLeft);
  expect(after.lineNumbersWidth).not.toBe(before.lineNumbersWidth);
  expect(after.decorationsWidth).not.toBe(before.decorationsWidth);
  expect(afterBox).not.toBeNull();
  expect(afterBox.width).not.toBe(beforeBox.width);
});

test('setValue across a decimal line-count band updates scrollbar contentLeft', async ({
  page,
}) => {
  await mountFixture(page);
  await update(page, 'set_min_chars', 1);
  await update(page, 'set_line_count', 9);
  const scrollbar = page.locator(
    '.render-invalidation-host .monaco-scrollable-element.editor-scrollable',
  );
  const beforeBox = await scrollbar.boundingBox();
  const before = await page.evaluate(() =>
    globalThis.__renderInvalidationControls.layout(),
  );
  expect(beforeBox).not.toBeNull();

  const changed = await probeUpdate(page, () =>
    page.evaluate(() => globalThis.__renderInvalidationControls.set_line_count(10)),
  );
  const afterBox = await scrollbar.boundingBox();
  const after = await page.evaluate(() =>
    globalThis.__renderInvalidationControls.layout(),
  );
  expect(changed.frames).toBe(1);
  expect(after.lineNumbersWidth).toBeGreaterThan(before.lineNumbersWidth);
  expect(after.contentLeft).toBeGreaterThan(before.contentLeft);
  expect(after.width).toBe(before.width);
  expect(after.contentWidth).toBeLessThan(before.contentWidth);
  expect(after.contentLeft - before.contentLeft).toBeCloseTo(
    before.contentWidth - after.contentWidth,
    5,
  );
  expect(afterBox).not.toBeNull();
  expect(afterBox.x).toBeGreaterThan(beforeBox.x);
});

test('same-geometry layout_zone retains node and rereads callback in one frame', async ({
  page,
}) => {
  await mountFixture(page);
  await update(page, 'replace_zone');
  await expect(
    page.locator(
      '.render-invalidation-host [data-zone-generation="1"]',
    ),
  ).toHaveCount(1);
  const retainedNode = await page
    .locator('.render-invalidation-host [data-zone-generation="1"]')
    .elementHandle();
  expect(retainedNode).not.toBeNull();
  const before = await page.evaluate(() =>
    globalThis.__renderInvalidationControls.zone_counts(),
  );
  expect(before.first).toBeGreaterThan(0);

  const changed = await probeUpdate(page, () =>
    page.evaluate(() => globalThis.__renderInvalidationControls.replace_zone()),
  );
  const after = await page.evaluate(() =>
    globalThis.__renderInvalidationControls.zone_counts(),
  );
  expect(changed.frames).toBe(1);
  await expect(
    page.locator(
      '.render-invalidation-host [data-zone-generation="1"]',
    ),
  ).toHaveCount(1);
  await expect(
    page.locator(
      '.render-invalidation-host [data-zone-generation="2"]',
    ),
  ).toHaveCount(0);
  expect(
    await retainedNode.evaluate(
      (node) =>
        node ===
        document.querySelector(
          '.render-invalidation-host [data-zone-generation="1"]',
        ),
    ),
  ).toBe(true);
  expect(after.first).toBe(before.first);
  expect(after.second).toBeGreaterThan(0);
});

test('Chromium viewer root carries the non-Safari selection class', async ({
  page,
}) => {
  await mountFixture(page);
  const root = page.locator(editorSelector);
  await expect(root).toHaveClass(/\bno-user-select\b/);
  await expect(root).not.toHaveClass(/\benable-user-select\b/);
});
