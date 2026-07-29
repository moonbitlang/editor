import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

const outerEditor =
  '.definition-host > .monaco-editor.readonly-editor';
const definitionLink = `${outerEditor} .moonbit-viewer-definition-link`;
const peek = `${outerEditor} .moonbit-viewer-definition-peek`;
const preview =
  `${peek} .moonbit-viewer-definition-peek-preview > ` +
  '.monaco-editor.readonly-editor';
const platformModifier = process.platform === 'darwin' ? 'Meta' : 'Control';

async function settle(page) {
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      ),
  );
}

async function mountDefinitionFixture(page, testInfo) {
  const reporter = await installMoonBitReporter(page);
  await page.goto('/browser-tests/definition.html');
  await page.waitForFunction(() => Boolean(globalThis.__definitionControls));
  const report = await reporter.waitForReport(testInfo, {
    suite: 'definition',
    timeout: 10_000,
  });
  expectMoonBitReportPassed(report, { suite: 'definition' });
  await expect(page.locator(outerEditor)).toContainText('definition_alpha');
  await settle(page);
  return reporter;
}

async function state(page) {
  return page.evaluate(() => globalThis.__definitionControls.state());
}

async function resetScroll(page) {
  await page.evaluate(() => globalThis.__definitionControls.reset_scroll());
  await settle(page);
}

async function textRange(page, rootSelector, line, needle) {
  const result = await page.locator(rootSelector).evaluate(
    (root, request) => {
      const viewLine = root.querySelector(
        `.view-line[data-line="${request.line}"]`,
      );
      if (!viewLine) return null;
      const walker = document.createTreeWalker(
        viewLine,
        NodeFilter.SHOW_TEXT,
      );
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const index = node.textContent.indexOf(request.needle);
        if (index < 0) continue;
        const range = document.createRange();
        range.setStart(node, index);
        range.setEnd(node, index + request.needle.length);
        const rect = range.getBoundingClientRect();
        return {
          x: rect.x + rect.width / 2,
          y: rect.y + rect.height / 2,
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
        };
      }
      return null;
    },
    { line, needle },
  );
  expect(result).not.toBeNull();
  return result;
}

async function referencePoint(page) {
  return textRange(page, outerEditor, 2, 'definition_alpha');
}

async function armDefinitionLink(page) {
  const point = await referencePoint(page);
  await page.mouse.move(2, 2);
  await page.keyboard.down(platformModifier);
  await page.mouse.move(point.x, point.y);
  await expect(page.locator(definitionLink)).toHaveCount(1);
  return point;
}

test('definition link preserves plain selection, paints only while armed, and navigates on an exact modifier click', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    const plainPoint = await referencePoint(page);
    await page.mouse.click(plainPoint.x, plainPoint.y);
    const plain = await state(page);
    expect(plain.position.line).toBe(2);
    expect(plain.selection.anchorLine).toBe(2);
    expect(plain.selection.activeLine).toBe(2);
    expect(plain.selection.anchorColumn).toBe(plain.selection.activeColumn);
    expect(plain.providerCalls).toBe(0);
    await expect(page.locator(definitionLink)).toHaveCount(0);

    await armDefinitionLink(page);
    const linkStyle = await page.locator(definitionLink).evaluate((node) => {
      const style = getComputedStyle(node);
      return {
        cursor: style.cursor,
        textDecorationLine: style.textDecorationLine,
      };
    });
    expect(linkStyle.cursor).toBe('pointer');
    expect(linkStyle.textDecorationLine).toContain('underline');

    await page.keyboard.up(platformModifier);
    await expect(page.locator(definitionLink)).toHaveCount(0);
    expect((await state(page)).position.line).toBe(2);

    const scrollPoint = await armDefinitionLink(page);
    await page.mouse.move(scrollPoint.x, scrollPoint.y);
    await page.mouse.wheel(0, 240);
    await expect.poll(async () => (await state(page)).scrollTop).toBeGreaterThan(0);
    await expect(page.locator(definitionLink)).toHaveCount(0);
    await page.keyboard.up(platformModifier);

    await resetScroll(page);
    const lateModifierPoint = await referencePoint(page);
    await page.mouse.move(lateModifierPoint.x, lateModifierPoint.y);
    await page.mouse.down();
    await page.keyboard.down(platformModifier);
    await page.mouse.up();
    await settle(page);
    const afterLateModifier = await state(page);
    expect(afterLateModifier.position.line).toBe(2);
    expect(afterLateModifier.selection.anchorLine).toBe(2);
    expect(afterLateModifier.selection.activeLine).toBe(2);
    await page.keyboard.up(platformModifier);
    await expect(page.locator(definitionLink)).toHaveCount(0);

    const splitGesturePoint = await armDefinitionLink(page);
    const beforeSplitGesture = await state(page);
    const otherTarget = await textRange(page, outerEditor, 2, 'use');
    await page.mouse.move(splitGesturePoint.x, splitGesturePoint.y);
    await page.mouse.down();
    await page.mouse.move(otherTarget.x, otherTarget.y, { steps: 3 });
    await expect(page.locator(definitionLink)).toHaveCount(0);
    await page.mouse.up();
    await settle(page);
    const afterSplitGesture = await state(page);
    expect(afterSplitGesture.position).toEqual(beforeSplitGesture.position);
    expect(afterSplitGesture.selection).toEqual(beforeSplitGesture.selection);
    await page.keyboard.up(platformModifier);
    await expect(page.locator(definitionLink)).toHaveCount(0);

    const gotoPoint = await armDefinitionLink(page);
    await page.mouse.move(gotoPoint.x, gotoPoint.y);
    await page.mouse.down();
    await page.mouse.up();
    await expect
      .poll(async () => (await state(page)).position)
      .toEqual({ line: 1, column: 5 });
    await page.keyboard.up(platformModifier);
    await expect(page.locator(definitionLink)).toHaveCount(0);
  } finally {
    await page.keyboard.up(platformModifier).catch(() => {});
    reporter.dispose();
  }
});

