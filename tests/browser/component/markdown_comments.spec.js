import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

const host = '.markdown-comments-host';
const editor = `${host} > .monaco-editor.readonly-editor`;
const zone = `${editor} .moonbit-viewer-markdown-comment`;
const content = '.moonbit-viewer-markdown-comment-content';
const diagram = '.moonbit-viewer-markdown-diagram';
const imageUrl = 'https://images.example.test/markdown-comment.svg';

const fixtureSvg = `
  <svg xmlns="http://www.w3.org/2000/svg" width="180" height="48" viewBox="0 0 180 48">
    <rect width="180" height="48" rx="4" fill="#315f8c"/>
    <text x="12" y="30" fill="white" font-size="16">markdown fixture</text>
  </svg>
`;

async function settle(page, delay = 50) {
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() =>
          requestAnimationFrame(() => requestAnimationFrame(resolve)),
        ),
      ),
  );
  if (delay > 0) await page.waitForTimeout(delay);
}

async function mountMarkdownComments(page, testInfo) {
  await page.route(imageUrl, (route) =>
    route.fulfill({
      status: 200,
      contentType: 'image/svg+xml',
      body: fixtureSvg,
    }),
  );
  await page.addInitScript(() => {
    globalThis.__markdownCommentOpened = [];
    globalThis.open = (...args) => {
      globalThis.__markdownCommentOpened.push(args);
      return { opener: {} };
    };
  });
  const reporter = await installMoonBitReporter(page);
  await page.goto('/browser-tests/component.html?markdownComments=1');
  await page.waitForFunction(() => Boolean(globalThis.__markdownCommentsControls));
  const report = await reporter.waitForReport(testInfo, {
    suite: 'markdown_comments',
    timeout: 15_000,
  });
  expectMoonBitReportPassed(report, { suite: 'markdown_comments' });
  expect(report.metrics.initialZones).toBe(3);
  expect(report.metrics.initialDiagrams).toBe(1);
  await expect(page.locator(zone)).toHaveCount(3);
  await settle(page);
  return reporter;
}

async function control(page, name, ...args) {
  return page.evaluate(
    ({ method, values }) =>
      globalThis.__markdownCommentsControls[method](...values),
    { method: name, values: args },
  );
}

async function state(page) {
  return control(page, 'state');
}

async function zoneRanges(page) {
  return page.locator(zone).evaluateAll((nodes) =>
    nodes.map((node) => [
      Number(node.getAttribute('data-start-line')),
      Number(node.getAttribute('data-end-line')),
    ]),
  );
}

