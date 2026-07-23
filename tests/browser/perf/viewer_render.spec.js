import { promises as fs } from 'node:fs';
import { expect, test } from '../support/test.js';
import { openWorkspaceFile } from '../support/app.js';

const largeFixture = 'tests/fixtures/workspace/src/generated_large.mbt';

// Non-failing perf probe: opens the small fixture and a generated ~10k-line
// fixture, then attaches structured render timing evidence from browser events.
// It does not enforce budgets; hard gates should only be added with documented
// baselines.
test('records render timings for small and large documents', async ({ page }, testInfo) => {
  test.setTimeout(120_000);
  const chunks = [];
  for (let i = 0; i < 2000; i++) {
    chunks.push(`///|\npub fn generated_value_${i}() -> Int {\n  ${i}\n}\n`);
  }
  await fs.writeFile(largeFixture, chunks.join('\n'), 'utf8');

  const events = [];
  page.on('console', (message) => {
    const text = message.text();
    if (text.includes('[readonly-editor]')) {
      events.push(text);
    }
  });

  try {
    await page.goto('/');
    await openWorkspaceFile(page, 'src/main.mbt');
    await expect
      .poll(() => events.some((event) => event.includes('dom:mounted')))
      .toBeTruthy();
    const smallMark = events.length;

    await openWorkspaceFile(page, 'src/generated_large.mbt');
    await expect
      .poll(() => events.slice(smallMark).some((event) => event.includes('dom:mounted')), {
        timeout: 60_000,
      })
      .toBeTruthy();

    const timings = events
      .map((event, index) => {
        const parsed = parseReadonlyEvent(event);
        return parsed ? { ...parsed, rawIndex: index } : null;
      })
      .filter((event) => event?.name === 'moonbit:render' || event?.name === 'dom:mounted');
    const report = {
      suite: 'workbench_render_events',
      status: 'passed',
      failures: [],
      metrics: {
        eventCount: timings.length,
        smallEventCount: timings.filter((event) => event.rawIndex < smallMark).length,
        largeEventCount: timings.filter((event) => event.rawIndex >= smallMark).length,
        events: timings,
      },
    };
    await testInfo.attach('workbench-render-events', {
      body: JSON.stringify(report, null, 2),
      contentType: 'application/json',
    });
    console.log(
      '[perf] workbench render event report',
      JSON.stringify({
        eventCount: report.metrics.eventCount,
        smallEventCount: report.metrics.smallEventCount,
        largeEventCount: report.metrics.largeEventCount,
      }),
    );
  } finally {
    await fs.rm(largeFixture, { force: true });
  }
});

function parseReadonlyEvent(line) {
  const match = line.match(/^\[readonly-editor\]\s+(\S+)\s+(.+)$/);
  if (!match) {
    return null;
  }
  try {
    return {
      name: match[1],
      payload: JSON.parse(match[2]),
    };
  } catch {
    return {
      name: match[1],
      payload: match[2],
    };
  }
}
