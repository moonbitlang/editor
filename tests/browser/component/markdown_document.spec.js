import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

const host = '.markdown-document-host';
const root = `${host} > .moonbit-viewer-markdown-document`;
const viewport = `${root} > .moonbit-viewer-markdown-document-viewport`;
const article = `${viewport} > .moonbit-viewer-markdown-document-article`;
const overlays = `${root} > .moonbit-viewer-markdown-document-overlays`;
const hoverWidget = `${overlays} .moonbit-viewer-markdown-hover-widget`;
const secondaryHost = '.markdown-document-host-secondary';
const secondaryRoot = `${secondaryHost} > .moonbit-viewer-markdown-document`;
const secondaryArticle =
  `${secondaryRoot} .moonbit-viewer-markdown-document-article`;
const secondaryHover =
  `${secondaryRoot} .moonbit-viewer-markdown-hover-widget`;
const diagramViewport = '.moonbit-viewer-markdown-diagram-viewport';
const diagramContent = '.moonbit-viewer-markdown-diagram-content';
const diagramControls = '.moonbit-viewer-markdown-diagram-controls';
const mermaidCdnUrl =
  'https://cdn.jsdelivr.net/npm/mermaid@11.16.0/dist/mermaid.esm.min.mjs';

const fakeMarkdownDocumentMermaidModule = `
  let currentTheme = '';

  export function initialize(options) {
    currentTheme = options.theme;
  }

  export async function render(id, source) {
    return {
      svg:
        '<svg xmlns="http://www.w3.org/2000/svg" width="480" height="180" ' +
        'viewBox="0 0 480 180" data-mermaid-id="' + id + '" ' +
        'data-mermaid-theme="' + currentTheme + '">' +
        '<rect width="480" height="180" fill="#1f2937"/>' +
        '<text x="16" y="36" fill="#f8fafc">' + source + '</text></svg>',
      bindFunctions(root) {
        root.setAttribute('data-fake-mermaid-bound', id);
      },
    };
  }

  export default { initialize, render };
`;

async function diagramTransform(locator) {
  return locator.locator(diagramContent).evaluate((content) => {
    const matrix = new DOMMatrix(getComputedStyle(content).transform);
    return { scale: matrix.a, x: matrix.e, y: matrix.f };
  });
}

async function moveToSourceText(page, articleSelector, text, utf16Delta = 0) {
  const articleLocator = page.locator(articleSelector);
  await articleLocator.evaluate((articleNode, text) => {
    const walker = document.createTreeWalker(
      articleNode,
      NodeFilter.SHOW_TEXT,
    );
    let node;
    while ((node = walker.nextNode())) {
      if (!String(node.textContent || '').includes(text)) continue;
      node.parentElement?.scrollIntoView({
        block: 'center',
        inline: 'nearest',
      });
      return;
    }
    throw new Error(`text node not found: ${text}`);
  }, text);
  await page.waitForTimeout(50);
  const point = await page.locator(articleSelector).evaluate(
    (articleNode, { text, utf16Delta }) => {
      const walker = document.createTreeWalker(
        articleNode,
        NodeFilter.SHOW_TEXT,
      );
      let node;
      while ((node = walker.nextNode())) {
        const index = String(node.textContent || '').indexOf(text);
        if (index < 0) continue;
        const range = document.createRange();
        const boundary = Math.min(
          String(node.textContent || '').length,
          index + utf16Delta,
        );
        range.setStart(node, boundary);
        range.setEnd(node, Math.min(boundary + 1, node.textContent.length));
        const rect = range.getBoundingClientRect();
        return {
          x: rect.left + Math.max(rect.width / 2, 1),
          y: rect.top + Math.max(rect.height / 2, 1),
        };
      }
      throw new Error(`text node not found: ${text}`);
    },
    { text, utf16Delta },
  );
  const viewportSize = page.viewportSize();
  await page.mouse.move(
    Math.max((viewportSize?.width ?? 800) - 1, 0),
    Math.max((viewportSize?.height ?? 600) - 1, 0),
  );
  await page.waitForTimeout(25);
  await page.mouse.move(point.x, point.y);
  return point;
}

async function sourceTextPoints(
  page,
  articleSelector,
  text,
  utf16Deltas,
) {
  const articleLocator = page.locator(articleSelector);
  await articleLocator.evaluate((articleNode, text) => {
    const walker = document.createTreeWalker(
      articleNode,
      NodeFilter.SHOW_TEXT,
    );
    let node;
    while ((node = walker.nextNode())) {
      if (!String(node.textContent || '').includes(text)) continue;
      node.parentElement?.scrollIntoView({
        block: 'center',
        inline: 'nearest',
      });
      return;
    }
    throw new Error(`text node not found: ${text}`);
  }, text);
  await page.waitForTimeout(50);
  return articleLocator.evaluate(
    (articleNode, { text, utf16Deltas }) => {
      const walker = document.createTreeWalker(
        articleNode,
        NodeFilter.SHOW_TEXT,
      );
      let node;
      while ((node = walker.nextNode())) {
        const index = String(node.textContent || '').indexOf(text);
        if (index < 0) continue;
        return utf16Deltas.map((utf16Delta) => {
          const range = document.createRange();
          const boundary = Math.min(
            String(node.textContent || '').length,
            index + utf16Delta,
          );
          range.setStart(node, boundary);
          range.setEnd(node, Math.min(boundary + 1, node.textContent.length));
          const rect = range.getBoundingClientRect();
          return {
            x: rect.left + Math.max(rect.width / 2, 1),
            y: rect.top + Math.max(rect.height / 2, 1),
          };
        });
      }
      throw new Error(`text node not found: ${text}`);
    },
    { text, utf16Deltas },
  );
}