function relativeLuminance(color) {
  const channels = color.map((channel) => {
    const value = channel / 255;
    return value <= 0.04045
      ? value / 12.92
      : ((value + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

function contrastRatio(left, right) {
  const first = relativeLuminance(left);
  const second = relativeLuminance(right);
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
}

async function markdownPalette(page, theme) {
  await page
    .locator('.markdown-comments-shell')
    .evaluate((shell, value) => shell.setAttribute('data-theme', value), theme);
  return page.locator(editor).evaluate((root) => {
    const canvas = document.createElement('canvas');
    canvas.width = 1;
    canvas.height = 1;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    const resolveColor = (value) => {
      context.clearRect(0, 0, 1, 1);
      context.fillStyle = value;
      context.fillRect(0, 0, 1, 1);
      return Array.from(context.getImageData(0, 0, 1, 1).data.slice(0, 3));
    };
    const color = (node, property) =>
      resolveColor(window.getComputedStyle(node)[property]);
    const markdown = root.querySelector('.moonbit-viewer-markdown-comment');
    const fencedCode = root.querySelector(
      '.moonbit-viewer-markdown-comment .monaco-tokenized-source',
    );
    return {
      editor: color(root, 'backgroundColor'),
      markdown: color(markdown, 'backgroundColor'),
      code: color(fencedCode, 'backgroundColor'),
      foreground: color(markdown, 'color'),
    };
  });
}

async function transitionFrames(page, action) {
  return page.evaluate(async (method) => {
    const controls = globalThis.__markdownCommentsControls;
    const frames = [];
    const sample = (phase) => {
      const rawSourceVisible = Array.from(
        document.querySelectorAll(
          '.markdown-comments-host .view-lines .view-line',
        ),
      ).some((node) => node.textContent.includes('///'));
      const replacementCount = document.querySelectorAll(
        '.markdown-comments-host .moonbit-viewer-markdown-comment',
      ).length;
      frames.push({
        phase,
        rawSourceVisible,
        replacementCount,
        sourceAndReplacement: rawSourceVisible && replacementCount > 0,
      });
    };
    await new Promise((resolve) =>
      requestAnimationFrame(() => {
        sample('before');
        controls[method]();
        sample('synchronous');
        requestAnimationFrame(() => {
          sample('first-frame');
          requestAnimationFrame(() => {
            sample('second-frame');
            resolve();
          });
        });
      }),
    );
    return frames;
  }, action);
}

test('public Viewer replaces whole-line source with themed Markdown while model and native input stay truthful', async ({
  page,
}, testInfo) => {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    expect(await zoneRanges(page)).toEqual([
      [1, 3],
      [5, 9],
      [10, 25],
    ]);

    const zones = page.locator(zone);
    await expect(zones.nth(0).locator('h1')).toHaveText('Start comment');
    await expect(zones.nth(1).locator('h2')).toHaveText('Middle comment');
    await expect(zones.nth(1).locator('strong')).toHaveText(
      'same-key initial phrase',
    );
    await expect(zones.nth(1).locator('li')).toHaveCount(2);
    const fencedCode = zones.nth(2).locator('.monaco-tokenized-source');
    await expect(fencedCode).toContainText(
      'let fenced_value = 42',
    );
    await expect(fencedCode.locator('.mtk3')).not.toHaveCount(0);
    const diagoDiagram = zones
      .nth(2)
      .locator(`${diagram}[data-diagram-language="diago"]`);
    await expect(diagoDiagram).toHaveCount(1);
    await expect(diagoDiagram.locator(':scope > svg')).toHaveCount(1);
    const diagramLayout = await diagoDiagram.evaluate((wrapper) => {
      const svg = wrapper.querySelector(':scope > svg');
      const inner = wrapper.closest(
        '.moonbit-viewer-markdown-comment-content',
      );
      const outer = wrapper.closest('.moonbit-viewer-markdown-comment');
      const wrapperRect = wrapper.getBoundingClientRect();
      const svgRect = svg.getBoundingClientRect();
      const innerRect = inner.getBoundingClientRect();
      const outerRect = outer.getBoundingClientRect();
      const viewBox = svg.viewBox.baseVal;
      return {
        wrapperHeight: wrapperRect.height,
        wrapperWidth: wrapperRect.width,
        wrapperClientHeight: wrapper.clientHeight,
        wrapperClientWidth: wrapper.clientWidth,
        wrapperScrollHeight: wrapper.scrollHeight,
        svgHeight: svgRect.height,
        svgWidth: svgRect.width,
        svgAspectRatio: svgRect.width / svgRect.height,
        viewBoxAspectRatio: viewBox.width / viewBox.height,
        expectedMaxHeight: Math.min(window.innerHeight * 0.5, 480),
        innerClientWidth: inner.clientWidth,
        innerHeight: inner.offsetHeight,
        outerHeight: outerRect.height,
        outerStyleHeight: Number.parseFloat(outer.style.height),
        wrapperWithinContent:
          wrapperRect.left >= innerRect.left - 1 &&
          wrapperRect.right <= innerRect.right + 1,
        svgWithinWrapper:
          svgRect.left >= wrapperRect.left - 1 &&
          svgRect.right <= wrapperRect.right + 1,
        diagramWithinMeasuredHeight: wrapperRect.bottom <= innerRect.bottom + 1,
        overflowX: window.getComputedStyle(wrapper).overflowX,
        overflowY: window.getComputedStyle(wrapper).overflowY,
        wrapperMaxWidth: window.getComputedStyle(wrapper).maxWidth,
        svgDisplay: window.getComputedStyle(svg).display,
        svgMaxWidth: window.getComputedStyle(svg).maxWidth,
      };
    });
    expect(diagramLayout).toMatchObject({
      wrapperWithinContent: true,
      svgWithinWrapper: true,
      diagramWithinMeasuredHeight: true,
      overflowX: 'auto',
      overflowY: 'auto',
      wrapperMaxWidth: '100%',
      svgDisplay: 'block',
      svgMaxWidth: '100%',
    });
    expect(diagramLayout.wrapperHeight).toBeGreaterThan(0);
    expect(diagramLayout.svgHeight).toBeGreaterThan(0);
    expect(
      Math.abs(
        diagramLayout.wrapperClientHeight - diagramLayout.expectedMaxHeight,
      ),
    ).toBeLessThanOrEqual(1);
    expect(
      Math.abs(diagramLayout.wrapperHeight - diagramLayout.wrapperClientHeight),
    ).toBeLessThanOrEqual(1);
    expect(diagramLayout.wrapperScrollHeight).toBeGreaterThan(
      diagramLayout.wrapperClientHeight + 1,
    );
    expect(diagramLayout.svgHeight).toBeGreaterThan(
      diagramLayout.wrapperClientHeight + 1,
    );
    expect(
      Math.abs(
        diagramLayout.svgAspectRatio - diagramLayout.viewBoxAspectRatio,
      ),
    ).toBeLessThan(0.001);
    expect(diagramLayout.wrapperWidth).toBeLessThanOrEqual(
      diagramLayout.innerClientWidth + 1,
    );
    expect(diagramLayout.svgWidth).toBeLessThanOrEqual(
      diagramLayout.wrapperClientWidth + 1,
    );
    expect(
      Math.abs(diagramLayout.outerHeight - diagramLayout.innerHeight),
    ).toBeLessThanOrEqual(1);
    expect(
      Math.abs(diagramLayout.outerStyleHeight - diagramLayout.innerHeight),
    ).toBeLessThanOrEqual(1);

    const renderedImage = zones.nth(2).locator('img');
    await expect(renderedImage).toHaveAttribute('src', imageUrl);
    await expect
      .poll(() =>
        renderedImage.evaluate((node) => ({
          complete: node.complete,
          width: node.naturalWidth,
          height: node.naturalHeight,
        })),
      )
      .toEqual({ complete: true, width: 180, height: 48 });

    // The retained ViewZones container is intentionally aria-hidden, so this
    // deferred-accessibility surface cannot be located through the role tree.
    const link = zones.nth(0).locator('a');
    await expect(link).toHaveText('fixture link');
    await expect(link).toHaveAttribute('role', 'link');
    await expect(link).toHaveAttribute('tabindex', '0');
    await expect(link).not.toHaveAttribute('href', /.+/);
    await expect(zones.nth(0).locator(content)).toHaveCSS(
      'user-select',
      'text',
    );
    await expect(page.locator(`${editor} .view-zones`)).toHaveAttribute(
      'aria-hidden',
      'true',
    );

    await expect
      .poll(() =>
        zones.evaluateAll((nodes) =>
          nodes.every((outer) => {
            const inner = outer.querySelector(
              '.moonbit-viewer-markdown-comment-content',
            );
            const outerHeight = outer.getBoundingClientRect().height;
            const innerHeight = inner.offsetHeight;
            const styleHeight = Number.parseFloat(outer.style.height);
            return (
              innerHeight > 0 &&
              outerHeight > 0 &&
              Math.abs(outerHeight - innerHeight) <= 1 &&
              Math.abs(styleHeight - innerHeight) <= 1
            );
          }),
        ),
      )
      .toBe(true);

    const geometry = await page.locator(editor).evaluate((root) => {
      const rect = (node) => {
        const value = node.getBoundingClientRect();
        return {
          top: value.top,
          bottom: value.bottom,
          left: value.left,
          height: value.height,
        };
      };
      const byRange = (start, end) =>
        root.querySelector(
          `.moonbit-viewer-markdown-comment[data-start-line="${start}"][data-end-line="${end}"]`,
        );
      const lines = Array.from(root.querySelectorAll('.view-lines .view-line'));
      const lineWith = (needle) =>
        lines.find((node) => node.textContent.includes(needle));
      return {
        start: rect(byRange(1, 3)),
        middle: rect(byRange(5, 9)),
        eof: rect(byRange(10, 25)),
        alpha: rect(lineWith('alpha_code_truth')),
        omega: rect(lineWith('omega_code_truth')),
        startHeading: rect(byRange(1, 3).querySelector('h1')),
        eofCode: rect(
          byRange(10, 25).querySelector('.monaco-tokenized-source'),
        ),
        alphaContent: rect(
          lineWith('alpha_code_truth').querySelector('.view-line-content'),
        ),
        omegaContent: rect(
          lineWith('omega_code_truth').querySelector('.view-line-content'),
        ),
        visibleLineCount: lines.length,
        visibleSourceText: lines.map((node) => node.textContent).join('\n'),
      };
    });
    expect(geometry.start.bottom).toBeLessThanOrEqual(geometry.alpha.top + 1);
    expect(geometry.alpha.bottom).toBeLessThanOrEqual(geometry.middle.top + 1);
    expect(geometry.middle.bottom).toBeLessThanOrEqual(geometry.omega.top + 1);
    expect(geometry.omega.bottom).toBeLessThanOrEqual(geometry.eof.top + 1);
    expect(
      Math.abs(geometry.startHeading.left - geometry.alphaContent.left),
    ).toBeLessThanOrEqual(1);
    expect(
      Math.abs(geometry.eofCode.left - geometry.omegaContent.left),
    ).toBeLessThanOrEqual(1);
    expect(geometry.visibleLineCount).toBeGreaterThan(3);
    expect(geometry.visibleSourceText).not.toContain('///');
    expect(geometry.visibleSourceText).not.toContain('Start comment');

    const initialState = await state(page);
    expect(initialState).toMatchObject({
      attachedKind: 'primary',
      primaryAttachedEditors: 1,
      replacementAttachedEditors: 0,
      selection: {
        anchorLine: 1,
        anchorColumn: 1,
        activeLine: 1,
        activeColumn: 1,
      },
    });
    expect(initialState.attachedValue).toBe(initialState.primaryValue);
    expect(initialState.primaryValue).toContain('/// # Start comment');
    expect(initialState.primaryValue).toContain(
      [
        '/// ```diago',
        '/// direction: down',
        '/// viewer -> markdown: source',
        '/// markdown -> parser: parse',
        '/// parser -> layout: layout',
        '/// layout -> svg: render',
        '/// svg -> browser: mount',
        '/// ```',
      ].join('\n'),
    );
    expect(initialState.primaryValue).toContain(imageUrl);

    // The diagram owns wheel input only while it can consume that delta. The
    // browser keeps native scrolling because the shared listener never calls
    // preventDefault; the editor's scroll position must stay unchanged.
    const diagramBox = await diagoDiagram.boundingBox();
    expect(diagramBox).not.toBeNull();
    await page.mouse.move(
      diagramBox.x + diagramBox.width / 2,
      diagramBox.y + Math.min(100, diagramBox.height / 2),
    );
    const diagramScrollBefore = await diagoDiagram.evaluate(
      (wrapper) => wrapper.scrollTop,
    );
    const editorScrollBefore = (await state(page)).scrollTop;
    await page.mouse.wheel(0, 160);
    await expect
      .poll(() => diagoDiagram.evaluate((wrapper) => wrapper.scrollTop))
      .toBeGreaterThan(diagramScrollBefore);
    expect(
      Math.abs((await state(page)).scrollTop - editorScrollBefore),
    ).toBeLessThanOrEqual(1);

    const boundaryHandoff = await diagoDiagram.evaluate((wrapper) => {
      const owner = wrapper.closest(
        '.moonbit-viewer-markdown-comment-content',
      );
      wrapper.scrollTop = wrapper.scrollHeight;
      let bubbled = 0;
      const observe = (event) => {
        bubbled += 1;
        // Observe the handoff before Monaco consumes the synthetic wheel.
        event.stopPropagation();
      };
      owner.addEventListener('wheel', observe);
      wrapper.dispatchEvent(
        new WheelEvent('wheel', {
          bubbles: true,
          cancelable: true,
          deltaY: 160,
        }),
      );
      owner.removeEventListener('wheel', observe);
      return {
        atBottom:
          wrapper.scrollTop + wrapper.clientHeight >=
          wrapper.scrollHeight - 1,
        bubbled,
      };
    });
    expect(boundaryHandoff).toEqual({ atBottom: true, bubbled: 1 });
    await diagoDiagram.evaluate((wrapper) => {
      wrapper.scrollTop = 0;
    });

    await control(page, 'set_model_selection');
    await control(page, 'focus');
    await control(page, 'clear_input_log');
    expect((await state(page)).selection).toEqual({
      anchorLine: 3,
      anchorColumn: 1,
      activeLine: 3,
      activeColumn: 17,
    });
    await page.keyboard.press('ControlOrMeta+C');
    expect(
      await page.evaluate(() => globalThis.__readonlyEditorCopiedText),
    ).toBe('alpha_code_truth');
    expect(
      await page.evaluate(() => globalThis.__readonlyEditorCopiedHtml),
    ).toContain('alpha_code_truth');
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
      'alpha_code_truth',
    );
    expect((await control(page, 'copies')).at(-1)).toMatchObject({
      defaultPrevented: true,
      nativeSelection: '',
    });

    const nativeSelection = await page.evaluate(() => {
      const controls = globalThis.__markdownCommentsControls;
      controls.set_model_selection();
      controls.focus();
      controls.clear_input_log();
      const target = document.querySelector(
        '.moonbit-viewer-markdown-comment strong',
      );
      const range = document.createRange();
      range.selectNodeContents(target);
      const selection = document.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      return selection.toString();
    });
    expect(nativeSelection).toBe('same-key initial phrase');
    await page.keyboard.press('ControlOrMeta+C');
    expect(await control(page, 'copies')).toEqual([
      expect.objectContaining({
        defaultPrevented: false,
        nativeSelection: 'same-key initial phrase',
      }),
    ]);
    expect(
      await page.evaluate(() => globalThis.__readonlyEditorCopiedText || ''),
    ).toBe('');
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
      'same-key initial phrase',
    );

    await page.evaluate(() => document.getSelection()?.removeAllRanges());
    const selectionBeforeLink = (await state(page)).selection;
    await link.click();
    await link.focus();
    await page.keyboard.press('ArrowLeft');
    await page.keyboard.press('Enter');
    await page.keyboard.press('Space');
    await settle(page);
    expect((await state(page)).selection).toEqual(selectionBeforeLink);
    expect(await page.evaluate(() => globalThis.__markdownCommentOpened)).toEqual([
      ['https://example.test/docs', '_blank', 'noopener,noreferrer'],
      ['https://example.test/docs', '_blank', 'noopener,noreferrer'],
      ['https://example.test/docs', '_blank', 'noopener,noreferrer'],
    ]);
    const keyLog = await control(page, 'keys');
    expect(keyLog.slice(-3)).toEqual([
      expect.objectContaining({
        key: 'ArrowLeft',
        defaultPrevented: false,
        targetRole: 'link',
      }),
      expect.objectContaining({
        key: 'Enter',
        defaultPrevented: true,
        targetRole: 'link',
      }),
      expect.objectContaining({
        key: ' ',
        defaultPrevented: true,
        targetRole: 'link',
      }),
    ]);
  } finally {
    reporter.dispose();
  }
});

test('keeps the Markdown surface distinct from source and fenced code in both themes', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    for (const theme of ['dark', 'light']) {
      const palette = await markdownPalette(page, theme);
      expect(contrastRatio(palette.editor, palette.markdown)).toBeGreaterThan(
        1.03,
      );
      expect(contrastRatio(palette.markdown, palette.code)).toBeGreaterThan(
        1.03,
      );
      expect(
        contrastRatio(palette.foreground, palette.markdown),
      ).toBeGreaterThanOrEqual(4.5);
    }
  } finally {
    reporter.dispose();
  }
});

