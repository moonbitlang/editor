import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

test('renders whitespace glyphs and control-character placeholders via ViewerOptions', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  await page.goto('/browser-tests/whitespace.html');
  // The fixture viewer renders its single line before the assertions run.
  await expect(page.locator('.monaco-editor.readonly-editor .view-line').first()).toBeVisible({
    timeout: 10_000,
  });
  const report = await reporter.waitForReport(testInfo, { suite: 'whitespace' });
  expectMoonBitReportPassed(report, { suite: 'whitespace' });
  // render_whitespace=All produced real whitespace glyph spans, and
  // render_control_characters=true produced a [U+202E] placeholder — both
  // reachable only because the options now thread into RenderLineInput.
  expect(report.metrics.whitespaceSpans).toBeGreaterThan(0);
  expect(report.metrics.controlSpans).toBeGreaterThan(0);
  // Cross-check the DOM directly: the whitespace span and the placeholder text
  // are present in the live view line.
  await expect(page.locator('.view-line .mtkw').first()).toBeVisible();
  await expect(page.locator('.view-line .mtkcontrol').first()).toHaveText('[U+202E]');
});
