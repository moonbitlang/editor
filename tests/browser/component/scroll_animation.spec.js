import { expect, test } from '../support/test.js';

async function openSmoothViewer(page) {
  await page.goto('/browser-tests/component.html');
  await expect(page.locator('.monaco-editor.readonly-editor')).toContainText(
    'component_answer',
    { timeout: 10_000 },
  );
}

async function scrollFacts(page) {
  return page.locator('.viewer-host').evaluate((host) => ({
    events: Number(host.dataset.scrollEvents || 0),
    top: Number(host.dataset.scrollTop || 0),
  }));
}

test('animates a classified physical wheel through multiple rAF states', async ({ page }) => {
  await openSmoothViewer(page);
  const before = await scrollFacts(page);
  const prevented = await page.evaluate(() => {
    const event = new WheelEvent('wheel', {
      deltaY: 40,
      deltaMode: 0,
      bubbles: true,
      cancelable: true,
    });
    document.querySelector('.overflow-guard').dispatchEvent(event);
    return event.defaultPrevented;
  });
  expect(prevented).toBeTruthy();
  await expect.poll(async () => (await scrollFacts(page)).top).toBe(before.top + 50);
  const after = await scrollFacts(page);
  expect(after.events - before.events).toBeGreaterThan(1);
});

test('applies a classified trackpad wheel in one rendered state', async ({ page }) => {
  await openSmoothViewer(page);
  const before = await scrollFacts(page);
  // Exercising both axes gives the source classifier an immediate score of 1;
  // predominant-axis routing then keeps Y and yields a 3px integer move.
  const prevented = await page.evaluate(() => {
    const event = new WheelEvent('wheel', {
      deltaX: 1,
      deltaY: 2.37,
      deltaMode: 0,
      bubbles: true,
      cancelable: true,
    });
    document.querySelector('.overflow-guard').dispatchEvent(event);
    return event.defaultPrevented;
  });
  expect(prevented).toBeTruthy();
  await expect.poll(async () => (await scrollFacts(page)).top).toBe(before.top + 3);
  const after = await scrollFacts(page);
  expect(after.events - before.events).toBe(1);
});
