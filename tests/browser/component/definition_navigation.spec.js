import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

const outerEditor =
  '.definition-host > .monaco-editor.readonly-editor';
const definitionLink = `${outerEditor} .moonbit-viewer-definition-link`;
const peek = `${outerEditor} .moonbit-viewer-references-peek`;
const preview =
  `${peek} .moonbit-viewer-references-peek-preview > ` +
  '.monaco-editor.readonly-editor';
const markdownEditor =
  '.definition-markdown-host > .moonbit-viewer-markdown-document';
const markdownDefinitionLink =
  `${markdownEditor} .moonbit-viewer-markdown-definition-link`;
const markdownPeek =
  `${markdownEditor} > .moonbit-viewer-markdown-document-overlays > ` +
  '.moonbit-viewer-references-peek-overlay';
const markdownPreview =
  `${markdownPeek} .moonbit-viewer-references-peek-preview > ` +
  '.moonbit-viewer-markdown-document';
const contextMenu =
  'body > .moonbit-context-menu:not(.moonbit-context-submenu)';
const goToDefinitionAction =
  `${contextMenu} ` +
  '[data-context-menu-command="editor.action.revealDefinition"]';
const peekDefinitionAction =
  `${contextMenu} ` +
  '[data-context-menu-command="editor.action.peekDefinition"]';
const peekReferencesAction =
  `${contextMenu} ` +
  '[data-context-menu-command="editor.action.referenceSearch.trigger"]';
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

async function markdownState(page) {
  return page.evaluate(
    () => globalThis.__definitionControls.markdown_state(),
  );
}

async function resetScroll(page) {
  await page.evaluate(() => globalThis.__definitionControls.reset_scroll());
  await settle(page);
}