test('Alt+F12 mounts one measured Peek preview, blocks recursive Peek, and Escape restores outer focus', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    const point = await referencePoint(page);
    await page.mouse.click(point.x, point.y);
    expect((await state(page)).position.line).toBe(2);
    const scrollHeightBeforePeek = (await state(page)).scrollHeight;

    await page.keyboard.press('Alt+F12');
    await expect(page.locator(peek)).toHaveCount(1);
    await expect(page.locator(preview)).toHaveCount(1);
    await expect
      .poll(async () => (await state(page)).scrollHeight)
      .toBeGreaterThan(scrollHeightBeforePeek);
    const geometry = await page.locator(peek).evaluate((root) => {
      const zone = root.closest('[monaco-view-zone]');
      const rootRect = root.getBoundingClientRect();
      const zoneRect = zone?.getBoundingClientRect();
      return {
        rootWidth: rootRect.width,
        rootHeight: rootRect.height,
        zoneWidth: zoneRect?.width ?? 0,
        zoneHeight: zoneRect?.height ?? 0,
      };
    });
    expect(geometry.rootWidth).toBeGreaterThan(0);
    expect(geometry.rootHeight).toBeGreaterThan(0);
    expect(geometry.zoneWidth).toBeGreaterThan(0);
    expect(geometry.zoneHeight).toBeGreaterThan(0);

    const targetRect = await textRange(
      page,
      preview,
      1,
      'definition_alpha',
    );
    const cursorRect = await page.locator(`${preview} .cursor`).first().boundingBox();
    expect(cursorRect).not.toBeNull();
    expect(Math.abs(cursorRect.x - targetRect.left)).toBeLessThan(3);
    expect(Math.abs(cursorRect.y - targetRect.top)).toBeLessThan(3);
    const previewBox = await page.locator(preview).boundingBox();
    expect(previewBox).not.toBeNull();
    expect(targetRect.top).toBeGreaterThanOrEqual(previewBox.y);
    expect(targetRect.top + targetRect.height).toBeLessThanOrEqual(
      previewBox.y + previewBox.height,
    );

    const nestedPoint = await textRange(
      page,
      preview,
      1,
      'definition_alpha',
    );
    await page.mouse.click(nestedPoint.x, nestedPoint.y);
    await page.locator(preview).focus();
    await expect
      .poll(() =>
        page.evaluate(
          (selector) => document.activeElement?.matches(selector) ?? false,
          preview,
        ),
      )
      .toBe(true);
    const callsBeforeNestedPeek = (await state(page)).providerCalls;
    await page.keyboard.press('Alt+F12');
    await settle(page);
    await expect(page.locator(peek)).toHaveCount(1);
    await expect(page.locator(`${peek} ${peek}`)).toHaveCount(0);
    expect((await state(page)).providerCalls).toBe(callsBeforeNestedPeek);

    await page.keyboard.press('Escape');
    await expect(page.locator(peek)).toHaveCount(0);
    await expect(page.locator(preview)).toHaveCount(0);
    await expect
      .poll(async () => (await state(page)).scrollHeight)
      .toBe(scrollHeightBeforePeek);
    await expect
      .poll(() =>
        page.evaluate(
          () =>
            document.activeElement ===
            globalThis.__definitionControls.outerRoot,
        ),
      )
      .toBe(true);
    expect((await state(page)).hasTextFocus).toBe(true);
  } finally {
    reporter.dispose();
  }
});
