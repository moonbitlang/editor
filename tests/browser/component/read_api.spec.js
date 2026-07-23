import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

test('runs MoonBit DOM-measured read-API checks in the browser', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  await page.goto('/browser-tests/read_api.html');
  // The no-wrap fixture viewer renders its lines before the measurements run.
  await expect(page.locator('.monaco-editor.readonly-editor .view-line').first()).toBeVisible({
    timeout: 10_000,
  });
  const report = await reporter.waitForReport(testInfo, { suite: 'read_api' });
  expectMoonBitReportPassed(report, { suite: 'read_api' });
  // The measured offsets are real, positive client-rect pixels.
  expect(report.metrics.offsetColumn9).toBeGreaterThan(report.metrics.offsetColumn1);
  expect(report.metrics.lineWidth).toBeGreaterThanOrEqual(report.metrics.offsetColumn9);
  expect(report.metrics.contentLeft).toBeGreaterThan(0);
});