async function contextMenuDefaultPrevented(page, probeSelector, gesture) {
  await page.evaluate((selector) => {
    globalThis.__definitionContextMenuDefaultPrevented = null;
    document.querySelector(selector).addEventListener(
      'contextmenu',
      (event) => {
        globalThis.__definitionContextMenuDefaultPrevented =
          event.defaultPrevented;
      },
      { once: true },
    );
  }, probeSelector);
  await gesture();
  await expect
    .poll(() =>
      page.evaluate(
        () => globalThis.__definitionContextMenuDefaultPrevented,
      ),
    )
    .not.toBeNull();
  return page.evaluate(
    () => globalThis.__definitionContextMenuDefaultPrevented,
  );
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

async function markdownTextRange(page, needle, semantic, occurrence = 0) {
  const result = await page.locator(markdownEditor).evaluate(
    (root, request) => {
      const candidates = request.semantic
        ? root.querySelectorAll('.moonbit-viewer-markdown-code-line')
        : root.querySelectorAll(
            '.moonbit-viewer-markdown-code-block:not([data-markdown-semantic])',
          );
      let seen = 0;
      for (const candidate of candidates) {
        const walker = document.createTreeWalker(
          candidate,
          NodeFilter.SHOW_TEXT,
        );
        const nodes = [];
        let text = '';
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          nodes.push({ node, start: text.length });
          text += node.textContent;
        }
        for (
          let index = text.indexOf(request.needle);
          index >= 0;
          index = text.indexOf(request.needle, index + 1)
        ) {
          if (seen++ !== request.occurrence) continue;
          const start = nodes.findLast((entry) => entry.start <= index);
          const endOffset = index + request.needle.length;
          const end = nodes.findLast(
            (entry) => entry.start <= endOffset,
          );
          const range = document.createRange();
          range.setStart(start.node, index - start.start);
          range.setEnd(end.node, endOffset - end.start);
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
      }
      return null;
    },
    { needle, semantic, occurrence },
  );
  expect(result).not.toBeNull();
  return result;
}

async function armDefinitionLink(page) {
  const point = await referencePoint(page);
  await page.mouse.move(2, 2);
  await page.keyboard.down(platformModifier);
  await page.mouse.move(point.x, point.y);
  await expect(page.locator(definitionLink)).toHaveCount(1);
  return point;
}

test('HTML context menu preserves an enclosing selection and runs Go to Definition after closing', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    await page.evaluate(
      () => globalThis.__definitionControls.select_reference(),
    );
    const point = await referencePoint(page);
    expect(
      await contextMenuDefaultPrevented(page, outerEditor, () =>
        page.mouse.click(point.x, point.y, { button: 'right' }),
      ),
    ).toBe(true);
    await expect(page.locator(contextMenu)).toHaveCount(1);
    await expect(page.locator(`${contextMenu} [role="menu"]`)).toHaveCount(1);
    await expect(page.locator(`${contextMenu} [role="menuitem"]`)).toHaveCount(
      3,
    );
    await expect(page.locator(goToDefinitionAction)).toContainText(
      'Go to Definition',
    );
    await expect(page.locator(peekDefinitionAction)).toContainText(
      'Peek Definition',
    );
    await expect(page.locator(peekReferencesAction)).toContainText(
      'Peek References',
    );
    const menuState = await page.locator(contextMenu).evaluate((root) => {
      const item = root.querySelector('.action-menu-item');
      const menu = root.querySelector('.monaco-menu');
      const keybinding = root.querySelector('.keybinding');
      const style = getComputedStyle(menu);
      return {
        activeInside: root.contains(document.activeElement),
        itemHeight: item.getBoundingClientRect().height,
        background: style.backgroundColor,
        fontSize: style.fontSize,
        keybindingFontSize: getComputedStyle(keybinding).fontSize,
        position: getComputedStyle(root).position,
      };
    });
    expect(menuState.activeInside).toBe(true);
    expect(menuState.itemHeight).toBe(24);
    expect(menuState.background).not.toBe('rgba(0, 0, 0, 0)');
    expect(menuState.keybindingFontSize).toBe(menuState.fontSize);
    expect(menuState.position).toBe('fixed');
    const selection = (await state(page)).selection;
    expect(selection).toEqual({
      anchorLine: 2,
      anchorColumn: 11,
      activeLine: 2,
      activeColumn: 27,
    });

    await page.keyboard.press('Escape');
    await expect(page.locator(contextMenu)).toHaveCount(0);
    await expect
      .poll(() =>
        page.evaluate(
          () =>
            document.activeElement ===
            globalThis.__definitionControls.outerRoot,
        ),
      )
      .toBe(true);

    await page.mouse.click(point.x, point.y, { button: 'right' });
    await expect(page.locator(contextMenu)).toHaveCount(1);
    await page.keyboard.press('Tab');
    await expect(page.locator(contextMenu)).toHaveCount(0);

    await page.mouse.click(point.x, point.y, { button: 'right' });
    await expect(page.locator(contextMenu)).toHaveCount(1);
    await page.locator('.definition-markdown-host').click({
      position: { x: 4, y: 4 },
    });
    await expect(page.locator(contextMenu)).toHaveCount(0);

    await page.mouse.click(point.x, point.y, { button: 'right' });
    await expect(page.locator(contextMenu)).toHaveCount(1);
    await page.evaluate(() => window.dispatchEvent(new Event('blur')));
    await expect(page.locator(contextMenu)).toHaveCount(0);

    const callsBefore = (await state(page)).providerCalls;
    await page.mouse.click(point.x, point.y, { button: 'right' });
    await page.locator(goToDefinitionAction).click();
    await expect(page.locator(contextMenu)).toHaveCount(0);
    await expect
      .poll(async () => (await state(page)).position)
      .toEqual({ line: 1, column: 5 });
    expect((await state(page)).providerCalls).toBe(callsBefore + 1);
  } finally {
    reporter.dispose();
  }
});

