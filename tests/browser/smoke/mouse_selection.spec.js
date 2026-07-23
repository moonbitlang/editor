import { expect, test } from '../support/test.js';

// Mouse-driven selection modes routed through the ported ViewController:
// dispatchMouse maps the multi-click count to CoreNavigationCommands, so a
// double-click selects a word, a triple-click selects the line, and a click in
// the line-number gutter selects a whole line. Each is verified through the
// clipboard (the model selection), independent of the rendered view lines.

async function mountComponentViewer(page) {
  await page.goto('/browser-tests/component.html');
  await expect(page.locator('.monaco-editor.readonly-editor')).toContainText('component_answer', {
    timeout: 10_000,
  });
}

async function copySelection(page) {
  await page.keyboard.press('ControlOrMeta+C');
  return page.evaluate(() => globalThis.__readonlyEditorCopiedText || '');
}

test('double-click selects the word under the pointer', async ({ page }) => {
  await mountComponentViewer(page);

  const line = page.locator('.view-line').filter({ hasText: 'component_answe' });
  await expect(line).toHaveCount(1);
  const box = await line.boundingBox();
  expect(box).not.toBeNull();

  // Double-click in the middle of the `component_answer` identifier.
  await page.mouse.dblclick(box.x + 40, box.y + box.height / 2);
  await expect.poll(() => page.locator('.selected-text').count()).toBeGreaterThan(0);

  const copied = await copySelection(page);
  expect(copied).toBe('component_answer');
});

test('triple-click selects the whole model line', async ({ page }) => {
  await mountComponentViewer(page);

  const line = page.locator('.view-line').filter({ hasText: 'component_answe' });
  await expect(line).toHaveCount(1);
  const box = await line.boundingBox();
  expect(box).not.toBeNull();

  // Three rapid clicks at the same point escalate to line selection. Real
  // browsers stamp `MouseEvent.detail` 1/2/3 across the burst, and Monaco's
  // `MouseDownState.trySetCount` is detail-driven — `page.mouse.click()`
  // always sends detail 1, so the escalation is written as explicit
  // down/up pairs with growing `clickCount`.
  const x = box.x + 40;
  const y = box.y + box.height / 2;
  await page.mouse.move(x, y);
  await page.mouse.down({ clickCount: 1 });
  await page.mouse.up({ clickCount: 1 });
  await page.mouse.down({ clickCount: 2 });
  await page.mouse.up({ clickCount: 2 });
  await page.mouse.down({ clickCount: 3 });
  await page.mouse.up({ clickCount: 3 });
  await expect.poll(() => page.locator('.selected-text').count()).toBeGreaterThan(0);

  const copied = await copySelection(page);
  // The full logical (model) line, even though it is soft-wrapped into several
  // view lines, plus the trailing newline that line selection includes.
  expect(copied).toContain('pub fn component_answer() -> Int {');
  expect(copied.endsWith('\n')).toBe(true);
});

test('clicking the line-number gutter selects that line', async ({ page }) => {
  await mountComponentViewer(page);

  const line = page.locator('.view-line').filter({ hasText: 'component_answe' });
  await expect(line).toHaveCount(1);
  const lineBox = await line.boundingBox();
  const gutterBox = await page.locator('.margin-view-overlays .line-numbers').first().boundingBox();
  expect(lineBox).not.toBeNull();
  expect(gutterBox).not.toBeNull();

  // Click in the line-number gutter at the component line's row.
  await page.mouse.click(gutterBox.x + gutterBox.width / 2, lineBox.y + lineBox.height / 2);
  await expect.poll(() => page.locator('.selected-text').count()).toBeGreaterThan(0);

  const copied = await copySelection(page);
  expect(copied).toContain('pub fn component_answer() -> Int {');
  expect(copied.endsWith('\n')).toBe(true);
});
