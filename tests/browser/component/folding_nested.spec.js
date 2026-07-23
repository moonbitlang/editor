import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

// End-to-end coverage for the recursive folding mouse variants over a NESTED
// fixture (outer region 1..5 containing inner region 2..4, built by
// tests/browser/moonbit/folding_nested). Monaco's `onEditorMouseUp`
// (`folding.ts:449-510`) treats a shift- or middle-click on a chevron as
// recursive: the first click toggles only the descendants that share the
// header's collapse state, the second click (no expanded descendants left)
// folds the header itself, and a recursive click on the collapsed header
// unfolds the whole subtree at once.
//
// NOTE: view-line text uses non-breaking spaces, so text needles must be
// space-free.

const editor = '.monaco-editor.readonly-editor';

const expandedSelector =
  '.margin-view-overlays .cldr.codicon-folding-expanded';
const collapsedSelector =
  '.margin-view-overlays .cldr.codicon-folding-collapsed';

async function visibleLineNumbers(page) {
  const numbers = await page
    .locator('.margin-view-overlays .line-numbers')
    .allInnerTexts();
  return numbers.map((n) => n.trim()).filter(Boolean);
}

// Drives the three-step recursive matrix with the given chevron click
// options (`{ modifiers: ['Shift'] }` or `{ button: 'middle' }`) — the two
// gestures share `folding.ts`'s `recursive` arm via
// `e.event.middleButton || e.event.shiftKey`.
async function runRecursiveMatrix(page, clickOptions) {
  const expandedChevrons = page.locator(expandedSelector);
  const collapsedChevrons = page.locator(collapsedSelector);
  await expect(expandedChevrons).toHaveCount(2);

  // Step 1: a recursive click on the OUTER header's chevron toggles only the
  // regions inside it that share its (expanded) state — the inner region
  // folds, the outer header stays expanded (`folding.ts:495-505`).
  await expandedChevrons.first().click({ force: true, ...clickOptions });
  await expect(page.locator(editor)).not.toContainText('nest_leaf_a');
  await expect(page.locator(editor)).not.toContainText('nest_leaf_b');
  await expect(page.locator(editor)).toContainText('nest_branch');
  await expect(page.locator(editor)).toContainText('nest_after');
  await expect(collapsedChevrons).toHaveCount(1);
  await expect(expandedChevrons).toHaveCount(1);
  expect(await visibleLineNumbers(page)).toEqual(['1', '2', '5', '6']);

  // Step 2: no expanded descendants remain, so the same click now folds the
  // header itself ("If all are already folded or there are no children, also
  // fold parent").
  await expandedChevrons.first().click({ force: true, ...clickOptions });
  await expect(page.locator(editor)).not.toContainText('nest_branch');
  await expect(page.locator(editor)).not.toContainText('nest_after');
  await expect(page.locator(editor)).toContainText('nest_root');
  await expect(page.locator(editor)).toContainText('nest_end');
  await expect(collapsedChevrons).toHaveCount(1);
  await expect(expandedChevrons).toHaveCount(0);
  expect(await visibleLineNumbers(page)).toEqual(['1', '6']);

  // Step 3: a recursive click on the collapsed header toggles it together
  // with every descendant sharing its (collapsed) state — the whole subtree
  // unfolds in one gesture.
  await collapsedChevrons.first().click({ force: true, ...clickOptions });
  await expect(page.locator(editor)).toContainText('nest_leaf_a');
  await expect(page.locator(editor)).toContainText('nest_leaf_b');
  await expect(collapsedChevrons).toHaveCount(0);
  await expect(expandedChevrons).toHaveCount(2);
  expect(await visibleLineNumbers(page)).toEqual([
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
  ]);
}

test('folding: shift-clicking a chevron folds children first, then the region, and unfolds the subtree', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  try {
    await page.goto('/browser-tests/folding_nested.html');
    await expect(page.locator(editor)).toContainText('nest_leaf_a', {
      timeout: 10_000,
    });
    const report = await reporter.waitForReport(testInfo, {
      suite: 'folding_nested',
    });
    expectMoonBitReportPassed(report, { suite: 'folding_nested' });

    await runRecursiveMatrix(page, { modifiers: ['Shift'] });
  } finally {
    reporter.dispose();
  }
});

test('folding: middle-clicking a chevron drives the same recursive toggle', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  try {
    await page.goto('/browser-tests/folding_nested.html');
    await expect(page.locator(editor)).toContainText('nest_leaf_a', {
      timeout: 10_000,
    });
    await reporter.waitForReport(testInfo, { suite: 'folding_nested' });

    await runRecursiveMatrix(page, { button: 'middle' });
  } finally {
    reporter.dispose();
  }
});