test('Shift+F12 and the context action open provider-backed Peek References', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    const point = await referencePoint(page);
    await page.mouse.click(point.x, point.y);
    const callsBefore = (await state(page)).referencesProviderCalls;

    await page.keyboard.press('Shift+F12');
    await expect(
      page.getByRole('dialog', { name: 'Peek References' }),
    ).toHaveCount(1);
    await expect(page.locator(`${peek} [role="treeitem"]`)).toHaveCount(2);
    await expect(page.locator(peek)).toContainText('2 results');
    await expect
      .poll(async () => (await state(page)).referencesProviderCalls)
      .toBe(callsBefore + 1);
    await page.keyboard.press('Escape');
    await expect(page.locator(peek)).toHaveCount(0);

    // Removing the Code ViewZone may restore a different scroll offset. Read
    // the live token geometry again before the second, independent gesture.
    await settle(page);
    const contextPoint = await referencePoint(page);
    await page.mouse.click(contextPoint.x, contextPoint.y, {
      button: 'right',
    });
    await expect(page.locator(contextMenu)).toHaveCount(1);
    await expect(page.locator(peekReferencesAction)).toContainText(
      process.platform === 'darwin' ? '⇧F12' : 'Shift+F12',
    );
    await page.locator(peekReferencesAction).click();
    await expect(page.locator(contextMenu)).toHaveCount(0);
    await expect(
      page.getByRole('dialog', { name: 'Peek References' }),
    ).toHaveCount(1);
    await expect(page.locator(preview)).toHaveCount(1);
    await expect
      .poll(async () => (await state(page)).referencesProviderCalls)
      .toBe(callsBefore + 2);
    await page.keyboard.press('Escape');
  } finally {
    reporter.dispose();
  }
});

test('Go to Definition flashes the full target range for the VS Code 350ms window', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    await page.locator(outerEditor).evaluate((root) => {
      const trace = {
        appearedAt: null,
        disappearedAt: null,
        rect: null,
      };
      globalThis.__definitionHighlightTrace = trace;
      const sample = () => {
        const highlight = root.querySelector('.symbolHighlight');
        if (highlight && trace.appearedAt === null) {
          const rect = highlight.getBoundingClientRect();
          trace.appearedAt = performance.now();
          trace.rect = {
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
          };
        } else if (
          !highlight &&
          trace.appearedAt !== null &&
          trace.disappearedAt === null
        ) {
          trace.disappearedAt = performance.now();
        }
      };
      new MutationObserver(sample).observe(root, {
        attributes: true,
        childList: true,
        subtree: true,
      });
    });
    const point = await referencePoint(page);
    await page.mouse.click(point.x, point.y);
    await page.keyboard.press('F12');
    await expect
      .poll(() =>
        page.evaluate(
          () => globalThis.__definitionHighlightTrace.appearedAt,
        ),
      )
      .not.toBeNull();
    await expect
      .poll(async () => (await state(page)).position)
      .toEqual({ line: 1, column: 5 });
    const target = await textRange(
      page,
      outerEditor,
      1,
      'definition_alpha',
    );
    const appeared = await page.evaluate(
      () => globalThis.__definitionHighlightTrace.rect,
    );
    expect(Math.abs(appeared.left - target.left)).toBeLessThan(3);
    expect(Math.abs(appeared.top - target.top)).toBeLessThan(3);
    expect(Math.abs(appeared.width - target.width)).toBeLessThan(3);

    await expect
      .poll(() =>
        page.evaluate(
          () => globalThis.__definitionHighlightTrace.disappearedAt,
        ),
      )
      .not.toBeNull();
    const duration = await page.evaluate(() => {
      const trace = globalThis.__definitionHighlightTrace;
      return trace.disappearedAt - trace.appearedAt;
    });
    expect(duration).toBeGreaterThanOrEqual(250);
    expect(duration).toBeLessThan(1000);
    await expect(
      page.locator(`${outerEditor} .symbolHighlight`),
    ).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});

test('an empty definition result shows a request-anchored inline message', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    const point = await textRange(page, outerEditor, 2, 'use');
    await page.mouse.click(point.x, point.y);
    const cursor = await page
      .locator(`${outerEditor} .cursor`)
      .first()
      .boundingBox();
    expect(cursor).not.toBeNull();

    await page.keyboard.press('F12');
    const message = page.locator(
      `${outerEditor} .moonbit-viewer-definition-message`,
    );
    await expect(message).toBeVisible();
    await expect(message).toContainText("No definition found for 'use'");
    await expect(message).toHaveClass(/below/);
    const box = await message.boundingBox();
    expect(box).not.toBeNull();
    expect(Math.abs(box.x - (cursor.x - 6))).toBeLessThan(4);
    expect(box.y).toBeGreaterThanOrEqual(cursor.y + cursor.height - 2);

    await page.keyboard.press('ArrowRight');
    await expect(message).toBeHidden();
  } finally {
    reporter.dispose();
  }
});

