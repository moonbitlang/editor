import { test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

// Pins Monaco's setValue flush lane (TextModel.setValue behind
// codeEditorWidget.setValue, plan monaco-set-value-api-port.md): across a
// set_value the same editor root survives (no view rebuild, unlike
// set_model), the scroll is kept instead of reset, the quick-diff gutter
// recomputes against the new snapshot, and the folding chevrons re-derive
// after the flush destroyed their decorations. The assertions run
// MoonBit-side in tests/browser/moonbit/set_value.
test('keeps the view and refreshes gutter state across set_value', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  try {
    await page.goto('/browser-tests/set_value.html');
    const report = await reporter.waitForReport(testInfo, { suite: 'set_value' });
    expectMoonBitReportPassed(report, { suite: 'set_value' });
  } finally {
    reporter.dispose();
  }
});