async function moveToSyntheticPadding(page, articleSelector, lineText) {
  const point = await page.locator(articleSelector).evaluate(
    (articleNode, lineText) => {
      const line = Array.from(
        articleNode.querySelectorAll('[data-markdown-code-line]'),
      ).find((candidate) =>
        String(candidate.textContent || '').includes(lineText),
      );
      if (!line) throw new Error(`semantic line not found: ${lineText}`);
      line.scrollIntoView({ block: 'center', inline: 'nearest' });
      const rect = line.getBoundingClientRect();
      return {
        x: rect.left + 1,
        y: rect.top + Math.max(rect.height / 2, 1),
      };
    },
    lineText,
  );
  await page.waitForTimeout(50);
  await page.mouse.move(point.x, point.y);
  return point;
}

async function moveToTrailingLineRegion(page, articleSelector, lineText) {
  const point = await page.locator(articleSelector).evaluate(
    (articleNode, lineText) => {
      const line = Array.from(
        articleNode.querySelectorAll('[data-markdown-code-line]'),
      ).find((candidate) =>
        String(candidate.textContent || '').includes(lineText),
      );
      if (!line) throw new Error(`semantic line not found: ${lineText}`);
      line.scrollIntoView({ block: 'center', inline: 'nearest' });
      const lineRect = line.getBoundingClientRect();
      const block = line.closest('[data-markdown-code-block]');
      if (!block) throw new Error(`semantic block not found: ${lineText}`);
      const blockRect = block.getBoundingClientRect();
      const x = Math.min(lineRect.right + 16, blockRect.right - 4);
      if (x <= lineRect.right) {
        throw new Error(`semantic line has no trailing region: ${lineText}`);
      }
      return {
        x,
        y: lineRect.top + Math.max(lineRect.height / 2, 1),
      };
    },
    lineText,
  );
  await page.waitForTimeout(50);
  await page.mouse.move(point.x, point.y);
  return point;
}

async function hoverCalls(page) {
  return page.evaluate(() =>
    globalThis.__markdownDocumentControls.getHoverCalls(),
  );
}

async function waitForNewHoverCall(page, previousCount) {
  await expect.poll(async () => (await hoverCalls(page)).length).toBe(
    previousCount + 1,
  );
  return (await hoverCalls(page))[previousCount];
}

function sourcePositionAtOffset(source, offset) {
  const before = source.slice(0, offset);
  const lines = before.split('\n');
  return {
    lineNumber: lines.length,
    column: lines.at(-1).length + 1,
  };
}

function fullModelRangeString(source) {
  const lines = source.split('\n');
  return `1:1-${lines.length}:${lines.at(-1).length + 1}`;
}

async function expectNoNewHoverCall(page, previousCount) {
  await page.waitForTimeout(75);
  expect((await hoverCalls(page)).length).toBe(previousCount);
}

async function expectHoverCallCancelled(page, callId) {
  await expect
    .poll(async () => {
      const call = (await hoverCalls(page)).find(
        (candidate) => candidate.id === callId,
      );
      return call?.cancelled;
    })
    .toBe(true);
}

test('mounts zoom and drag controls for D2 and Mermaid in Markdown documents', async ({
  page,
}, testInfo) => {
  await page.route(mermaidCdnUrl, (route) =>
    route.fulfill({
      status: 200,
      contentType: 'text/javascript',
      headers: {
        'access-control-allow-origin': '*',
        'cache-control': 'no-store',
      },
      body: fakeMarkdownDocumentMermaidModule,
    }),
  );
  const reporter = await installMoonBitReporter(page);
  try {
    await page.goto('/browser-tests/component.html?markdownDocument=1');
    await page.waitForFunction(() =>
      Boolean(globalThis.__markdownDocumentControls),
    );
    const report = await reporter.waitForReport(testInfo, {
      suite: 'markdown_document',
    });
    expectMoonBitReportPassed(report, { suite: 'markdown_document' });

    await page.evaluate(() =>
      globalThis.__markdownDocumentControls.showDiagrams(),
    );

    const viewports = page.locator(`${article} ${diagramViewport}`);
    await expect(viewports).toHaveCount(2);
    const d2 = page.locator(
      `${article} [data-diagram-language="diago"]${diagramViewport}`,
    );
    const mermaid = page.locator(
      `${article} [data-diagram-language="mermaid"]${diagramViewport}`,
    );
    await expect(d2).toHaveCount(1);
    await expect(mermaid).toHaveCount(1);
    await expect(d2).toHaveAttribute(
      'aria-label',
      'Interactive Diago diagram',
    );
    await expect(mermaid).toHaveAttribute(
      'aria-label',
      'Interactive Mermaid diagram',
    );
    await expect(d2.getByRole('button')).toHaveCount(4);
    await expect(mermaid.getByRole('button')).toHaveCount(4);
    await expect(
      d2.getByRole('toolbar', { name: 'D2 diagram controls' }),
    ).toBeVisible();
    await expect(
      mermaid.getByRole('toolbar', { name: 'Mermaid diagram controls' }),
    ).toBeVisible();
    await expect(d2).toHaveCSS('z-index', '0');
    await expect(d2.locator(diagramControls)).toHaveCSS(
      'pointer-events',
      'auto',
    );
    await expect(d2.locator(diagramControls)).toHaveCSS('opacity', '0.9');

    await d2.hover();
    const beforeZoom = await diagramTransform(d2);
    await d2.getByRole('button', { name: 'Zoom in' }).click();
    await expect
      .poll(async () => (await diagramTransform(d2)).scale)
      .toBeGreaterThan(beforeZoom.scale);
    const panToggle = d2.getByRole('button', { name: 'Toggle pan mode' });
    await panToggle.click();
    await expect(panToggle).toHaveAttribute('aria-pressed', 'true');
    const beforePan = await diagramTransform(d2);
    const box = await d2.boundingBox();
    expect(box).not.toBeNull();
    await page.mouse.move(box.x + box.width * 0.35, box.y + box.height * 0.5);
    await page.mouse.down();
    await page.mouse.move(
      box.x + box.width * 0.35 + 50,
      box.y + box.height * 0.5 + 30,
      { steps: 4 },
    );
    await page.mouse.up();
    await expect
      .poll(async () => {
        const afterPan = await diagramTransform(d2);
        return Math.abs(afterPan.x - beforePan.x) +
          Math.abs(afterPan.y - beforePan.y);
      })
      .toBeGreaterThan(10);

    await page.evaluate(() => {
      globalThis.__markdownDocumentRetainedDiagrams = Array.from(
        document.querySelectorAll(
          '.markdown-document-host .moonbit-viewer-markdown-diagram-viewport',
        ),
      );
      globalThis.__markdownDocumentControls.replaceSource();
    });
    await expect(page.locator(article)).toContainText('replacement_answer');
    expect(
      await page.evaluate(() =>
        globalThis.__markdownDocumentRetainedDiagrams.map((diagram) => ({
          connected: diagram.isConnected,
          enhanced: diagram.classList.contains(
            'moonbit-viewer-markdown-diagram-viewport',
          ),
        })),
      ),
    ).toEqual([
      { connected: false, enhanced: false },
      { connected: false, enhanced: false },
    ]);
  } finally {
    reporter.dispose();
  }
});