test('Shift+F10 fits the menu at a viewport edge and keyboard-runs Peek Definition', async ({
  page,
}, testInfo) => {
  await page.setViewportSize({ width: 800, height: 600 });
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    const point = await referencePoint(page);
    await page.mouse.click(point.x, point.y);
    await page.locator('.definition-host').evaluate((host) => {
      Object.assign(host.style, {
        position: 'fixed',
        right: '0',
        bottom: '0',
        width: '260px',
        height: '70px',
        zIndex: '10',
      });
    });
    await page.evaluate(() => {
      globalThis.__definitionControls.layout_outer();
      globalThis.__definitionControls.focus_outer();
    });
    await settle(page);
    const cursorBox = await page
      .locator(`${outerEditor} .cursor`)
      .first()
      .boundingBox();
    expect(cursorBox).not.toBeNull();

    await page.keyboard.press('Shift+F10');
    await expect(page.locator(contextMenu)).toHaveCount(1);
    await expect
      .poll(() =>
        page.evaluate(
          (selector) =>
            document.activeElement?.matches(selector) ?? false,
          goToDefinitionAction,
        ),
      )
      .toBe(true);
    const menuBox = await page.locator(contextMenu).boundingBox();
    expect(menuBox).not.toBeNull();
    expect(menuBox.x).toBeGreaterThanOrEqual(0);
    expect(menuBox.y).toBeGreaterThanOrEqual(0);
    expect(menuBox.x + menuBox.width).toBeLessThanOrEqual(800);
    expect(menuBox.y + menuBox.height).toBeLessThanOrEqual(600);
    expect(menuBox.x).toBeLessThan(cursorBox.x);
    expect(menuBox.y).toBeLessThan(cursorBox.y);

    await page.keyboard.press('ArrowDown');
    await expect
      .poll(() =>
        page.evaluate(
          (selector) =>
            document.activeElement?.matches(selector) ?? false,
          peekDefinitionAction,
        ),
      )
      .toBe(true);
    await page.keyboard.press('Enter');
    await expect(page.locator(contextMenu)).toHaveCount(0);
    await expect(page.locator(peek)).toHaveCount(1);
    await page.keyboard.press('Escape');
    await expect(page.locator(peek)).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});

test('semantic Markdown shares the HTML menu while ordinary Markdown and scrollbars keep the native menu', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    const ordinary = await markdownTextRange(
      page,
      'definition_alpha',
      false,
      0,
    );
    expect(
      await contextMenuDefaultPrevented(
        page,
        `${markdownEditor} .moonbit-viewer-markdown-document-article`,
        () =>
          page.mouse.click(ordinary.x, ordinary.y, { button: 'right' }),
      ),
    ).toBe(false);
    await expect(page.locator(contextMenu)).toHaveCount(0);
    const proseBox = await page
      .locator(
        `${markdownEditor} ` +
          '.moonbit-viewer-markdown-document-article p',
      )
      .first()
      .boundingBox();
    expect(proseBox).not.toBeNull();
    const prose = { x: proseBox.x + 8, y: proseBox.y + 8 };

    const semantic = await markdownTextRange(
      page,
      'definition_alpha',
      true,
      0,
    );
    expect(
      await contextMenuDefaultPrevented(
        page,
        `${markdownEditor} .moonbit-viewer-markdown-document-article`,
        () =>
          page.mouse.click(semantic.x, semantic.y, { button: 'right' }),
      ),
    ).toBe(true);
    await expect(page.locator(contextMenu)).toHaveCount(1);
    expect(
      await contextMenuDefaultPrevented(
        page,
        `${markdownEditor} .moonbit-viewer-markdown-document-article`,
        () =>
          page.mouse.click(prose.x, prose.y, { button: 'right' }),
      ),
    ).toBe(false);
    await expect(page.locator(contextMenu)).toHaveCount(0);
    const callsAfterNativeFallback = (await markdownState(page)).providerCalls;
    await page.keyboard.press('F12');
    await settle(page);
    expect((await markdownState(page)).providerCalls).toBe(
      callsAfterNativeFallback,
    );

    await page.mouse.click(semantic.x, semantic.y, { button: 'right' });
    await expect(page.locator(contextMenu)).toHaveCount(1);
    await page.keyboard.press('Escape');
    await expect(page.locator(contextMenu)).toHaveCount(0);
    await page.keyboard.press('Shift+F10');
    await expect(page.locator(contextMenu)).toHaveCount(1);
    await expect(page.locator(goToDefinitionAction)).toBeFocused();
    await page.keyboard.press('Escape');

    const callsBefore = (await markdownState(page)).providerCalls;
    await page.mouse.click(semantic.x, semantic.y, { button: 'right' });
    await page.locator(goToDefinitionAction).click();
    await expect(page.locator(contextMenu)).toHaveCount(0);
    await expect
      .poll(async () => (await markdownState(page)).scrollTop)
      .toBeGreaterThan(0);
    expect((await markdownState(page)).providerCalls).toBe(callsBefore + 1);

    const rail = page.locator(
      `${outerEditor} ` +
        '.monaco-scrollable-element.editor-scrollable > .scrollbar.vertical',
    );
    const railBox = await rail.boundingBox();
    expect(railBox).not.toBeNull();
    expect(
      await contextMenuDefaultPrevented(page, outerEditor, () =>
        page.mouse.click(
          railBox.x + railBox.width / 2,
          railBox.y + railBox.height / 2,
          { button: 'right' },
        ),
      ),
    ).toBe(false);
    await expect(page.locator(contextMenu)).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});

