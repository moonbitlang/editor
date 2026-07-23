import { expect, test } from '../support/test.js';
import { openMainFixture } from '../support/app.js';

const widgetSelector = '[data-content-widget="editor.contrib.resizableContentHoverWidget"]';

// The content-hover widget is a persistent content widget (Monaco
// `ViewContentWidgets` lifecycle): its DOM mounts once and per-frame rendering
// only repositions it. Moving the pointer along the hovered range must keep
// the same node visible with no fade-in replays — a re-mounting regression
// restarts the CSS animation and reads as flicker.
test('hover widget stays mounted and visible while the mouse moves along the span', async ({ page }) => {
  await page.goto('/');
  await openMainFixture(page);

  const symbol = page.locator('.view-line span', { hasText: 'startup_event' }).first();
  await expect(symbol).toBeVisible();
  const hover = page.locator(`${widgetSelector} .monaco-hover`);
  // The first hover result waits on the language backend warming up; retry
  // like the pointer-interaction smoke test does.
  await expect(async () => {
    await symbol.hover();
    await expect(hover).toBeVisible({ timeout: 3_000 });
  }).toPass({ timeout: 60_000 });

  // Sweep inside the shown hover's own range — the `.hoverHighlight`
  // decoration marks exactly the span the hover applies to. Within it the
  // hover must stay put (Monaco keeps the filtered parts for same-line
  // anchors inside the part range); leaving it may legitimately hide.
  const highlight = page.locator('.hoverHighlight').first();
  await expect(highlight).toBeVisible();
  const box = await highlight.boundingBox();
  const y = box.y + box.height / 2;
  await page.mouse.move(box.x + 3, y);
  await expect(hover).toBeVisible({ timeout: 5_000 });

  // Tag the live node and count animation (fade-in) restarts from here on.
  await page.evaluate((selector) => {
    const el = document.querySelector(selector);
    el.__probe = true;
    window.__animationStarts = 0;
    el.addEventListener('animationstart', () => {
      window.__animationStarts += 1;
    });
  }, widgetSelector);

  // Sweep the pointer horizontally across the hovered span, sampling for
  // longer than several hiding-delay/hover-delay cycles.
  let hiddenSamples = 0;
  const steps = 40;
  for (let i = 0; i < steps; i++) {
    const x = box.x + 3 + ((box.width - 6) * i) / (steps - 1);
    await page.mouse.move(x, y);
    await page.waitForTimeout(40);
    if (!(await hover.isVisible())) {
      hiddenSamples += 1;
    }
  }

  const { sameNode, animationStarts } = await page.evaluate((selector) => {
    const el = document.querySelector(selector);
    return {
      sameNode: Boolean(el && el.__probe),
      animationStarts: window.__animationStarts,
    };
  }, widgetSelector);

  expect(sameNode).toBeTruthy(); // the widget DOM was never re-created
  expect(animationStarts).toBe(0); // the fade-in never replayed mid-hover
  expect(hiddenSamples).toBe(0); // the widget never blinked off
  await expect(hover).toBeVisible();
});
