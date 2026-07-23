import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

// Drags a selection across the full width of one rendered view line.
async function dragAcrossLine(page, lineLocator) {
  const box = await lineLocator.boundingBox();
  expect(box).not.toBeNull();
  const y = box.y + box.height / 2;
  await page.mouse.move(box.x + 2, y);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width - 2, y, { steps: 6 });
  await page.mouse.up();
}

test('paints whitespace dots only under a selection and re-renders on change', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  await page.goto('/browser-tests/whitespace_selection.html');
  await expect(page.locator('.monaco-editor.readonly-editor .view-line').first()).toBeVisible({
    timeout: 10_000,
  });

  // Default mode is now Selection: with no selection, nothing dots.
  const report = await reporter.waitForReport(testInfo, { suite: 'whitespace_selection' });
  expectMoonBitReportPassed(report, { suite: 'whitespace_selection' });
  expect(report.metrics.initialWhitespaceSpans).toBe(0);
  await expect(page.locator('.view-line .mtkw')).toHaveCount(0);

  const line1Dots = page.locator('.view-line[data-line="1"] .mtkw');
  const line2Dots = page.locator('.view-line[data-line="2"] .mtkw');

  // Select line 1 → whitespace glyphs appear under it, none on line 2.
  await dragAcrossLine(page, page.locator('.view-line[data-line="1"]'));
  await expect.poll(() => line1Dots.count(), { timeout: 2_000 }).toBeGreaterThan(0);
  await expect(line2Dots).toHaveCount(0);

  // Dots take editorWhitespace.foreground (viewLines.css `.mtkw`), not the
  // token color: #e3e4e229 in the dark shell.
  expect(
    await line1Dots.first().evaluate((el) => getComputedStyle(el).color),
  ).toBe('rgba(227, 228, 226, 0.16)');

  // Move the selection to line 2 → line 1 re-renders without dots (the
  // selection-change invalidation), line 2 gains them.
  await dragAcrossLine(page, page.locator('.view-line[data-line="2"]'));
  await expect.poll(() => line2Dots.count(), { timeout: 2_000 }).toBeGreaterThan(0);
  await expect(line1Dots).toHaveCount(0);
});