test('semantic Markdown runs Peek References from its menu and Shift+F12 anchor', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    const semantic = await markdownTextRange(
      page,
      'definition_alpha',
      true,
      0,
    );
    const callsBefore = (await markdownState(page)).referencesProviderCalls;

    await page.mouse.click(semantic.x, semantic.y, { button: 'right' });
    await expect(page.locator(contextMenu)).toHaveCount(1);
    await page.locator(peekReferencesAction).click();
    await expect(page.locator(markdownPeek)).toHaveAttribute(
      'aria-label',
      'Peek References',
    );
    await expect(page.locator(`${markdownPeek} [role="treeitem"]`)).toHaveCount(
      2,
    );
    await expect(page.locator(markdownPreview)).toHaveCount(1);
    await expect
      .poll(async () => (await markdownState(page)).referencesProviderCalls)
      .toBe(callsBefore + 1);
    await page.keyboard.press('Escape');
    await expect(page.locator(markdownPeek)).toHaveCount(0);

    await page.mouse.click(semantic.x, semantic.y, { button: 'right' });
    await page.keyboard.press('Escape');
    await page.keyboard.press('Shift+F12');
    await expect(page.locator(markdownPeek)).toHaveAttribute(
      'aria-label',
      'Peek References',
    );
    await expect
      .poll(async () => (await markdownState(page)).referencesProviderCalls)
      .toBe(callsBefore + 2);
    await page.keyboard.press('Escape');
  } finally {
    reporter.dispose();
  }
});

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

    const emptyTarget = await textRange(page, outerEditor, 2, 'use');
    await page.keyboard.down(platformModifier);
    await page.mouse.move(emptyTarget.x, emptyTarget.y);
    await settle(page);
    await expect(page.locator(definitionLink)).toHaveCount(0);
    await expect(
      page.locator(`${outerEditor} .moonbit-viewer-definition-message`),
    ).toBeHidden();
    await page.keyboard.up(platformModifier);

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
    const callsBeforeSameWordMove = (await state(page)).providerCalls;
    await page.mouse.move(gotoPoint.left + 2, gotoPoint.y);
    await settle(page);
    expect((await state(page)).providerCalls).toBe(callsBeforeSameWordMove);
    const callsBeforeClick = (await state(page)).providerCalls;
    await page.mouse.down();
    await page.mouse.up();
    await expect
      .poll(async () => (await state(page)).position)
      .toEqual({ line: 1, column: 5 });
    expect((await state(page)).providerCalls).toBe(callsBeforeClick + 1);
    await expect(page.locator(definitionLink)).toHaveCount(0);
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
      .poll(() =>
        page.evaluate(
          (selector) =>
            document.querySelector(selector)?.contains(document.activeElement) ??
            false,
          peek,
        ),
      )
      .toBe(true);
    await expect
      .poll(() => page.locator(peek).getAttribute('aria-hidden'))
      .toBeNull();
    await expect
      .poll(async () => (await state(page)).scrollHeight)
      .toBeGreaterThan(scrollHeightBeforePeek);
    const geometry = await page.locator(peek).evaluate((root) => {
      const editor = root.closest('.monaco-editor');
      const zone = editor?.querySelector(
        '.moonbit-viewer-references-peek-zone[monaco-view-zone]',
      );
      const header = root.querySelector(
        '.moonbit-viewer-references-peek-header',
      );
      const body = root.querySelector('.moonbit-viewer-references-peek-body');
      const previewHost = root.querySelector(
        '.moonbit-viewer-references-peek-preview',
      );
      const list = root.querySelector(
        '.moonbit-viewer-reference-results-tree',
      );
      const nested = previewHost?.firstElementChild;
      const rootRect = root.getBoundingClientRect();
      const editorRect = editor?.getBoundingClientRect();
      const zoneRect = zone?.getBoundingClientRect();
      const headerRect = header?.getBoundingClientRect();
      const bodyRect = body?.getBoundingClientRect();
      const previewRect = previewHost?.getBoundingClientRect();
      const listRect = list?.getBoundingClientRect();
      const nestedRect = nested?.getBoundingClientRect();
      const visibleLineCount = Array.from(
        previewHost?.querySelectorAll('.view-line') ?? [],
      ).filter((line) => {
        const rect = line.getBoundingClientRect();
        return (
          previewRect &&
          rect.bottom > previewRect.top &&
          rect.top < previewRect.bottom
        );
      }).length;
      return {
        rootX: rootRect.x,
        rootWidth: rootRect.width,
        rootHeight: rootRect.height,
        editorX: editorRect?.x ?? 0,
        editorWidth: editorRect?.width ?? 0,
        editorTop: editorRect?.top ?? 0,
        editorBottom: editorRect?.bottom ?? 0,
        rootTop: rootRect.top,
        rootBottom: rootRect.bottom,
        zoneWidth: zoneRect?.width ?? 0,
        zoneHeight: zoneRect?.height ?? 0,
        headerHeight: headerRect?.height ?? 0,
        bodyHeight: bodyRect?.height ?? 0,
        previewX: previewRect?.x ?? 0,
        previewHeight: previewRect?.height ?? 0,
        listX: listRect?.x ?? 0,
        nestedHeight: nestedRect?.height ?? 0,
        visibleLineCount,
      };
    });
    expect(geometry.rootWidth).toBeGreaterThan(0);
    expect(geometry.rootHeight).toBeGreaterThan(0);
    expect(geometry.zoneWidth).toBeGreaterThan(0);
    expect(geometry.zoneHeight).toBeGreaterThan(0);
    expect(Math.abs(geometry.rootX - geometry.editorX)).toBeLessThan(2);
    expect(
      Math.abs(geometry.rootWidth - (geometry.editorWidth - 14)),
    ).toBeLessThan(3);
    expect(Math.abs(geometry.rootHeight - geometry.zoneHeight)).toBeLessThan(2);
    expect(geometry.rootTop).toBeGreaterThanOrEqual(geometry.editorTop - 1);
    expect(geometry.rootBottom).toBeLessThanOrEqual(geometry.editorBottom + 1);
    expect(geometry.headerHeight).toBeGreaterThan(0);
    expect(geometry.bodyHeight).toBeGreaterThan(
      geometry.rootHeight - geometry.headerHeight - 3,
    );
    expect(Math.abs(geometry.previewHeight - geometry.bodyHeight)).toBeLessThan(
      2,
    );
    expect(Math.abs(geometry.nestedHeight - geometry.previewHeight)).toBeLessThan(
      2,
    );
    expect(geometry.previewX).toBeLessThan(geometry.listX);
    expect(geometry.visibleLineCount).toBeGreaterThan(4);
    await expect(
      page.locator(`${peek} .moonbit-viewer-references-peek-title-filename`),
    ).toHaveText('Definitions');
    await expect(
      page.locator(`${peek} .moonbit-viewer-references-peek-title-meta`),
    ).toHaveText('1 result');

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
    const match = page.locator(
      `${preview} .moonbit-viewer-references-peek-reference-match-selected`,
    );
    await expect(match).toHaveCount(1);
    const matchRect = await match.boundingBox();
    expect(matchRect).not.toBeNull();
    expect(Math.abs(matchRect.x - targetRect.left)).toBeLessThan(3);
    expect(Math.abs(matchRect.y - targetRect.top)).toBeLessThan(3);
    expect(Math.abs(matchRect.width - targetRect.width)).toBeLessThan(3);

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

