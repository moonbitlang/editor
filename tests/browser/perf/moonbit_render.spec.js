import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

test('records MoonBit-authored viewer render performance samples', async ({
  page,
}, testInfo) => {
  test.setTimeout(30_000);
  const reporter = await installMoonBitReporter(page);
  try {
    await page.goto('/browser-tests/perf.html');
    const report = await reporter.waitForReport(testInfo, {
      suite: 'viewer_render_perf',
      timeout: 20_000,
    });
    expectMoonBitReportPassed(report, { suite: 'viewer_render_perf' });
    expect(report.metrics.warmupCount).toBe(1);
    expect(report.metrics.sampleCount).toBe(3);
    expect(Array.isArray(report.metrics.samples)).toBeTruthy();
    expect(report.metrics.samples).toHaveLength(3);
    expect(report.metrics.worstMs).toBeGreaterThanOrEqual(report.metrics.bestMs);
  } finally {
    reporter.dispose();
  }
});
