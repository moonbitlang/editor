import { expect } from './test.js';

const reportPrefix = '[readonly-editor-browser-test]';

export async function installMoonBitReporter(page) {
  const consoleReports = [];
  const onConsole = (message) => {
    const text = message.text();
    if (!text.startsWith(reportPrefix)) {
      return;
    }
    const raw = text.slice(reportPrefix.length).trim();
    try {
      consoleReports.push(JSON.parse(raw));
    } catch (error) {
      consoleReports.push({
        suite: 'unknown',
        status: 'failed',
        failures: [`invalid console report JSON: ${error?.message || String(error)}`],
        metrics: {},
      });
    }
  };
  page.on('console', onConsole);
  await page.addInitScript(() => {
    globalThis.__readonlyEditorBrowserTestReports = [];
    globalThis.__readonlyEditorBrowserTestReport = (payload) => {
      const report = typeof payload === 'string' ? JSON.parse(payload) : payload;
      globalThis.__readonlyEditorBrowserTestReports.push(report);
    };
  });
  return {
    async waitForReport(testInfo, options = {}) {
      const report = await waitForReport(page, consoleReports, options);
      await testInfo.attach(options.attachmentName ?? 'moonbit-browser-report', {
        body: JSON.stringify(report, null, 2),
        contentType: 'application/json',
      });
      return report;
    },
    dispose() {
      page.off('console', onConsole);
    },
  };
}

export function expectMoonBitReportPassed(report, options = {}) {
  if (options.suite) {
    expect(report.suite).toBe(options.suite);
  }
  expect(report.status).toBe('passed');
  expect(Array.isArray(report.failures)).toBeTruthy();
  expect(report.failures).toEqual([]);
  expect(report.metrics && typeof report.metrics).toBe('object');
}

async function waitForReport(page, consoleReports, options) {
  const suite = options.suite;
  const deadline = Date.now() + (options.timeout ?? 10_000);
  while (Date.now() < deadline) {
    const directReports = await page
      .evaluate(() => globalThis.__readonlyEditorBrowserTestReports ?? [])
      .catch(() => []);
    const report = [...directReports, ...consoleReports].find((candidate) =>
      suite ? candidate?.suite === suite : candidate,
    );
    if (report) {
      return report;
    }
    await page.waitForTimeout(50);
  }
  throw new Error(
    suite
      ? `Timed out waiting for MoonBit browser report for suite ${suite}`
      : 'Timed out waiting for MoonBit browser report',
  );
}