test('same-key replacement retains zone identity, reflows, and reconciles add remove move atomically', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    const middleSelector = `${zone}[data-start-line="5"][data-end-line="9"]`;
    const oldOuter = await page.locator(middleSelector).elementHandle();
    const oldContent = await page
      .locator(`${middleSelector} ${content}`)
      .elementHandle();
    const oldHeading = await page.locator(`${middleSelector} h2`).elementHandle();
    expect(oldOuter).not.toBeNull();
    expect(oldContent).not.toBeNull();
    expect(oldHeading).not.toBeNull();
    const versionBefore = (await state(page)).primaryVersion;

    const updateFrames = await transitionFrames(page, 'same_key_update');
    expect(updateFrames.map((frame) => frame.sourceAndReplacement)).toEqual([
      false,
      false,
      false,
      false,
    ]);
    expect(updateFrames.every((frame) => !frame.rawSourceVisible)).toBe(true);
    await expect(page.locator(middleSelector)).toContainText('Middle updated');
    await expect(page.locator(middleSelector)).not.toContainText(
      'same-key initial phrase',
    );
    expect(await oldOuter.evaluate((node, selector) =>
      node === document.querySelector(selector), middleSelector)).toBe(true);
    expect(await oldContent.evaluate((node, selector) =>
      node === document.querySelector(selector), `${middleSelector} ${content}`)).toBe(true);
    expect(await oldHeading.evaluate((node) => node.isConnected)).toBe(false);
    expect((await state(page)).primaryVersion).toBeGreaterThan(versionBefore);
    expect(await zoneRanges(page)).toEqual([
      [1, 3],
      [5, 9],
      [10, 25],
    ]);

    const wideHeight = await page
      .locator(`${middleSelector} ${content}`)
      .evaluate((node) => node.offsetHeight);
    await control(page, 'resize', 240);
    await expect
      .poll(() =>
        page
          .locator(`${middleSelector} ${content}`)
          .evaluate((node) => node.offsetHeight),
      )
      .toBeGreaterThan(wideHeight);
    const narrowHeight = await page
      .locator(`${middleSelector} ${content}`)
      .evaluate((node) => node.offsetHeight);
    await expect
      .poll(() =>
        page.locator(middleSelector).evaluate((node) => {
          const box = node.getBoundingClientRect().height;
          const style = Number.parseFloat(node.style.height);
          const inner = node.querySelector(
            '.moonbit-viewer-markdown-comment-content',
          ).offsetHeight;
          return (
            Math.abs(box - inner) <= 1 && Math.abs(style - inner) <= 1
          );
        }),
      )
      .toBe(true);
    expect(await oldOuter.evaluate((node) => node.isConnected)).toBe(true);
    await control(page, 'resize', 620);
    await expect
      .poll(() =>
        page
          .locator(`${middleSelector} ${content}`)
          .evaluate((node) => node.offsetHeight),
      )
      .toBeLessThan(narrowHeight);

    const previousZones = await page.locator(zone).elementHandles();
    const restructureFrames = await transitionFrames(page, 'restructure');
    expect(restructureFrames.every((frame) => !frame.sourceAndReplacement)).toBe(
      true,
    );
    expect(restructureFrames.every((frame) => !frame.rawSourceVisible)).toBe(true);
    await expect(page.locator(zone)).toHaveCount(3);
    await expect(page.locator(zone)).toContainText([
      'Middle moved',
      'Added comment',
      'EOF moved',
    ]);
    expect(await zoneRanges(page)).toEqual([
      [2, 4],
      [5, 7],
      [8, 10],
    ]);
    for (const previous of previousZones) {
      expect(await previous.evaluate((node) => node.isConnected)).toBe(false);
    }
    await expect(page.locator(editor)).not.toContainText('Start comment');
    expect((await state(page)).attachedValue).toContain('/// ### Added comment');
    expect(
      await page
        .locator(`${editor} .view-lines`)
        .evaluate((node) => node.textContent),
    ).not.toContain('///');
  } finally {
    reporter.dispose();
  }
});

