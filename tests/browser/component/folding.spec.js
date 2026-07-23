import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

// End-to-end coverage for the folding contrib: the MoonBit scenario
// (tests/browser/moonbit/folding) asserts the initial render (expanded
// chevrons in the .cldr lane), then this spec drives the real interactions —
// a chevron click folds the region out of the view axis (collapsed chevron,
// inline-folded `⋯`, skipped line numbers), a second click unfolds, and
// Ctrl/Cmd+Shift+[ folds at the cursor.
//
// NOTE: view-line text uses non-breaking spaces, so text needles must be
// space-free.

const editor = '.monaco-editor.readonly-editor';

test('folding: chevron click folds and unfolds, keyboard folds at cursor', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  try {
    await page.goto('/browser-tests/folding.html');
    await expect(page.locator(editor)).toContainText('fold_child_a', {
      timeout: 10_000,
    });
    const report = await reporter.waitForReport(testInfo, { suite: 'folding' });
    expectMoonBitReportPassed(report, { suite: 'folding' });

    const expandedChevrons = page.locator(
      '.margin-view-overlays .cldr.codicon-folding-expanded',
    );
    const collapsedChevrons = page.locator(
      '.margin-view-overlays .cldr.codicon-folding-collapsed',
    );
    await expect(expandedChevrons).toHaveCount(2);

    // Fold the first region (lines 1-3). The chevrons sit at opacity 0 under
    // showFoldingControls=mouseover; force past the visibility check.
    await expandedChevrons.first().click({ force: true });

    // Lines 2-3 leave the view axis; the second region is untouched.
    await expect(page.locator(editor)).not.toContainText('fold_child_a');
    await expect(page.locator(editor)).not.toContainText('fold_child_b');
    await expect(page.locator(editor)).toContainText('fold_top');
    await expect(page.locator(editor)).toContainText('fold_tail');
    await expect(collapsedChevrons).toHaveCount(1);
    await expect(expandedChevrons).toHaveCount(1);

    // The folded header renders the `inline-folded` ⋯ pseudo-element carrier
    // and the folded-background whole-line highlight.
    await expect(page.locator(`${editor} .inline-folded`)).toHaveCount(1);
    await expect(page.locator(`${editor} .folded-background`)).toHaveCount(1);

    // Line numbers skip the folded model lines: 1, 4, 5.
    const numbers = await page
      .locator('.margin-view-overlays .line-numbers')
      .allInnerTexts();
    expect(numbers.map((n) => n.trim()).filter(Boolean)).toEqual(['1', '4', '5']);

    // A second click on the (now collapsed) chevron unfolds.
    await collapsedChevrons.first().click({ force: true });
    await expect(page.locator(editor)).toContainText('fold_child_a');
    await expect(collapsedChevrons).toHaveCount(0);
    await expect(expandedChevrons).toHaveCount(2);
    await expect(page.locator(`${editor} .inline-folded`)).toHaveCount(0);

    // Keyboard: put the cursor inside the second region and fold it with
    // Ctrl/Cmd+Shift+[ (editor.fold → setCollapseStateUp).
    await page.locator(`${editor} .view-line`, { hasText: 'fold_tail' }).click();
    await page.keyboard.press('ControlOrMeta+Shift+[');
    await expect(page.locator(editor)).not.toContainText('fold_tail');
    await expect(collapsedChevrons).toHaveCount(1);

    // ... and unfold it again with Ctrl/Cmd+Shift+].
    await page.keyboard.press('ControlOrMeta+Shift+]');
    await expect(page.locator(editor)).toContainText('fold_tail');
    await expect(collapsedChevrons).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});

test('folding: clicking the collapsed ⋯ unfolds; clicks past it and split gestures do not', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  try {
    await page.goto('/browser-tests/folding.html');
    await expect(page.locator(editor)).toContainText('fold_child_a', {
      timeout: 10_000,
    });
    await reporter.waitForReport(testInfo, { suite: 'folding' });

    const expandedChevrons = page.locator(
      '.margin-view-overlays .cldr.codicon-folding-expanded',
    );
    await expandedChevrons.first().click({ force: true });
    await expect(page.locator(editor)).not.toContainText('fold_child_a');

    // The collapsed `⋯` is the `.inline-folded` span's `::after` content; the
    // CSS-generated glyph is part of the span's layout box, so the DOM-measured
    // line width (`ViewLines.getLineWidth` → `offsetWidth`) includes it and a
    // click inside it hit-tests as CONTENT_TEXT at the header's max column —
    // Monaco's unfold-on-ellipsis arm (`folding.ts:433-441`).
    const ellipsis = page.locator(`${editor} .inline-folded`);
    await expect(ellipsis).toHaveCount(1);
    const ellipsisBox = await ellipsis.boundingBox();
    expect(ellipsisBox).not.toBeNull();
    expect(ellipsisBox.width).toBeGreaterThan(2);
    const y = ellipsisBox.y + ellipsisBox.height / 2;

    // A mousedown on the ⋯ that is released on another line toggles nothing
    // (`onEditorMouseUp` re-checks the line, `folding.ts:457-459`).
    await page.mouse.move(ellipsisBox.x + ellipsisBox.width - 2, y);
    await page.mouse.down();
    await page.mouse.move(ellipsisBox.x, y + 40, { steps: 2 });
    await page.mouse.up();
    await expect(page.locator(editor)).not.toContainText('fold_child_a');

    // A click well past the rendered width (beyond the ⋯) is CONTENT_EMPTY;
    // with `unfoldOnClickAfterEndOfLine` at its default `false` it toggles
    // nothing (`folding.ts:424-431`).
    await page.mouse.click(ellipsisBox.x + ellipsisBox.width + 24, y);
    await expect(page.locator(editor)).not.toContainText('fold_child_a');

    // A click on the ⋯ itself unfolds.
    await page.mouse.click(ellipsisBox.x + ellipsisBox.width - 2, y);
    await expect(page.locator(editor)).toContainText('fold_child_a');
    await expect(page.locator(`${editor} .inline-folded`)).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});

test('folding: alt-clicking a chevron folds the surrounding regions', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  try {
    await page.goto('/browser-tests/folding.html');
    await expect(page.locator(editor)).toContainText('fold_child_a', {
      timeout: 10_000,
    });
    await reporter.waitForReport(testInfo, { suite: 'folding' });

    const expandedChevrons = page.locator(
      '.margin-view-overlays .cldr.codicon-folding-expanded',
    );
    const collapsedChevrons = page.locator(
      '.margin-view-overlays .cldr.codicon-folding-collapsed',
    );
    await expect(expandedChevrons).toHaveCount(2);

    // Alt+click the first region's chevron: Monaco's "fold surrounding"
    // (`folding.ts:477-491`) toggles every region neither containing nor
    // contained by the clicked one — here the sibling `fold_mid` region folds
    // while the clicked region stays expanded.
    await expandedChevrons.first().click({ force: true, modifiers: ['Alt'] });
    await expect(page.locator(editor)).toContainText('fold_child_a');
    await expect(page.locator(editor)).not.toContainText('fold_tail');
    await expect(collapsedChevrons).toHaveCount(1);
  } finally {
    reporter.dispose();
  }
});