test('same-anchor Alt+F12 toggles Peek closed without another provider request', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    const point = await referencePoint(page);
    await page.mouse.click(point.x, point.y);
    await page.keyboard.press('Alt+F12');
    await expect(page.locator(peek)).toHaveCount(1);
    await expect(page.locator(preview)).toHaveCount(1);
    const callsAfterOpen = (await state(page)).providerCalls;

    await page.evaluate(() => globalThis.__definitionControls.focus_outer());
    await page.keyboard.press('Alt+F12');
    await expect(page.locator(peek)).toHaveCount(0);
    expect((await state(page)).providerCalls).toBe(callsAfterOpen);
    await expect
      .poll(() =>
        page.evaluate(
          () =>
            document.activeElement ===
            globalThis.__definitionControls.outerRoot,
        ),
      )
      .toBe(true);
  } finally {
    reporter.dispose();
  }
});

test('F4 replaces a multi-definition preview without losing preview focus', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    await page.evaluate(() =>
      globalThis.__definitionControls.enable_multiple_definitions(),
    );
    const point = await referencePoint(page);
    await page.mouse.click(point.x, point.y);
    await page.keyboard.press('Alt+F12');
    await expect(page.locator(peek)).toHaveCount(1);
    await expect(page.locator(`${peek} [role="treeitem"]`)).toHaveCount(2);
    await expect(page.locator(preview)).toHaveCount(1);
    const providerCalls = (await state(page)).providerCalls;

    await page.locator(preview).focus();
    await page.keyboard.press('F4');
    await expect(
      page.locator(`${preview} .view-line[data-line="3"]`),
    ).toContainText('filler_line_3');
    const nextTarget = await textRange(page, preview, 3, 'filler_line_3');
    await expect
      .poll(async () => page.locator(`${preview} .cursor`).first().boundingBox())
      .not.toBeNull();
    const nextCursor = await page
      .locator(`${preview} .cursor`)
      .first()
      .boundingBox();
    expect(Math.abs(nextCursor.x - nextTarget.left)).toBeLessThan(3);
    await expect
      .poll(() =>
        page.evaluate(
          (selector) => document.activeElement?.matches(selector) ?? false,
          preview,
        ),
      )
      .toBe(true);
    expect((await state(page)).providerCalls).toBe(providerCalls);

    await page.keyboard.press('Shift+F4');
    await expect(
      page.locator(`${preview} .view-line[data-line="1"]`),
    ).toContainText('definition_alpha');
    const previousTarget = await textRange(
      page,
      preview,
      1,
      'definition_alpha',
    );
    const previousCursor = await page
      .locator(`${preview} .cursor`)
      .first()
      .boundingBox();
    expect(Math.abs(previousCursor.x - previousTarget.left)).toBeLessThan(3);
    await expect
      .poll(() =>
        page.evaluate(
          (selector) => document.activeElement?.matches(selector) ?? false,
          preview,
        ),
      )
      .toBe(true);

    await page.keyboard.press('Escape');
    await expect(page.locator(peek)).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});