test('folding hides a Markdown zone for another hidden source while its own source remains ignored', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    await control(page, 'folding_source');
    await expect(page.locator(zone)).toHaveCount(1);
    await expect(page.locator(zone)).toContainText('Folded Markdown comment');
    expect(await zoneRanges(page)).toEqual([[2, 4]]);
    const retainedZone = await page.locator(zone).elementHandle();
    expect(retainedZone).not.toBeNull();

    // The comment contribution's own hidden-source projection must not hide
    // its replacement zone.
    await expect(page.locator(zone)).toBeVisible();
    await expect(page.locator(zone)).toHaveAttribute(
      'monaco-visible-view-zone',
      'true',
    );
    await expect(page.locator(editor)).toContainText('folded_child_code');

    const expanded = page.locator(
      `${editor} .margin-view-overlays .cldr.codicon-folding-expanded`,
    );
    const collapsed = page.locator(
      `${editor} .margin-view-overlays .cldr.codicon-folding-collapsed`,
    );
    await expect(expanded).toHaveCount(1);
    await expanded.click({ force: true });

    // Folding is a distinct hidden-area source, so it suppresses both the
    // indented code and the retained replacement zone.
    await expect(page.locator(editor)).not.toContainText('folded_child_code');
    await expect(page.locator(zone)).not.toBeVisible();
    await expect(collapsed).toHaveCount(1);
    expect(await retainedZone.evaluate((node) => node.isConnected)).toBe(true);

    await collapsed.click({ force: true });
    await expect(page.locator(editor)).toContainText('folded_child_code');
    await expect(page.locator(zone)).toBeVisible();
    expect(
      await retainedZone.evaluate(
        (node) =>
          node ===
          document.querySelector('.moonbit-viewer-markdown-comment'),
      ),
    ).toBe(true);
  } finally {
    reporter.dispose();
  }
});

