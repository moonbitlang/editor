import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

// Pins Monaco's per-model View lifecycle (setModel = detach-then-attach,
// codeEditorWidget.ts:506): across a model swap the old view's DOM leaves
// the container and a fresh view appears with data-uri/data-mode-id stamps,
// model-scoped view zones are lost, viewer-scoped unmanaged overlays replay,
// text focus carries over, the persistent hover keeps its editor-relative
// geometry, detaching to no model restores the placeholder, and idempotent
// disposal cancels a pending frame while removing owned DOM but retaining the
// host and caller-owned overlay node. The assertions run MoonBit-side in
// tests/browser/moonbit/model_swap except for browser-measured widget geometry.
test('rebuilds the view per model and carries focus across set_model', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  try {
    await page.goto('/browser-tests/model_swap.html');

    const hoverMarkerStart = async () => {
      const line = page.locator('.viewer-host .view-line[data-line="1"]');
      await expect(line).toBeVisible();
      const box = await line.boundingBox();
      expect(box).not.toBeNull();
      await page.mouse.move(0, 0);
      await page.mouse.move(box.x + 3, box.y + box.height / 2);
      const hover = page.locator(
        '[data-content-widget="editor.contrib.resizableContentHoverWidget"] .monaco-hover:not(.hidden)',
      );
      await expect(hover).toBeVisible({ timeout: 3_000 });
      await expect(hover).toContainText('persistent hover diagnostic', {
        timeout: 3_000,
      });
      const hoverBox = await hover.boundingBox();
      expect(hoverBox).not.toBeNull();
      return hoverBox;
    };

    await page.waitForFunction(() => globalThis.__modelSwapPhase === 'model-a');
    const modelAHoverBox = await hoverMarkerStart();
    await page.evaluate(() => globalThis.__modelSwapContinue());

    await page.waitForFunction(() => globalThis.__modelSwapPhase === 'model-b');
    const modelBHoverBox = await hoverMarkerStart();
    expect(
      Math.abs(modelBHoverBox.width - modelAHoverBox.width),
    ).toBeLessThanOrEqual(1);
    const slider = page.locator(
      '[data-content-widget="editor.contrib.resizableContentHoverWidget"] .scrollbar.vertical .slider',
    );
    await slider.dispatchEvent('pointerdown', {
      button: 0,
      buttons: 1,
      pointerId: 77,
      clientX: 10,
      clientY: 10,
    });
    await expect(slider).toHaveClass(/\bactive\b/);
    await slider.dispatchEvent('pointerup', {
      button: 0,
      buttons: 0,
      pointerId: 77,
      clientX: 10,
      clientY: 10,
    });
    await expect(slider).not.toHaveClass(/\bactive\b/);
    await page.evaluate(() => globalThis.__modelSwapContinue());

    // The persistent hover scrollable is remounted with model C. Schedule its
    // 500-ms hide callback, retain the detached bar, then let Viewer.dispose
    // cancel the callback. The MoonBit scenario waits past the deadline.
    await page.waitForFunction(() => globalThis.__modelSwapPhase === 'model-c');
    const hoverContent = page.locator(
      '[data-content-widget="editor.contrib.resizableContentHoverWidget"] .monaco-hover-content',
    );
    const verticalBar = page.locator(
      '[data-content-widget="editor.contrib.resizableContentHoverWidget"] .scrollbar.vertical',
    );
    await hoverContent.dispatchEvent('wheel', { deltaY: 20 });
    const classBeforeDispose = await verticalBar.getAttribute('class');
    const retainedBar = await verticalBar.elementHandle();
    expect(retainedBar).not.toBeNull();
    await page.evaluate(() => globalThis.__modelSwapContinue());

    const report = await reporter.waitForReport(testInfo, { suite: 'model_swap' });
    expectMoonBitReportPassed(report, { suite: 'model_swap' });
    expect(await retainedBar.getAttribute('class')).toBe(classBeforeDispose);
  } finally {
    reporter.dispose();
  }
});
