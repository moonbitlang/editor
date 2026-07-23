import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

test('runs MoonBit reveal_position horizontal-reveal check in the browser', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  await page.goto('/browser-tests/reveal.html');
  // The no-wrap fixture viewer renders its lines before the reveal fires.
  await expect(page.locator('.monaco-editor.readonly-editor .view-line').first()).toBeVisible({
    timeout: 10_000,
  });
  const report = await reporter.waitForReport(testInfo, { suite: 'reveal_horizontal' });
  expectMoonBitReportPassed(report, { suite: 'reveal_horizontal' });
  // The deferred horizontal reveal moved the caret into view on both axes.
  expect(report.metrics.scrollLeft).toBeGreaterThan(0);
  expect(report.metrics.scrollTop).toBeGreaterThan(0);
});