test('offscreen Markdown measures before first reveal and reflows without a scroll jump', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    await control(page, 'offscreen_source');
    await expect(page.locator(zone)).toHaveCount(1);
    expect(await zoneRanges(page)).toEqual([[81, 91]]);
    const retained = await page.locator(zone).elementHandle();
    expect(retained).not.toBeNull();
    await expect(page.locator(zone)).not.toBeVisible();

    // Eighty short visible lines contribute 1440px. The provisional zone is
    // only one 18px line; crossing this threshold proves the still-offscreen
    // heading/list/image body has already entered scroll geometry.
    await expect
      .poll(async () => (await state(page)).scrollHeight)
      .toBeGreaterThan(1560);
    const wideHeight = (await state(page)).scrollHeight;

    await control(page, 'resize', 240);
    await expect(page.locator(zone)).not.toBeVisible();
    await expect
      .poll(async () => (await state(page)).scrollHeight)
      .toBeGreaterThan(wideHeight + 20);
    const narrowHeight = (await state(page)).scrollHeight;

    await control(page, 'scroll_to_bottom');
    await settle(page);
    await expect(page.locator(zone)).toBeVisible();
    expect(
      await retained.evaluate(
        (node) =>
          node ===
          document.querySelector('.moonbit-viewer-markdown-comment'),
      ),
    ).toBe(true);
    await expect
      .poll(async () =>
        Math.abs((await state(page)).scrollHeight - narrowHeight),
      )
      .toBeLessThanOrEqual(1);
    await expect
      .poll(() =>
        page.locator(zone).evaluate((outer) => {
          const inner = outer.querySelector(
            '.moonbit-viewer-markdown-comment-content',
          );
          return Math.abs(outer.getBoundingClientRect().height - inner.offsetHeight);
        }),
      )
      .toBeLessThanOrEqual(1);
  } finally {
    reporter.dispose();
  }
});

