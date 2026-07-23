import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

test('runs MoonBit viewer API component checks in the browser', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  try {
    await page.goto('/browser-tests/component.html');
    await expect(page.locator('.monaco-editor.readonly-editor')).toContainText(
      'component_answer',
      { timeout: 10_000 },
    );
    const report = await reporter.waitForReport(testInfo, { suite: 'viewer_api' });
    expectMoonBitReportPassed(report, { suite: 'viewer_api' });
    expect(report.metrics.renderedLines).toBeGreaterThan(0);
    expect(report.metrics.viewLines).toBeGreaterThan(report.metrics.modelLines);
    // The 'keeps' continuation of the wrapped long line sits below the
    // viewport: exactly like Monaco, only the lines intersecting the viewport
    // are in the DOM, so it is asserted after the scroll further down.
    const wrappedHoverLine = page.locator('.view-line').filter({ hasText: 'keeps' });
    await expect(wrappedHoverLine).toHaveCount(0);
    const firstGlyphLeft = (locator) =>
      locator.first().evaluate((node) => {
        const text = node.textContent || '';
        const idx = text.search(/\S/);
        if (idx < 0) return null;
        const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
        let remaining = idx;
        let target = null;
        let offset = 0;
        let current;
        while ((current = walker.nextNode())) {
          const len = current.textContent.length;
          if (remaining < len) {
            target = current;
            offset = remaining;
            break;
          }
          remaining -= len;
        }
        if (!target) return null;
        const range = document.createRange();
        range.setStart(target, offset);
        range.setEnd(target, offset + 1);
        const root = node.closest('.monaco-editor');
        return Math.round(
          range.getBoundingClientRect().left - root.getBoundingClientRect().left,
        );
      });
    // Captured while line 1 is still rendered; the horizontal offset is
    // unaffected by the vertical scroll below.
    const flushLeftGlyph = await firstGlyphLeft(page.locator('.view-line[data-line="1"]'));
    expect(flushLeftGlyph).not.toBeNull();
    const componentZone = page.locator(
      '.component-zone.host-zone-class[monaco-view-zone]',
    );
    await expect(componentZone).toContainText('component view zone');
    await expect(componentZone).toHaveCSS('color', 'rgb(1, 2, 3)');
    const braceLine = page.locator('.view-line').filter({ hasText: '{' });
    await expect(braceLine).toHaveCount(1);
    const zoneBox = await componentZone.boundingBox();
    const braceBox = await braceLine.boundingBox();
    expect(zoneBox).not.toBeNull();
    expect(braceBox).not.toBeNull();
    expect(Math.abs(Math.round(braceBox.y - (zoneBox.y + zoneBox.height)))).toBeLessThanOrEqual(1);
    const signatureStart = page.locator('.view-line').filter({ hasText: 'component_answe' });
    // A view segment near the top of the wrapped body line is a stable drag
    // endpoint (the deeper continuations scroll out of reach). The identifier
    // text repeats on the later `.length()` line, so take the first occurrence.
    const bodyEndLine = page
      .locator('.view-line')
      .filter({ hasText: 'really_long_c' })
      .first();
    await expect(signatureStart).toHaveCount(1);
    await expect(bodyEndLine).toBeVisible();
    const startBox = await signatureStart.boundingBox();
    const endBox = await bodyEndLine.boundingBox();
    expect(startBox).not.toBeNull();
    expect(endBox).not.toBeNull();
    await page.mouse.move(startBox.x + 1, startBox.y + startBox.height / 2);
    await page.mouse.down();
    await page.mouse.move(endBox.x + endBox.width - 1, endBox.y + endBox.height / 2, {
      steps: 4,
    });
    await page.mouse.up();
    await expect.poll(() => page.locator('.selected-text').count(), { timeout: 2_000 }).toBeGreaterThan(0);
    await page.keyboard.press('ControlOrMeta+C');
    const copiedText = await page.evaluate(() => globalThis.__readonlyEditorCopiedText || '');
    expect(copiedText).toContain('component_answer() -> Int');
    expect(copiedText).toContain('let really_l');
    const copiedHtml = await page.evaluate(() => globalThis.__readonlyEditorCopiedHtml || '');
    // Monaco's getRichTextToCopy shape: a styled wrapper div with per-token
    // inline color styles from the token color map (viewModelImpl.ts:1051).
    expect(copiedHtml).toContain('white-space: pre;');
    expect(copiedHtml).toContain('var(--vscode-token-variable)');
    // Collapse the drag selection before the later checks.
    await page.locator('.view-line[data-line="1"]').click();
    await expect.poll(() => page.locator('.selected-text').count(), { timeout: 2_000 }).toBe(0);
    // Scroll the wrapped continuation into the viewport (4 line heights).
    // Exact-viewport rendering: lines leaving the viewport leave the DOM, so
    // line 1 disappears and the 'keeps' continuation appears.
    await page.locator('.overflow-guard').hover();
    await page.mouse.wheel(0, 72);
    await expect(page.locator('.view-line[data-line="1"]')).toHaveCount(0, {
      timeout: 2_000,
    });
    await expect(wrappedHoverLine).toHaveCount(1);
    expect(Number(await wrappedHoverLine.getAttribute('data-line'))).toBeGreaterThan(
      report.metrics.modelLines,
    );
    // wrappingIndent=Same (the default): the wrapped continuation of the
    // two-space-indented line is itself indented, so its first visible glyph
    // sits to the right of a flush-left line's first glyph (the DOM left offset
    // proves the indent renders, not just that the content carries spaces).
    const wrappedGlyph = await firstGlyphLeft(wrappedHoverLine);
    expect(wrappedGlyph).not.toBeNull();
    expect(wrappedGlyph).toBeGreaterThan(flushLeftGlyph + 5);
    // The warning squiggle renders as an absolutely positioned overlay piece
    // (`<div class="cdr squiggly-warning">`, Monaco's DecorationsOverlay), not
    // as an inline span inside the view line. Its 'keeps' range is only
    // decorated now that the line is inside the rendered viewport.
    await expect(page.locator('.cdr.squiggly-warning')).toHaveCount(1, {
      timeout: 10_000,
    });
    // Non-HC squiggle form (editor.css:91-100 + codeEditorWidget.ts theming
    // participant): the visible squiggle is the runtime SVG background from
    // the foreground token; the `::before` background layer and the
    // `border-double` underline exist but stay inert because the
    // `editorWarning-background`/`-border` tokens are null outside
    // high-contrast themes.
    const squiggleForm = await page
      .locator('.cdr.squiggly-warning')
      .evaluate((node) => {
        const style = window.getComputedStyle(node);
        const before = window.getComputedStyle(node, '::before');
        return {
          backgroundImage: style.backgroundImage,
          borderBottomStyle: style.borderBottomStyle,
          beforeDisplay: before.display,
          beforeBackgroundColor: before.backgroundColor,
        };
      });
    expect(squiggleForm.backgroundImage).toContain('data:image/svg+xml');
    expect(squiggleForm.borderBottomStyle).toBe('none');
    expect(squiggleForm.beforeDisplay).toBe('block');
    expect(squiggleForm.beforeBackgroundColor).toBe('rgba(0, 0, 0, 0)');
    // Hover the 'keeps' glyphs themselves: the hover anchors on the mouse
    // position, and the wrap segment's center is not guaranteed to fall
    // inside the provider's 'keeps' range.
    const keepsPoint = await wrappedHoverLine.evaluate((node) => {
      const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
      for (let text = walker.nextNode(); text; text = walker.nextNode()) {
        const index = text.textContent.indexOf('keeps');
        if (index < 0) continue;
        const range = document.createRange();
        range.setStart(text, index);
        range.setEnd(text, index + 'keeps'.length);
        const rect = range.getBoundingClientRect();
        return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
      }
      return null;
    });
    expect(keepsPoint).not.toBeNull();
    await page.mouse.move(keepsPoint.x, keepsPoint.y);
    await expect(page.locator('[data-content-widget="editor.contrib.resizableContentHoverWidget"] .monaco-hover')).toContainText(
      'wrapped component hover',
      { timeout: 3_000 },
    );
  } finally {
    reporter.dispose();
  }
});