test('renders and refreshes the editor-owned readonly Markdown presentation', async ({
  page,
}, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  try {
    await page.goto('/browser-tests/component.html?markdownDocument=1');
    await page.waitForFunction(() =>
      Boolean(globalThis.__markdownDocumentControls),
    );
    const report = await reporter.waitForReport(testInfo, {
      suite: 'markdown_document',
    });
    expectMoonBitReportPassed(report, { suite: 'markdown_document' });
    expect(report.metrics.rootCount).toBe(1);
    expect(report.metrics.codeBlocks).toBe(3);
    expect(report.metrics.keywordTokens).toBeGreaterThan(0);
    expect(report.metrics.semanticLines).toBe(8);
    expect(report.metrics.phraseDividers).toBe(1);
    expect(report.metrics.diagnostics).toBeGreaterThan(0);
    expect(report.metrics.sourceUri).toBe(
      'inmemory://component/literate.mbt.md',
    );
    const initialSource = await page.evaluate(() =>
      globalThis.__markdownDocumentControls.getModelValue(),
    );

    await expect(page.locator(root)).toHaveCount(1);
    await expect(page.locator(`${host} > .monaco-editor`)).toHaveCount(0);
    await expect(page.locator(article)).toContainText(
      'Readonly Markdown document',
    );
    await expect(
      page.locator(`${article} [data-markdown-code-block="0"]`),
    ).toHaveAttribute('data-markdown-semantic', 'moonbit-check');
    await expect(
      page.locator(`${article} [data-markdown-code-block="1"]`),
    ).toHaveAttribute('data-markdown-semantic', 'moonbit-check');
    await expect(
      page.locator(`${article} [data-markdown-code-block="2"]`),
    ).not.toHaveAttribute('data-markdown-semantic', /.+/);
    const phraseDivider = page.locator(
      `${article} [data-markdown-phrase-divider="true"]`,
    );
    await expect(phraseDivider).toHaveCount(1);
    await expect(phraseDivider).toHaveText('///|');
    await expect(phraseDivider).toHaveAttribute('role', 'separator');
    const dividerPresentation = await phraseDivider.evaluate((node) => {
      const sourceStart = Number(
        node.getAttribute('data-markdown-source-start'),
      );
      const sourceEnd = Number(node.getAttribute('data-markdown-source-end'));
      const rect = node.getBoundingClientRect();
      const blockRect = node
        .closest('[data-markdown-code-block]')
        .getBoundingClientRect();
      const token = node.querySelector('span');
      const rule = getComputedStyle(node, '::after');
      return {
        sourceStart,
        sourceEnd,
        tokenColor: getComputedStyle(token).color,
        ruleContent: rule.content,
        ruleColor: rule.backgroundColor,
        width: rect.width,
        blockWidth: blockRect.width,
      };
    });
    expect(
      initialSource.slice(
        dividerPresentation.sourceStart,
        dividerPresentation.sourceEnd,
      ),
    ).toBe('///|');
    expect(dividerPresentation.tokenColor).toBe('rgba(0, 0, 0, 0)');
    expect(dividerPresentation.ruleContent).toBe('\"\"');
    expect(dividerPresentation.ruleColor).not.toBe('rgba(0, 0, 0, 0)');
    expect(dividerPresentation.width).toBeGreaterThan(
      dividerPresentation.blockWidth * 0.9,
    );
    const nestedSemanticLine = page
      .locator(`${article} [data-markdown-code-line]`)
      .filter({ hasText: 'let planet' });
    await expect(nestedSemanticLine).toHaveCount(1);
    const nestedProjection = await nestedSemanticLine.evaluate((node) => ({
      displayedText: node.textContent,
      sourceStart: Number(node.getAttribute('data-markdown-source-start')),
      sourceEnd: Number(node.getAttribute('data-markdown-source-end')),
    }));
    const nestedSourceText = initialSource.slice(
      nestedProjection.sourceStart,
      nestedProjection.sourceEnd,
    );
    expect(nestedSourceText).toMatch(
      /^let planet = "🪐"; let nested_answer/,
    );
    expect(nestedProjection.displayedText.endsWith(nestedSourceText)).toBe(
      true,
    );
    const nestedSyntheticPadding = nestedProjection.displayedText.slice(
      0,
      nestedProjection.displayedText.length - nestedSourceText.length,
    );
    expect(nestedSyntheticPadding).toMatch(/^ +$/);
    expect(nestedSyntheticPadding.length).toBeGreaterThan(0);
    await expect(page.locator(`${article} .mtk3`)).not.toHaveCount(0);
    await expect(page.locator(`${article} input[type="checkbox"]`)).toBeDisabled();
    await expect
      .poll(() =>
        page.locator(root).evaluate((node) => node.getBoundingClientRect().width),
      )
      .toBe(720);
    await page.evaluate(() =>
      globalThis.__markdownDocumentControls.resizeHost(640),
    );
    await expect
      .poll(() =>
        page.locator(root).evaluate((node) => node.getBoundingClientRect().width),
      )
      .toBe(640);

    const initialDiagnostic =
      `${article} .moonbit-viewer-markdown-diagnostic.squiggly-warning`;
    await expect(page.locator(initialDiagnostic)).not.toHaveCount(0);
    await expect(page.locator(initialDiagnostic).first()).toHaveAttribute(
      'data-marker-message',
      'initial markdown diagnostic',
    );
    await expect(page.locator(initialDiagnostic).first()).toHaveAttribute(
      'data-marker-z-index',
      '20',
    );
    expect(
      await page.locator(initialDiagnostic).first().evaluate((node) =>
        getComputedStyle(node).zIndex,
      ),
    ).toBe('20');
    expect(
      await page.locator(initialDiagnostic).first().evaluate((node) =>
        getComputedStyle(node).backgroundImage,
      ),
    ).not.toBe('none');

    // A real Range-derived pointer sweeps across source boundaries faster than
    // the hover delay. Only its final stable boundary reaches the provider;
    // while that call remains unresolved, the standard loading row makes the
    // pending state visible.
    let callCount = (await hoverCalls(page)).length;
    const sweepPoints = await sourceTextPoints(
      page,
      article,
      'markdown_answer',
      [1, 2, 4],
    );
    const viewportSize = page.viewportSize();
    await page.mouse.move(
      Math.max((viewportSize?.width ?? 800) - 1, 0),
      Math.max((viewportSize?.height ?? 600) - 1, 0),
    );
    for (const point of sweepPoints) {
      await page.mouse.move(point.x, point.y);
      await page.waitForTimeout(25);
    }
    await page.waitForTimeout(50);
    expect((await hoverCalls(page)).length).toBe(callCount);
    const initialPoint = sweepPoints.at(-1);
    const initialCall = await waitForNewHoverCall(page, callCount);
    const expectedInitialOffset =
      initialSource.indexOf('markdown_answer') + 4;
    const expectedInitialPosition = sourcePositionAtOffset(
      initialSource,
      expectedInitialOffset,
    );
    expect(initialCall).toMatchObject({
      uri: 'inmemory://component/literate.mbt.md',
      revision: 'markdown-document-rev-1',
      hostVersion: 1,
      internalVersion: 1,
      ...expectedInitialPosition,
      offset: expectedInitialOffset,
      cancelled: false,
    });
    expect(initialCall.modelIdentity).toBeGreaterThan(0);
    await expect(page.locator(hoverWidget)).toContainText('Loading...', {
      timeout: 2_000,
    });
    expect(await hoverCalls(page)).toHaveLength(callCount + 1);
    await page.evaluate(
      ({ id }) =>
        globalThis.__markdownDocumentControls.releaseHover(
          id,
          'wide:initial language hover with enough descriptive words to exercise readable natural width measurement',
        ),
      initialCall,
    );
    await expect(page.locator(hoverWidget)).toHaveAttribute(
      'data-markdown-hover-visible',
      'true',
    );
    await expect(page.locator(hoverWidget)).toContainText(
      'wide:initial language hover',
    );
    await expect(page.locator(hoverWidget)).not.toContainText('Loading...');
    await expect(page.locator(hoverWidget)).toContainText(
      'initial markdown diagnostic',
    );
    await expect(page.locator(hoverWidget)).toHaveAttribute(
      'data-markdown-hover-model-identity',
      String(initialCall.modelIdentity),
    );
    await expect(page.locator(hoverWidget)).toHaveAttribute(
      'data-markdown-hover-uri',
      initialCall.uri,
    );
    await expect(page.locator(hoverWidget)).toHaveAttribute(
      'data-markdown-hover-revision',
      initialCall.revision,
    );
    await expect(page.locator(hoverWidget)).toHaveAttribute(
      'data-markdown-hover-source-line',
      String(initialCall.lineNumber),
    );
    await expect(page.locator(hoverWidget)).toHaveAttribute(
      'data-markdown-hover-source-column',
      String(initialCall.column),
    );
    await expect(page.locator(hoverWidget)).toHaveAttribute(
      'data-markdown-hover-wire-offset',
      String(initialCall.offset),
    );
    await expect(page.locator(hoverWidget)).toHaveAttribute(
      'data-markdown-hover-returned-range',
      fullModelRangeString(initialSource),
    );
    const projectedHoverRanges =
      `${article} .moonbit-viewer-markdown-hover-range`;
    await expect(page.locator(projectedHoverRanges)).toHaveCount(4);
    expect(
      await page.locator(projectedHoverRanges).evaluateAll((nodes) =>
        nodes.every(
          (node) =>
            node.closest('[data-markdown-code-block]')?.getAttribute(
              'data-markdown-code-block',
            ) === '0',
        ),
      ),
    ).toBe(true);
    const clamped = await page.evaluate(
      ({ widgetSelector, viewportSelector, initialPoint }) => {
        const widgetRect = document
          .querySelector(widgetSelector)
          .getBoundingClientRect();
        const viewportRect = document
          .querySelector(viewportSelector)
          .getBoundingClientRect();
        return {
          pointerX: initialPoint.x,
          widgetWidth: widgetRect.width,
          widgetLeft: widgetRect.left,
          widgetRight: widgetRect.right,
          widgetTop: widgetRect.top,
          widgetBottom: widgetRect.bottom,
          viewportLeft: viewportRect.left,
          viewportRight: viewportRect.right,
          viewportTop: viewportRect.top,
          viewportBottom: viewportRect.bottom,
        };
      },
      { widgetSelector: hoverWidget, viewportSelector: viewport, initialPoint },
    );
    expect(clamped.widgetWidth).toBeGreaterThanOrEqual(300);
    expect(clamped.widgetLeft).toBeGreaterThanOrEqual(clamped.viewportLeft);
    expect(clamped.widgetRight).toBeLessThanOrEqual(clamped.viewportRight + 1);
    expect(clamped.widgetTop).toBeGreaterThanOrEqual(clamped.viewportTop);
    expect(clamped.widgetBottom).toBeLessThanOrEqual(
      clamped.viewportBottom + 1,
    );
    await page.locator(`${hoverWidget} .hover-copy-button`).click();
    await expect
      .poll(() =>
        page.evaluate(() => globalThis.__readonlyEditorCopiedText || ''),
      )
      .toBe('initial markdown diagnostic');

    // The second semantic target is nested through a quote and list. Its
    // rendered line begins with two non-source padding cells, while the real
    // Range-derived target follows an astral character on the same source line.
    // Narrowing the host forces that one logical line across visual rows.
    // VS Code b18492a's DecorationsOverlay paints one hoverHighlight fragment
    // per wrapped view row; the Markdown DOM projection must preserve the same
    // no-bleed behavior.
    await page.evaluate(() =>
      globalThis.__markdownDocumentControls.resizeHost(360),
    );
    await expect
      .poll(() =>
        page.locator(root).evaluate((node) => node.getBoundingClientRect().width),
      )
      .toBe(360);
    callCount = (await hoverCalls(page)).length;
    await moveToSourceText(page, article, 'nested_answer', 6);
    const nestedCall = await waitForNewHoverCall(page, callCount);
    const expectedNestedOffset =
      initialSource.indexOf('nested_answer') + 6;
    const nestedSourceLineStart =
      initialSource.lastIndexOf('\n', expectedNestedOffset) + 1;
    expect(
      initialSource.slice(nestedSourceLineStart, expectedNestedOffset),
    ).toContain('🪐');
    expect(nestedCall).toMatchObject({
      modelIdentity: initialCall.modelIdentity,
      uri: initialCall.uri,
      revision: initialCall.revision,
      ...sourcePositionAtOffset(initialSource, expectedNestedOffset),
      offset: expectedNestedOffset,
      cancelled: false,
    });
    await page.evaluate(
      ({ id }) =>
        globalThis.__markdownDocumentControls.releaseHover(
          id,
          'nested astral language hover',
        ),
      nestedCall,
    );
    await expect(page.locator(hoverWidget)).toContainText(
      'nested astral language hover',
    );
    await expect(page.locator(hoverWidget)).toHaveAttribute(
      'data-markdown-hover-block-index',
      '1',
    );
    await expect(page.locator(hoverWidget)).toHaveAttribute(
      'data-markdown-hover-wire-offset',
      String(expectedNestedOffset),
    );
    const wrappedHoverGeometry = await nestedSemanticLine.evaluate(
      (line, { text, utf16Delta }) => {
        const walker = document.createTreeWalker(
          line,
          NodeFilter.SHOW_TEXT,
        );
        let node;
        while ((node = walker.nextNode())) {
          const index = String(node.textContent || '').indexOf(text);
          if (index < 0) continue;
          const range = document.createRange();
          range.setStart(node, index + utf16Delta);
          range.setEnd(node, index + utf16Delta + 1);
          const lineRect = line.getBoundingClientRect();
          const lineHeight = Number.parseFloat(
            getComputedStyle(line).lineHeight,
          );
          const target = Array.from(
            range.getClientRects(),
            (rect) => ({
              left: rect.left,
              top: rect.top,
              right: rect.right,
              bottom: rect.bottom,
              width: rect.width,
              height: rect.height,
            }),
          );
          const actual = Array.from(
            line.querySelectorAll(
              '.moonbit-viewer-markdown-hover-range',
            ),
            (element) => {
              const rect = element.getBoundingClientRect();
              return {
                left: rect.left,
                top: rect.top,
                right: rect.right,
                bottom: rect.bottom,
                width: rect.width,
                height: rect.height,
              };
            },
          );
          return {
            lineHeight,
            logicalLineHeight: lineRect.height,
            logicalLineTop: lineRect.top,
            logicalLineBottom: lineRect.bottom,
            target,
            actual,
          };
        }
        throw new Error(`text node not found: ${text}`);
      },
      { text: 'nested_answer', utf16Delta: 6 },
    );
    expect(wrappedHoverGeometry.logicalLineHeight).toBeGreaterThan(
      wrappedHoverGeometry.lineHeight + 1,
    );
    expect(wrappedHoverGeometry.target).toHaveLength(1);
    expect(wrappedHoverGeometry.actual).toHaveLength(1);
    const targetRect = wrappedHoverGeometry.target[0];
    const actualRect = wrappedHoverGeometry.actual[0];
    expect(Math.abs(actualRect.left - targetRect.left)).toBeLessThanOrEqual(1);
    expect(Math.abs(actualRect.right - targetRect.right)).toBeLessThanOrEqual(
      1,
    );
    expect(actualRect.height).toBeLessThanOrEqual(
      wrappedHoverGeometry.lineHeight + 1,
    );
    expect(actualRect.height).toBeGreaterThanOrEqual(
      wrappedHoverGeometry.lineHeight - 1,
    );
    expect(actualRect.top).toBeLessThanOrEqual(targetRect.top + 1);
    expect(actualRect.bottom).toBeGreaterThanOrEqual(targetRect.bottom - 1);
    expect(actualRect.top).toBeGreaterThanOrEqual(
      wrappedHoverGeometry.logicalLineTop - 1,
    );
    expect(actualRect.bottom).toBeLessThanOrEqual(
      wrappedHoverGeometry.logicalLineBottom + 1,
    );
    await page.evaluate(() =>
      globalThis.__markdownDocumentControls.resizeHost(640),
    );
    await expect
      .poll(() =>
        page.locator(root).evaluate((node) => node.getBoundingClientRect().width),
      )
      .toBe(640);
    await expect(page.locator(hoverWidget)).toHaveAttribute(
      'data-markdown-hover-visible',
      'false',
    );
    await expect(
      page.locator(`${article} .moonbit-viewer-markdown-hover-range`),
    ).toHaveCount(0);

    // Resolved marker options keep Code's z/class/range paint order.
    // The observable unnecessary underline follows the live root gate;
    // inline source-text tag effects are an explicit first-slice exclusion.
    await page.evaluate(() =>
      globalThis.__markdownDocumentControls.setMarkerPolicyFixture(),
    );
    const policyDiagnostics =
      `${article} .moonbit-viewer-markdown-diagnostic[data-marker-message^="policy "]`;
    await expect(page.locator(policyDiagnostics)).toHaveCount(3);
    expect(
      await page.locator(policyDiagnostics).evaluateAll((nodes) =>
        nodes.map((node) => ({
          message: node.getAttribute('data-marker-message'),
          zIndex: node.getAttribute('data-marker-z-index'),
        })),
      ),
    ).toEqual([
      { message: 'policy unnecessary', zIndex: '0' },
      { message: 'policy warning', zIndex: '20' },
      { message: 'policy error', zIndex: '30' },
    ]);
    const unnecessaryDiagnostic =
      `${policyDiagnostics}.squiggly-unnecessary`;
    await expect(page.locator(root)).toHaveClass(/showUnused/);
    expect(
      await page.locator(unnecessaryDiagnostic).evaluate((node) =>
        getComputedStyle(node).borderBottomStyle,
      ),
    ).toBe('dashed');
    await page.evaluate(() =>
      globalThis.__markdownDocumentControls.setMarkerUnusedVisibility(false),
    );
    await expect(page.locator(root)).not.toHaveClass(/showUnused/);
    expect(
      await page.locator(unnecessaryDiagnostic).evaluate((node) =>
        getComputedStyle(node).borderBottomStyle,
      ),
    ).toBe('none');
    await page.evaluate(() =>
      globalThis.__markdownDocumentControls.setMarkerUnusedVisibility(true),
    );

    // Marker changes retire both pending/visible hover state before
    // reprojecting; the next request merges the updated live marker row.
    await page.evaluate(() =>
      globalThis.__markdownDocumentControls.updateMarker(
        'updated markdown diagnostic',
      ),
    );
    await expect(page.locator(initialDiagnostic).first()).toHaveAttribute(
      'data-marker-message',
      'updated markdown diagnostic',
    );
    await expect(page.locator(hoverWidget)).toHaveAttribute(
      'data-markdown-hover-visible',
      'false',
    );
    callCount = (await hoverCalls(page)).length;
    await moveToSourceText(page, article, 'markdown_answer', 5);
    const updatedMarkerCall = await waitForNewHoverCall(page, callCount);
    await page.evaluate(
      ({ id }) =>
        globalThis.__markdownDocumentControls.releaseHover(
          id,
          'updated language hover',
        ),
      updatedMarkerCall,
    );
    await expect(page.locator(hoverWidget)).toContainText(
      'updated language hover',
    );
    await expect(page.locator(hoverWidget)).toContainText(
      'updated markdown diagnostic',
    );

    // Ordinary fences, synthetic padding, trailing code-row space, and prose
    // are all outside source-bearing semantic text and issue no request.
    callCount = (await hoverCalls(page)).length;
    await moveToSourceText(page, article, 'ordinary_fence_answer', 4);
    await expectNoNewHoverCall(page, callCount);
    await moveToSyntheticPadding(page, article, 'nested_answer');
    await expectNoNewHoverCall(page, callCount);
    await moveToTrailingLineRegion(page, article, 'markdown_answer');
    await expectNoNewHoverCall(page, callCount);
    await moveToSourceText(page, article, 'Readonly Markdown document', 3);
    await expectNoNewHoverCall(page, callCount);
    await expect(page.locator(hoverWidget)).toHaveAttribute(
      'data-markdown-hover-visible',
      'false',
    );
    expect(
      await page.locator(hoverWidget).evaluate((node) =>
        getComputedStyle(node).display,
      ),
    ).toBe('none');

    // Two Viewers sharing the model/services have independent request and DOM
    // owners.
    callCount = (await hoverCalls(page)).length;
    await moveToSourceText(page, secondaryArticle, 'markdown_answer', 3);
    const secondaryCall = await waitForNewHoverCall(page, callCount);
    await page.evaluate(
      ({ id }) =>
        globalThis.__markdownDocumentControls.releaseHover(
          id,
          'secondary viewer language hover',
        ),
      secondaryCall,
    );
    await expect(page.locator(secondaryHover)).toContainText(
      'secondary viewer language hover',
    );
    await expect(page.locator(hoverWidget)).not.toContainText(
      'secondary viewer language hover',
    );

    const originalValue = await page.evaluate(() =>
      globalThis.__markdownDocumentControls.getModelValue(),
    );
    await page.locator(`${article} input[type="checkbox"]`).click({
      force: true,
    });
    expect(
      await page.evaluate(() =>
        globalThis.__markdownDocumentControls.getModelValue(),
      ),
    ).toBe(originalValue);

    // Moving away invalidates an in-flight provider completion.
    callCount = (await hoverCalls(page)).length;
    await moveToSourceText(page, article, 'markdown_answer', 3);
    const staleMoveCall = await waitForNewHoverCall(page, callCount);
    await moveToSourceText(page, article, 'Readonly Markdown document', 1);
    await expectHoverCallCancelled(page, staleMoveCall.id);
    await page.evaluate(
      ({ id }) =>
        globalThis.__markdownDocumentControls.releaseHover(
          id,
          'stale pointer completion',
        ),
      staleMoveCall,
    );
    await page.waitForTimeout(50);
    await expect(page.locator(hoverWidget)).not.toContainText(
      'stale pointer completion',
    );

    // A source replacement retires the old projection/request before the
    // retained article target is rewritten.
    callCount = (await hoverCalls(page)).length;
    await moveToSourceText(page, article, 'markdown_answer', 6);
    const staleContentCall = await waitForNewHoverCall(page, callCount);
    await page.evaluate(() => {
      const root = document.querySelector(
        '.markdown-document-host > .moonbit-viewer-markdown-document',
      );
      globalThis.__markdownDocumentRetainedDom = {
        root,
        article: root.querySelector(
          '.moonbit-viewer-markdown-document-article',
        ),
        overlays: root.querySelector(
          '.moonbit-viewer-markdown-document-overlays',
        ),
        generation: Number(
          root.getAttribute('data-markdown-projection-generation'),
        ),
      };
      globalThis.__markdownDocumentControls.replaceSource();
    });
    await expectHoverCallCancelled(page, staleContentCall.id);
    await page.evaluate(
      ({ id }) =>
        globalThis.__markdownDocumentControls.releaseHover(
          id,
          'stale content completion',
        ),
      staleContentCall,
    );
    await expect(page.locator(article)).toContainText('replacement_answer');
    await expect(page.locator(hoverWidget)).not.toContainText(
      'stale content completion',
    );
    expect(
      await page.evaluate(() =>
        globalThis.__markdownDocumentControls.getModelValue(),
      ),
    ).toContain('replacement_answer');
    const replacementState = await page.evaluate(() => {
      const retained = globalThis.__markdownDocumentRetainedDom;
      const currentRoot = document.querySelector(
        '.markdown-document-host > .moonbit-viewer-markdown-document',
      );
      return {
        sameRoot: retained.root === currentRoot,
        sameArticle:
          retained.article ===
          currentRoot.querySelector(
            '.moonbit-viewer-markdown-document-article',
          ),
        sameOverlays:
          retained.overlays ===
          currentRoot.querySelector(
            '.moonbit-viewer-markdown-document-overlays',
          ),
        generation: Number(
          currentRoot.getAttribute('data-markdown-projection-generation'),
        ),
        previousGeneration: retained.generation,
      };
    });
    expect(replacementState).toMatchObject({
      sameRoot: true,
      sameArticle: true,
      sameOverlays: true,
    });
    expect(replacementState.generation).toBeGreaterThan(
      replacementState.previousGeneration,
    );
    const replacementDiagnostic =
      `${article} .moonbit-viewer-markdown-diagnostic.squiggly-warning`;
    await expect(page.locator(replacementDiagnostic).first()).toHaveAttribute(
      'data-marker-message',
      'replacement markdown diagnostic',
    );

    callCount = (await hoverCalls(page)).length;
    await moveToSourceText(page, article, 'replacement_answer', 4);
    const replacementCall = await waitForNewHoverCall(page, callCount);
    await page.evaluate(
      ({ id }) =>
        globalThis.__markdownDocumentControls.releaseHover(
          id,
          'replacement language hover',
        ),
      replacementCall,
    );
    await expect(page.locator(hoverWidget)).toContainText(
      'replacement language hover',
    );
    await expect(page.locator(hoverWidget)).toContainText(
      'replacement markdown diagnostic',
    );

    // Theme refresh is also a projection replacement and rejects the pending
    // generation before rebuilding token/marker DOM.
    callCount = (await hoverCalls(page)).length;
    await moveToSourceText(page, article, 'replacement_answer', 5);
    const staleThemeCall = await waitForNewHoverCall(page, callCount);
    await page.evaluate(() =>
      globalThis.__markdownDocumentControls.updateTheme(
        'markdown-component-theme',
      ),
    );
    await expectHoverCallCancelled(page, staleThemeCall.id);
    await page.evaluate(
      ({ id }) =>
        globalThis.__markdownDocumentControls.releaseHover(
          id,
          'stale theme completion',
        ),
      staleThemeCall,
    );
    await expect(page.locator(root)).toHaveAttribute(
      'data-theme',
      'markdown-component-theme',
    );
    const themedGeneration = Number(
      await page.locator(root).getAttribute(
        'data-markdown-projection-generation',
      ),
    );
    expect(themedGeneration).toBeGreaterThan(replacementState.generation);
    await expect(page.locator(hoverWidget)).not.toContainText(
      'stale theme completion',
    );
    expect(
      await page.evaluate(() => {
        const retained = globalThis.__markdownDocumentRetainedDom;
        const currentRoot = document.querySelector(
          '.markdown-document-host > .moonbit-viewer-markdown-document',
        );
        return (
          retained.root === currentRoot &&
          retained.article ===
            currentRoot.querySelector(
              '.moonbit-viewer-markdown-document-article',
            ) &&
          retained.overlays ===
            currentRoot.querySelector(
              '.moonbit-viewer-markdown-document-overlays',
            )
        );
      }),
    ).toBe(true);

    await page.evaluate(() =>
      globalThis.__markdownDocumentControls.setScrollTop(60),
    );
    await expect
      .poll(() => page.locator(viewport).evaluate((node) => node.scrollTop))
      .toBeGreaterThan(0);

    await page.evaluate(() => globalThis.__markdownDocumentControls.showCode());
    await expect(page.locator(root)).toHaveCount(0);
    await expect(page.locator(`${host} > .monaco-editor`)).toHaveCount(1);
    await expect(page.locator(`${host} > .monaco-editor`)).toContainText(
      'ordinary_code',
    );

    await page.evaluate(() =>
      globalThis.__markdownDocumentControls.showMarkdown(),
    );
    await expect(page.locator(root)).toHaveCount(1);
    await expect(page.locator(`${host} > .monaco-editor`)).toHaveCount(0);
    await expect(page.locator(article)).toContainText('replacement_answer');

    // A different model with the same URI/revision/caller version still has a
    // distinct identity and attachment generation.
    callCount = (await hoverCalls(page)).length;
    await moveToSourceText(page, article, 'replacement_answer', 6);
    const staleSameUriCall = await waitForNewHoverCall(page, callCount);
    await page.evaluate(() =>
      globalThis.__markdownDocumentControls.showSameUriMarkdown(),
    );
    await expect(page.locator(article)).toContainText('same_uri_answer');
    await expectHoverCallCancelled(page, staleSameUriCall.id);
    await page.evaluate(
      ({ id }) =>
        globalThis.__markdownDocumentControls.releaseHover(
          id,
          'stale same URI completion',
        ),
      staleSameUriCall,
    );
    await expect(page.locator(hoverWidget)).not.toContainText(
      'stale same URI completion',
    );
    callCount = (await hoverCalls(page)).length;
    await moveToSourceText(page, article, 'same_uri_answer', 4);
    const sameUriCall = await waitForNewHoverCall(page, callCount);
    expect(sameUriCall.modelIdentity).not.toBe(staleSameUriCall.modelIdentity);
    expect(sameUriCall.uri).toBe(staleSameUriCall.uri);
    expect(sameUriCall.revision).toBe(staleSameUriCall.revision);
    await page.evaluate(
      ({ id }) =>
        globalThis.__markdownDocumentControls.releaseHover(
          id,
          'same URI accepted hover',
        ),
      sameUriCall,
    );
    await expect(page.locator(hoverWidget)).toContainText(
      'same URI accepted hover',
    );
    await expect(page.locator(hoverWidget)).toContainText(
      'same URI markdown diagnostic',
    );

    // Disposal cancels the final in-flight request and removes both the
    // presentation and its persistent overlay widget before completion.
    callCount = (await hoverCalls(page)).length;
    await moveToSourceText(page, article, 'Same URI replacement model', 1);
    await expectNoNewHoverCall(page, callCount);
    await expect(page.locator(hoverWidget)).toHaveAttribute(
      'data-markdown-hover-visible',
      'false',
    );
    await moveToSourceText(page, article, 'Int', 1);
    const staleDisposeCall = await waitForNewHoverCall(page, callCount);
    await page.evaluate(() => globalThis.__markdownDocumentControls.dispose());
    await expect(page.locator(root)).toHaveCount(0);
    await expect(page.locator(`${host} > .monaco-editor`)).toHaveCount(0);
    await expectHoverCallCancelled(page, staleDisposeCall.id);
    await page.evaluate(
      ({ id }) =>
        globalThis.__markdownDocumentControls.releaseHover(
          id,
          'stale dispose completion',
        ),
      staleDisposeCall,
    );
    await page.waitForTimeout(50);
    await expect(page.locator(root)).toHaveCount(0);
    await expect(page.locator(hoverWidget)).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});
