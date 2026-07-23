import { expect, test } from '../support/test.js';

// Selection geometry parity: pointer hits resolve through the browser caret
// APIs and the selection highlight is painted from DOM-measured client rects
// (Monaco's MouseTargetFactory + SelectionsOverlay roles), not monospace `ch`
// arithmetic. These checks lock in the two observable wins of that rework: one
// merged rectangle per contiguous selection (no per-token seams) and an
// end-of-line fill when the selection continues past a line's text.

async function mountComponentViewer(page) {
  await page.goto('/browser-tests/component.html');
  await expect(page.locator('.monaco-editor.readonly-editor')).toContainText('component_answer', {
    timeout: 10_000,
  });
}

// Rects of `.selected-text` overlay nodes whose vertical center falls on the
// given line box, in viewport coordinates.
async function selectionRectsOnLine(page, lineBox) {
  return page.evaluate((box) => {
    const midY = box.y + box.height / 2;
    return Array.from(document.querySelectorAll('.selected-text'))
      .map((node) => node.getBoundingClientRect())
      .filter((rect) => rect.top <= midY && rect.bottom >= midY)
      .map((rect) => ({ left: rect.left, right: rect.right, width: rect.width }));
  }, lineBox);
}

test('paints one merged rectangle for a contiguous single-line selection', async ({ page }) => {
  await mountComponentViewer(page);

  const line = page.locator('.view-line').filter({ hasText: 'component_answe' });
  await expect(line).toHaveCount(1);
  const box = await line.boundingBox();
  expect(box).not.toBeNull();

  // Drag horizontally within the one line; the span covers several tokens.
  const y = box.y + box.height / 2;
  const startX = box.x + 2;
  const endX = box.x + 56;
  await page.mouse.move(startX, y);
  await page.mouse.down();
  await page.mouse.move(endX, y, { steps: 4 });
  await page.mouse.up();

  await expect
    .poll(() => page.locator('.selected-text').count(), { timeout: 2_000 })
    .toBeGreaterThan(0);

  const rects = await selectionRectsOnLine(page, box);
  // A contiguous same-line selection is one rectangle, regardless of how many
  // token spans it crosses. The old per-span overlay produced one div per span.
  expect(rects).toHaveLength(1);
  // The rectangle is DOM-measured: it is anchored at the line origin (where the
  // drag began) and spans several glyphs out toward the drop point. Exact width
  // depends on which character boundary the caret snaps to, so only the
  // measured, multi-character span is asserted here.
  expect(Math.abs(rects[0].left - startX)).toBeLessThanOrEqual(4);
  expect(rects[0].width).toBeGreaterThan(10);
});

test('extends the highlight past a line whose continuation is selected', async ({ page }) => {
  await mountComponentViewer(page);

  const firstLine = page.locator('.view-line').filter({ hasText: 'component_answe' });
  // A reachable segment of the next model line (the old "er_name =" slice moved
  // once wrappingIndent shifted the soft-wrap breaks). The identifier repeats on
  // the later `.length()` line, so take the first occurrence.
  const lastLine = page.locator('.view-line').filter({ hasText: 'really_long_c' }).first();
  await expect(firstLine).toHaveCount(1);
  await expect(lastLine).toBeVisible();

  const firstBox = await firstLine.boundingBox();
  const lastBox = await lastLine.boundingBox();
  expect(firstBox).not.toBeNull();
  expect(lastBox).not.toBeNull();

  await page.mouse.move(firstBox.x + 2, firstBox.y + firstBox.height / 2);
  await page.mouse.down();
  await page.mouse.move(lastBox.x + lastBox.width - 2, lastBox.y + lastBox.height / 2, {
    steps: 6,
  });
  await page.mouse.up();

  await expect
    .poll(() => page.locator('.selected-text').count(), { timeout: 2_000 })
    .toBeGreaterThan(0);

  // The selection spans multiple stacked lines (distinct vertical bands).
  const bandCount = await page.evaluate(() => {
    const tops = new Set(
      Array.from(document.querySelectorAll('.selected-text')).map((node) =>
        Math.round(node.getBoundingClientRect().top),
      ),
    );
    return tops.size;
  });
  expect(bandCount).toBeGreaterThan(1);

  // Faithful end-of-line fill: this selection spans a real model-line break
  // (model line 1 -> model line 2) inside the soft-wrapped region. Monaco draws
  // the EOL fill only at real line breaks, never on soft-wrap continuations, so
  // exactly the lines that end a model line extend past their rendered text.
  // The check measures each selected line's true glyph right edge (a Range over
  // its text, not the padded content box) against its selection right edge.
  const fills = await page.evaluate(() => {
    const selRects = Array.from(document.querySelectorAll('.selected-text')).map((n) =>
      n.getBoundingClientRect(),
    );
    let extendsPastText = false;
    let coversExactlyOnContinuation = false;
    for (const lineEl of document.querySelectorAll('.view-line')) {
      const content = lineEl.querySelector('.view-line-content');
      if (!content || !content.textContent) {
        continue;
      }
      const range = document.createRange();
      range.selectNodeContents(content);
      let glyphRight = -Infinity;
      for (const r of range.getClientRects()) {
        glyphRight = Math.max(glyphRight, r.right);
      }
      if (glyphRight === -Infinity) {
        continue;
      }
      const lineRect = lineEl.getBoundingClientRect();
      const midY = lineRect.top + lineRect.height / 2;
      let selRight = -Infinity;
      for (const r of selRects) {
        if (r.top <= midY && r.bottom >= midY) {
          selRight = Math.max(selRight, r.right);
        }
      }
      if (selRight === -Infinity) {
        continue;
      }
      if (selRight > glyphRight + 2) {
        extendsPastText = true; // EOL fill at a real line break
      } else if (Math.abs(selRight - glyphRight) <= 1.5) {
        coversExactlyOnContinuation = true; // soft-wrap line: no spurious stub
      }
    }
    return { extendsPastText, coversExactlyOnContinuation };
  });
  // At least one line ends a model line and gets the EOL fill...
  expect(fills.extendsPastText).toBe(true);
  // ...while soft-wrap continuation lines cover exactly their text (no stub).
  expect(fills.coversExactlyOnContinuation).toBe(true);
});