test('semantic Markdown projects an exact definition link while ordinary fences and replacement stay inert', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    const point = await markdownTextRange(
      page,
      'definition_alpha',
      true,
      0,
    );
    await page.mouse.move(2, 2);
    await page.keyboard.down(platformModifier);
    await page.mouse.move(point.x, point.y);
    await expect(page.locator(markdownDefinitionLink)).toHaveCount(1);
    const linkBox = await page
      .locator(markdownDefinitionLink)
      .boundingBox();
    expect(linkBox).not.toBeNull();
    expect(Math.abs(linkBox.x - point.left)).toBeLessThan(2);
    expect(Math.abs(linkBox.width - point.width)).toBeLessThan(2);
    const sourceRange = await page
      .locator(markdownDefinitionLink)
      .evaluate((node) => ({
        start: Number(node.dataset.markdownSourceStart),
        end: Number(node.dataset.markdownSourceEnd),
      }));
    expect(sourceRange.end - sourceRange.start).toBe(
      'definition_alpha'.length,
    );

    const callsAfterSemantic = (await markdownState(page)).providerCalls;
    const ordinary = await markdownTextRange(
      page,
      'definition_alpha',
      false,
      0,
    );
    await page.mouse.move(ordinary.x, ordinary.y);
    await settle(page);
    await expect(page.locator(markdownDefinitionLink)).toHaveCount(0);
    expect((await markdownState(page)).providerCalls).toBe(
      callsAfterSemantic,
    );

    await page.mouse.move(point.x, point.y);
    await expect(page.locator(markdownDefinitionLink)).toHaveCount(1);
    await page.evaluate(
      () => globalThis.__definitionControls.replace_markdown_source(),
    );
    await expect(page.locator(markdownDefinitionLink)).toHaveCount(0);
    await page.keyboard.up(platformModifier);

    const freshPoint = await markdownTextRange(
      page,
      'definition_alpha',
      true,
      0,
    );
    // Keep the pointer on the semantic token, but deliver modifier keydown to
    // the other Viewer. Markdown mousedown must trust its current event rather
    // than requiring a prior key/move notification in its own bridge.
    await page.mouse.move(freshPoint.x, freshPoint.y);
    await page.evaluate(() => globalThis.__definitionControls.focus_outer());
    await page.keyboard.down(platformModifier);
    await page.mouse.down();
    await page.mouse.up();
    await expect
      .poll(async () => (await markdownState(page)).scrollTop)
      .toBeGreaterThan(0);
    await page.keyboard.up(platformModifier);
  } finally {
    await page.keyboard.up(platformModifier).catch(() => {});
    reporter.dispose();
  }
});