test('model detach replacement reattach and Viewer disposal release every rendered zone', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    const initialRoot = await page.locator(editor).elementHandle();
    const initialZone = await page.locator(zone).first().elementHandle();
    expect(initialRoot).not.toBeNull();
    expect(initialZone).not.toBeNull();

    await control(page, 'detach');
    await settle(page);
    // Detach restores the no-model placeholder, which deliberately carries
    // the same editor root classes but has no live view/model DOM.
    await expect(page.locator(editor)).toHaveCount(1);
    await expect(page.locator(`${editor} .lines-content`)).toHaveCount(0);
    await expect(page.locator(zone)).toHaveCount(0);
    expect(await initialRoot.evaluate((node) => node.isConnected)).toBe(false);
    expect(await initialZone.evaluate((node) => node.isConnected)).toBe(false);
    expect(await state(page)).toMatchObject({
      attachedKind: 'none',
      attachedValue: '',
      primaryAttachedEditors: 0,
      replacementAttachedEditors: 0,
    });

    await control(page, 'attach_replacement');
    await expect(page.locator(editor)).toHaveCount(1);
    await expect(page.locator(zone)).toHaveCount(1);
    await expect(page.locator(zone)).toContainText('Replacement comment');
    expect(await zoneRanges(page)).toEqual([[2, 4]]);
    expect(await state(page)).toMatchObject({
      attachedKind: 'replacement',
      replacementAttachedEditors: 1,
      primaryAttachedEditors: 0,
    });
    const replacementRoot = await page.locator(editor).elementHandle();
    const replacementZone = await page.locator(zone).elementHandle();

    await control(page, 'reattach_primary');
    await expect(page.locator(zone)).toHaveCount(3);
    await expect(page.locator(zone).first()).toContainText('Start comment');
    expect(await replacementRoot.evaluate((node) => node.isConnected)).toBe(false);
    expect(await replacementZone.evaluate((node) => node.isConnected)).toBe(false);
    expect(await state(page)).toMatchObject({
      attachedKind: 'primary',
      primaryAttachedEditors: 1,
      replacementAttachedEditors: 0,
    });
    const reattachedZones = await page.locator(zone).elementHandles();
    expect(
      await reattachedZones[0].evaluate(
        (node, original) => node === original,
        initialZone,
      ),
    ).toBe(false);

    await control(page, 'dispose');
    await control(page, 'dispose');
    await settle(page);
    await expect(page.locator(editor)).toHaveCount(0);
    await expect(page.locator(zone)).toHaveCount(0);
    await expect(page.locator(host)).toBeEmpty();
    expect(await state(page)).toMatchObject({
      attachedKind: 'none',
      attachedValue: '',
      primaryAttachedEditors: 0,
      replacementAttachedEditors: 0,
      disposed: true,
    });
    for (const rendered of reattachedZones) {
      expect(await rendered.evaluate((node) => node.isConnected)).toBe(false);
    }
  } finally {
    reporter.dispose();
  }
});