// Exact selection-rect oracle (the Exhibit A regression guard). The painted
// highlight must cover *exactly* the selected source characters — no more, no
// fewer. This pins the invariant the offset-centric round-trip violated: on a
// projected soft-wrapped line, `view_column_at_source_offset`
// resolved a wider column span than the stored selection, painting ~3 columns
// too wide. The fix keeps hit-test, selection state, and paint all in view
// `Position`s through the `CoordinatesConverter`, so the painted right edge
// equals the DOM-measured right edge of the selected source text.
test('paints exactly the selected source columns on a projected line', async ({ page }) => {
  await mountComponentViewer(page);

  // Exhibit A's exact repro: drag within the `component_answer` identifier (the
  // bug painted its 7-char prefix "compone" ~3 columns too wide). Soft wrap
  // keeps this on the projected path.
  const line = page.locator('.view-line').filter({ hasText: 'component_answe' });
  await expect(line).toHaveCount(1);
  const box = await line.boundingBox();
  expect(box).not.toBeNull();

  // Drag from the line's left edge into the identifier (single line, constant y).
  const y = box.y + box.height / 2;
  await page.mouse.move(box.x + 2, y);
  await page.mouse.down();
  await page.mouse.move(box.x + 56, y, { steps: 5 });
  await page.mouse.up();

  await expect
    .poll(() => page.locator('.selected-text').count(), { timeout: 2_000 })
    .toBeGreaterThan(0);

  await page.keyboard.press('ControlOrMeta+C');
  const copiedText = await page.evaluate(() => globalThis.__readonlyEditorCopiedText || '');
  expect(copiedText.length).toBeGreaterThan(3);
  expect(copiedText).not.toContain('\n'); // single-line selection

  // Independently measure the right edge of exactly `copiedText.length` source
  // characters from the line start and the painted selection's right edge.
  // They must coincide within sub-pixel rounding.
  const geometry = await page.evaluate((sourceLen) => {
    const lineEl = Array.from(document.querySelectorAll('.view-line')).find((el) =>
      el.textContent.includes('component_answe'),
    );
    const content = lineEl.querySelector('.view-line-content');
    const contentLeft = content.getBoundingClientRect().left;

    // Build a DOM Range over exactly `sourceLen` source characters, walking the
    // token spans in order.
    const range = document.createRange();
    range.setStart(content, 0);
    let remaining = sourceLen;
    let endNode = null;
    let endOffset = 0;
    for (const span of content.children) {
      const textNode = span.firstChild;
      if (!textNode || textNode.nodeType !== 3) {
        continue;
      }
      const len = textNode.textContent.length;
      if (remaining <= len) {
        endNode = textNode;
        endOffset = remaining;
        remaining = 0;
        break;
      }
      remaining -= len;
      endNode = textNode;
      endOffset = len;
    }
    if (!endNode) {
      return null;
    }
    range.setEnd(endNode, endOffset);
    let expectedRight = contentLeft;
    for (const r of range.getClientRects()) {
      expectedRight = Math.max(expectedRight, r.right);
    }

    const midY = lineEl.getBoundingClientRect().top + lineEl.getBoundingClientRect().height / 2;
    let paintedRight = contentLeft;
    for (const node of document.querySelectorAll('.selected-text')) {
      const r = node.getBoundingClientRect();
      if (r.top <= midY && r.bottom >= midY) {
        paintedRight = Math.max(paintedRight, r.right);
      }
    }
    return {
      expected: expectedRight - contentLeft,
      painted: paintedRight - contentLeft,
    };
  }, copiedText.length);

  expect(geometry).not.toBeNull();
  // Exact: the painted highlight ends where the selected source text ends. Under
  // the old offset round-trip this diverged by ~3 columns (70.5px vs 50.6px).
  expect(Math.abs(geometry.painted - geometry.expected)).toBeLessThanOrEqual(1.5);
});