test('Alt+F12 from semantic Markdown mounts a projection-scoped Peek overlay and restores focus', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    const point = await markdownTextRange(
      page,
      'definition_alpha',
      true,
      0,
    );
    await page.mouse.click(point.x, point.y);
    await page.keyboard.press('Alt+F12');
    await expect(page.locator(markdownPeek)).toHaveCount(1);
    await expect(page.locator(markdownPreview)).toHaveCount(1);

    await page.locator('.definition-markdown-host').evaluate((host) => {
      host.style.width = '640px';
    });
    await settle(page);
    const geometry = await page.locator(markdownPeek).evaluate((root) => {
      const editor = root.closest(
        '.moonbit-viewer-markdown-document',
      );
      const rootRect = root.getBoundingClientRect();
      const editorRect = editor.getBoundingClientRect();
      return {
        width: rootRect.width,
        height: rootRect.height,
        left: rootRect.left,
        right: rootRect.right,
        top: rootRect.top,
        bottom: rootRect.bottom,
        editorLeft: editorRect.left,
        editorRight: editorRect.right,
        editorTop: editorRect.top,
        editorBottom: editorRect.bottom,
      };
    });
    expect(geometry.width).toBeGreaterThan(300);
    expect(geometry.height).toBeGreaterThan(200);
    expect(geometry.left).toBeGreaterThanOrEqual(geometry.editorLeft);
    expect(geometry.right).toBeLessThanOrEqual(geometry.editorRight);
    expect(geometry.top).toBeGreaterThanOrEqual(geometry.editorTop);
    expect(geometry.bottom).toBeLessThanOrEqual(geometry.editorBottom);

    await page.keyboard.press('Escape');
    await expect(page.locator(markdownPeek)).toHaveCount(0);
    await expect
      .poll(() =>
        page.evaluate(
          () =>
            document.activeElement ===
            globalThis.__definitionControls.markdownRoot,
        ),
      )
      .toBe(true);

    const freshPoint = await markdownTextRange(
      page,
      'definition_alpha',
      true,
      0,
    );
    await page.mouse.click(freshPoint.x, freshPoint.y);
    await page.keyboard.press('Alt+F12');
    await expect(page.locator(markdownPeek)).toHaveCount(1);
    await page.evaluate(
      () => globalThis.__definitionControls.replace_markdown_source(),
    );
    await expect(page.locator(markdownPeek)).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});
