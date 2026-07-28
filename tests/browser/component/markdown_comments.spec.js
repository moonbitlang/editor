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
const diagramViewport =
  `${diagram}.moonbit-viewer-markdown-diagram-viewport`;
const diagramContent = '.moonbit-viewer-markdown-diagram-content';
const diagramControls = '.moonbit-viewer-markdown-diagram-controls';
const diagramResizeHandle =
  '.moonbit-viewer-markdown-diagram-resize-handle';
const editorScrollable =
  `${editor} .monaco-scrollable-element.editor-scrollable`;
const imageUrl = 'https://images.example.test/markdown-comment.svg';
const mermaidCdnUrl =
  'https://cdn.jsdelivr.net/npm/mermaid@11.16.0/dist/mermaid.esm.min.mjs';
const runLiveMermaidCdn =
  process.env.READONLY_EDITOR_TEST_LIVE_MERMAID_CDN === '1';

const fakeMermaidModule = `
  const state = globalThis.__markdownCommentsMermaid;
  state.moduleLoads += 1;
  let currentTheme = '';

  const escapeXml = (value) =>
    value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  export function initialize(options) {
    currentTheme = options.theme;
    state.initialize.push({
      startOnLoad: options.startOnLoad,
      securityLevel: options.securityLevel,
      suppressErrorRendering: options.suppressErrorRendering,
      theme: options.theme,
      secure: Array.isArray(options.secure) ? [...options.secure] : [],
    });
  }

  export async function render(id, source) {
    const call = {
      id,
      source,
      theme: currentTheme,
      order: state.render.length,
    };
    state.render.push(call);
    if (source.includes('INVALID')) {
      state.reject.push({ id, source, theme: currentTheme });
      throw new Error('deterministic invalid Mermaid fixture');
    }
    if (source.includes('DELAYED_OLD')) {
      await new Promise((resolve) => {
        state.pending.push({ id, source, theme: currentTheme, resolve });
      });
    }
    const theme = call.theme;
    const responsive = source.includes('RESPONSIVE_OFFSCREEN');
    const tall = source.includes('VALID_SECOND');
    const width = responsive ? 720 : 360;
    const height = responsive
      ? 240
      : tall
        ? 960
        : theme === 'default'
          ? 132
          : 76;
    const label = responsive
      ? 'RESPONSIVE_OFFSCREEN'
      : source.includes('DELAYED_OLD')
        ? 'DELAYED_OLD'
        : source.includes('CURRENT_NEW')
          ? 'CURRENT_NEW'
          : source.includes('VALID_SECOND')
            ? 'VALID_SECOND'
            : 'VALID_ONE';
    return {
      svg:
        '<svg xmlns="http://www.w3.org/2000/svg" width="' +
        width +
        '" height="' +
        height +
        '" viewBox="0 0 ' +
        width +
        ' ' +
        height +
        '" data-mermaid-id="' +
        escapeXml(id) +
        '" data-mermaid-theme="' +
        escapeXml(theme) +
        '" data-mermaid-source="' +
        label +
        '">' +
        '<rect width="' +
        width +
        '" height="' +
        height +
        '" fill="' +
        (theme === 'default' ? '#f4f7fb' : '#1f2937') +
        '"/>' +
        '<text x="16" y="36" fill="' +
        (theme === 'default' ? '#172033' : '#f8fafc') +
        '">' +
        label +
        '</text></svg>',
      bindFunctions(root) {
        root.setAttribute('data-fake-mermaid-bound', id);
        state.bind.push({
          id,
          source,
          theme,
          rootClass: root.className,
          connected: root.isConnected,
        });
      },
    };
  }

  export default { initialize, render };
`;

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

async function mountMarkdownComments(
  page,
  testInfo,
  { liveMermaidCdn = false } = {},
) {
  await page.route(imageUrl, (route) =>
    route.fulfill({
      status: 200,
      contentType: 'image/svg+xml',
      body: fixtureSvg,
    }),
  );
  if (!liveMermaidCdn) {
    await page.route(mermaidCdnUrl, (route) =>
      route.fulfill({
        status: 200,
        contentType: 'text/javascript',
        headers: {
          'access-control-allow-origin': '*',
          'cache-control': 'no-store',
        },
        body: fakeMermaidModule,
      }),
    );
  }
  await page.addInitScript(() => {
    globalThis.__markdownCommentOpened = [];
    globalThis.__markdownCommentsMermaid = {
      moduleLoads: 0,
      initialize: [],
      render: [],
      bind: [],
      reject: [],
      pending: [],
      released: [],
      release(needle = '') {
        const index = this.pending.findIndex((entry) =>
          entry.source.includes(needle),
        );
        if (index < 0) return false;
        const [entry] = this.pending.splice(index, 1);
        this.released.push({
          id: entry.id,
          source: entry.source,
          theme: entry.theme,
        });
        entry.resolve();
        return true;
      },
    };
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
  expect(report.metrics.initialDiagrams).toBe(2);
  await expect(page.locator(zone)).toHaveCount(3);
  await settle(page);
  return reporter;
}

async function mermaidLog(page) {
  return page.evaluate(() => {
    const state = globalThis.__markdownCommentsMermaid;
    return {
      moduleLoads: state.moduleLoads,
      initialize: state.initialize.map((entry) => ({ ...entry })),
      render: state.render.map((entry) => ({ ...entry })),
      bind: state.bind.map((entry) => ({ ...entry })),
      reject: state.reject.map((entry) => ({ ...entry })),
      pending: state.pending.map(({ id, source, theme }) => ({
        id,
        source,
        theme,
      })),
      released: state.released.map((entry) => ({ ...entry })),
    };
  });
}

async function releaseMermaid(page, needle = '') {
  return page.evaluate(
    (value) => globalThis.__markdownCommentsMermaid.release(value),
    needle,
  );
}

async function observeMermaidCommits(page) {
  await page.evaluate(() => {
    globalThis.__markdownCommentsMermaidCommits = [];
    globalThis.__markdownCommentsMermaidCommitObserver?.disconnect();
    const recordSvg = (node) => {
      if (!(node instanceof Element)) return;
      const svgs = node.matches('[data-mermaid-source]')
        ? [node]
        : Array.from(node.querySelectorAll('[data-mermaid-source]'));
      for (const svg of svgs) {
        globalThis.__markdownCommentsMermaidCommits.push({
          id: svg.getAttribute('data-mermaid-id'),
          source: svg.getAttribute('data-mermaid-source'),
          theme: svg.getAttribute('data-mermaid-theme'),
        });
      }
    };
    globalThis.__markdownCommentsMermaidCommitObserver = new MutationObserver(
      (records) => {
        for (const record of records) {
          for (const node of record.addedNodes) recordSvg(node);
        }
      },
    );
    globalThis.__markdownCommentsMermaidCommitObserver.observe(
      document.querySelector('.markdown-comments-host'),
      { childList: true, subtree: true },
    );
  });
}

async function mermaidCommits(page) {
  return page.evaluate(() =>
    (globalThis.__markdownCommentsMermaidCommits ?? []).map((entry) => ({
      ...entry,
    })),
  );
}

async function stopObservingMermaidCommits(page) {
  await page.evaluate(() =>
    globalThis.__markdownCommentsMermaidCommitObserver?.disconnect(),
  );
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

async function horizontalViewportGeometry(page) {
  return page.locator(editor).evaluate((root) => {
    const rect = (node) => {
      const value = node.getBoundingClientRect();
      return {
        top: value.top,
        bottom: value.bottom,
        left: value.left,
        right: value.right,
        width: value.width,
        height: value.height,
      };
    };
    const required = (selector, scope = root) => {
      const node = scope.querySelector(selector);
      if (!node) throw new Error(`missing horizontal geometry node: ${selector}`);
      return node;
    };
    const scrollable = required(
      '.monaco-scrollable-element.editor-scrollable',
    );
    const rail = required(':scope > .scrollbar.vertical', scrollable);
    const viewZones = required('.view-zones');
    const outers = Array.from(
      root.querySelectorAll('.moonbit-viewer-markdown-comment'),
    );
    if (outers.length === 0) {
      throw new Error('missing Markdown comment outer nodes');
    }
    const sourceLine = Array.from(
      root.querySelectorAll('.view-lines .view-line'),
    ).find((node) =>
      node.textContent.includes('horizontal_overflow_sentinel'));
    if (!sourceLine) throw new Error('missing horizontal overflow source line');
    const sourceContent =
      sourceLine.querySelector('.view-line-content') ?? sourceLine;
    const viewport = required(
      '.moonbit-viewer-markdown-diagram-viewport',
    );
    const toolbar = required(
      ':scope > .moonbit-viewer-markdown-diagram-controls',
      viewport,
    );
    const transformContent = required(
      ':scope > .moonbit-viewer-markdown-diagram-content',
      viewport,
    );
    return {
      scrollable: rect(scrollable),
      rail: rect(rail),
      viewZones: rect(viewZones),
      outers: outers.map(rect),
      source: rect(sourceContent),
      diagram: rect(viewport),
      toolbar: rect(toolbar),
      diagramTransform: transformContent.style.transform,
    };
  });
}

function expectMarkdownPinnedToVisibleViewport(geometry) {
  expect(geometry.rail.width).toBeGreaterThan(0);
  for (const outer of geometry.outers) {
    expectNear(outer.left, geometry.scrollable.left);
    expectNear(outer.right, geometry.rail.left);
    expectNear(
      outer.width,
      geometry.rail.left - geometry.scrollable.left,
    );
  }
}

async function zoneRanges(page) {
  return page.locator(zone).evaluateAll((nodes) =>
    nodes.map((node) => [
      Number(node.getAttribute('data-start-line')),
      Number(node.getAttribute('data-end-line')),
    ]),
  );
}

async function viewportGeometry(locator) {
  return locator.evaluate((wrapper) => {
    const transformContent = wrapper.querySelector(
      ':scope > .moonbit-viewer-markdown-diagram-content',
    );
    const svg = transformContent.querySelector(':scope > svg');
    const wrapperRect = wrapper.getBoundingClientRect();
    const svgRect = svg.getBoundingClientRect();
    const transform = new DOMMatrixReadOnly(
      window.getComputedStyle(transformContent).transform,
    );
    return {
      heightLimit: Math.min(window.innerHeight * 0.5, 480),
      wrapperHeight: wrapperRect.height,
      wrapperWidth: wrapperRect.width,
      inlineHeight: Number.parseFloat(wrapper.style.height),
      svgHeight: svgRect.height,
      svgWidth: svgRect.width,
      scale: transform.a,
      scaleY: transform.d,
      translateX: transform.e,
      translateY: transform.f,
      transform: transformContent.style.transform,
      fullyVisible:
        svgRect.left >= wrapperRect.left - 1 &&
        svgRect.right <= wrapperRect.right + 1 &&
        svgRect.top >= wrapperRect.top - 1 &&
        svgRect.bottom <= wrapperRect.bottom + 1,
    };
  });
}

function expectNear(actual, expected, tolerance = 1) {
  expect(Math.abs(actual - expected)).toBeLessThanOrEqual(tolerance);
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
      [10, 29],
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
    const diagoDiagrams = zones
      .nth(2)
      .locator(`${diagram}[data-diagram-language="diago"]`);
    await expect(diagoDiagrams).toHaveCount(2);
    const diagoDiagram = diagoDiagrams.nth(0);
    const compactDiagram = diagoDiagrams.nth(1);
    for (const renderedDiagram of [diagoDiagram, compactDiagram]) {
      await expect(renderedDiagram).toHaveClass(
        /moonbit-viewer-markdown-diagram-viewport/,
      );
      await expect(
        renderedDiagram.locator(`:scope > ${diagramContent} > svg`),
      ).toHaveCount(1);
      await expect(renderedDiagram.locator(':scope > svg')).toHaveCount(0);
      await expect(
        renderedDiagram.locator(`:scope > ${diagramControls} > button`),
      ).toHaveCount(4);
      await expect(
        renderedDiagram.locator(`:scope > ${diagramResizeHandle}`),
      ).toHaveCount(1);
      await expect(renderedDiagram).toHaveAttribute(
        'aria-label',
        'Interactive Diago diagram',
      );
      await expect(renderedDiagram).toHaveAttribute('tabindex', '0');
    }
    await expect(
      diagoDiagram.locator('[aria-label="Toggle pan mode"]'),
    ).toHaveAttribute('aria-pressed', 'false');
    await expect(
      diagoDiagram.locator('[aria-label="Zoom out"]'),
    ).toHaveCount(1);
    await expect(
      diagoDiagram.locator('[aria-label="Zoom in"]'),
    ).toHaveCount(1);
    await expect(
      diagoDiagram.locator('[aria-label="Fit diagram"]'),
    ).toHaveCount(1);
    const resizeHandle = diagoDiagram.locator(
      '[aria-label="Resize diagram"]',
    );
    await expect(resizeHandle).toHaveAttribute('role', 'separator');
    await expect(resizeHandle).toHaveAttribute('tabindex', '0');
    await expect(resizeHandle).toHaveAttribute(
      'aria-orientation',
      'horizontal',
    );
    const diagramLayout = await diagoDiagram.evaluate((wrapper) => {
      const transformContent = wrapper.querySelector(
        ':scope > .moonbit-viewer-markdown-diagram-content',
      );
      const svg = transformContent.querySelector(':scope > svg');
      const inner = wrapper.closest(
        '.moonbit-viewer-markdown-comment-content',
      );
      const outer = wrapper.closest('.moonbit-viewer-markdown-comment');
      const wrapperRect = wrapper.getBoundingClientRect();
      const svgRect = svg.getBoundingClientRect();
      const innerRect = inner.getBoundingClientRect();
      const outerRect = outer.getBoundingClientRect();
      const viewBox = svg.viewBox.baseVal;
      const transform = new DOMMatrixReadOnly(
        window.getComputedStyle(transformContent).transform,
      );
      return {
        viewportHeight: window.innerHeight,
        wrapperHeight: wrapperRect.height,
        wrapperWidth: wrapperRect.width,
        wrapperClientHeight: wrapper.clientHeight,
        wrapperClientWidth: wrapper.clientWidth,
        wrapperScrollHeight: wrapper.scrollHeight,
        svgHeight: svgRect.height,
        svgWidth: svgRect.width,
        svgAspectRatio: svgRect.width / svgRect.height,
        viewBoxAspectRatio: viewBox.width / viewBox.height,
        innerClientWidth: inner.clientWidth,
        innerHeight: inner.offsetHeight,
        outerHeight: outerRect.height,
        outerStyleHeight: Number.parseFloat(outer.style.height),
        wrapperWithinContent:
          wrapperRect.left >= innerRect.left - 1 &&
          wrapperRect.right <= innerRect.right + 1,
        svgWithinWrapper:
          svgRect.left >= wrapperRect.left - 1 &&
          svgRect.right <= wrapperRect.right + 1 &&
          svgRect.top >= wrapperRect.top - 1 &&
          svgRect.bottom <= wrapperRect.bottom + 1,
        diagramWithinMeasuredHeight: wrapperRect.bottom <= innerRect.bottom + 1,
        overflowX: window.getComputedStyle(wrapper).overflowX,
        overflowY: window.getComputedStyle(wrapper).overflowY,
        position: window.getComputedStyle(wrapper).position,
        boxSizing: window.getComputedStyle(wrapper).boxSizing,
        wrapperMaxWidth: window.getComputedStyle(wrapper).maxWidth,
        svgDisplay: window.getComputedStyle(svg).display,
        svgMaxWidth: window.getComputedStyle(svg).maxWidth,
        transformOrigin:
          window.getComputedStyle(transformContent).transformOrigin,
        scale: transform.a,
        translateY: transform.f,
        preserveAspectRatio: svg.getAttribute('preserveAspectRatio'),
        hasWidth: svg.hasAttribute('width'),
        hasHeight: svg.hasAttribute('height'),
      };
    });
    expect(diagramLayout).toMatchObject({
      wrapperWithinContent: true,
      svgWithinWrapper: true,
      diagramWithinMeasuredHeight: true,
      overflowX: 'hidden',
      overflowY: 'hidden',
      position: 'relative',
      boxSizing: 'border-box',
      wrapperMaxWidth: '100%',
      svgDisplay: 'block',
      svgMaxWidth: '100%',
      transformOrigin: '0px 0px',
      preserveAspectRatio: 'xMinYMin meet',
      hasWidth: false,
      hasHeight: false,
    });
    expectNear(
      diagramLayout.wrapperHeight,
      Math.min(diagramLayout.viewportHeight * 0.5, 480),
    );
    expect(diagramLayout.svgHeight).toBeGreaterThan(0);
    expect(diagramLayout.scale).toBeLessThan(1);
    expectNear(diagramLayout.translateY, 16);
    expectNear(
      diagramLayout.wrapperHeight,
      diagramLayout.wrapperClientHeight,
    );
    expect(diagramLayout.svgHeight).toBeLessThanOrEqual(
      diagramLayout.wrapperClientHeight - 32 + 1,
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
        eof: rect(byRange(10, 29)),
        alpha: rect(lineWith('alpha_code_truth')),
        omega: rect(lineWith('omega_code_truth')),
        startHeading: rect(byRange(1, 3).querySelector('h1')),
        eofCode: rect(
          byRange(10, 29).querySelector('.monaco-tokenized-source'),
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
    expect(geometry.visibleLineCount).toBeGreaterThanOrEqual(3);
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

    // An interactive viewport has no native diagram scroller. Ordinary wheel
    // input bubbles to the public Viewer scroll surface without changing its
    // transform.
    await diagoDiagram.scrollIntoViewIfNeeded();
    await settle(page);
    const diagramBox = await diagoDiagram.boundingBox();
    expect(diagramBox).not.toBeNull();
    await page.mouse.move(
      diagramBox.x + diagramBox.width / 2,
      Math.max(20, Math.min(660, diagramBox.y + 100)),
    );
    const diagramBeforeWheel = await viewportGeometry(diagoDiagram);
    const editorScrollBefore = (await state(page)).scrollTop;
    await page.mouse.wheel(0, 160);
    await expect
      .poll(async () => (await state(page)).scrollTop)
      .toBeGreaterThan(editorScrollBefore);
    const diagramAfterWheel = await viewportGeometry(diagoDiagram);
    expect(diagramAfterWheel.transform).toBe(diagramBeforeWheel.transform);
    expect(await diagoDiagram.evaluate((wrapper) => wrapper.scrollTop)).toBe(0);
    await control(page, 'set_scroll_top', 0);
    await settle(page);

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

test('pins Markdown to the visible viewport while long source keeps its horizontal scroll plane', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    const zeroState = await state(page);
    expect(zeroState.softWrap).toBe(false);
    expect(zeroState.scrollLeft).toBe(0);

    const zero = await horizontalViewportGeometry(page);
    expectMarkdownPinnedToVisibleViewport(zero);
    expect(zeroState.scrollWidth).toBeGreaterThan(zero.scrollable.width + 100);
    expect(zeroState.contentWidth).toBeGreaterThan(
      zero.scrollable.width + 100,
    );
    expect(zero.viewZones.width).toBeGreaterThan(
      zero.scrollable.width + 100,
    );

    const maximumRequest = Math.floor(zeroState.scrollWidth);
    const middleRequest = Math.max(
      1,
      Math.floor((zeroState.scrollWidth - zero.scrollable.width) / 2),
    );
    const samples = [{ state: zeroState, geometry: zero }];
    for (const requested of [middleRequest, maximumRequest]) {
      await control(page, 'set_scroll_left', requested);
      await expect
        .poll(async () => (await state(page)).scrollLeft)
        .toBeGreaterThan(samples.at(-1).state.scrollLeft);
      await settle(page);
      samples.push({
        state: await state(page),
        geometry: await horizontalViewportGeometry(page),
      });
    }

    for (const sample of samples) {
      expectMarkdownPinnedToVisibleViewport(sample.geometry);
      expect(sample.geometry.viewZones.width).toBeGreaterThan(
        sample.geometry.scrollable.width + 100,
      );
      expectNear(
        sample.geometry.source.left,
        zero.source.left - sample.state.scrollLeft,
      );
      expectNear(sample.geometry.diagram.left, zero.diagram.left);
      expectNear(sample.geometry.diagram.right, zero.diagram.right);
      expectNear(sample.geometry.toolbar.right, zero.toolbar.right);
      expect(sample.geometry.diagramTransform).toBe(zero.diagramTransform);
      sample.geometry.outers.forEach((outer, index) => {
        expectNear(outer.height, zero.outers[index].height);
      });
    }

    // Widen from the maximum horizontal position so the new maximum is
    // smaller but remains non-zero. This exercises real scrollLeft clamping,
    // not merely a resize that increases the available scroll range.
    const maximumSample = samples.at(-1);
    await control(page, 'resize', 900);
    await expect
      .poll(async () => (await state(page)).scrollLeft)
      .toBeGreaterThan(0);
    await expect
      .poll(async () => (await state(page)).scrollLeft)
      .toBeLessThan(maximumSample.state.scrollLeft);
    await settle(page);
    const resizedState = await state(page);
    const resized = await horizontalViewportGeometry(page);
    expect(resizedState.scrollLeft).toBeLessThanOrEqual(
      Math.max(0, resizedState.scrollWidth - resized.scrollable.width) + 1,
    );
    expectMarkdownPinnedToVisibleViewport(resized);
    expectNear(
      resized.source.left - resized.scrollable.left + resizedState.scrollLeft,
      zero.source.left - zero.scrollable.left,
    );
    expectNear(
      resized.diagram.right - resized.toolbar.right,
      zero.diagram.right - zero.toolbar.right,
    );
    expect(resized.diagram.right).toBeLessThanOrEqual(resized.rail.left + 1);
    expect(
      resized.outers.some(
        (outer, index) =>
          Math.abs(outer.height - maximumSample.geometry.outers[index].height)
          > 1,
      ),
    ).toBe(true);

    // Soft wrap removes the horizontal range and clamps scrollLeft. Toggling
    // it back restores overflow without changing the Markdown viewport
    // contract, after which horizontal scrolling can resume.
    await control(page, 'set_soft_wrap', true);
    await expect.poll(async () => (await state(page)).softWrap).toBe(true);
    await expect
      .poll(async () => (await state(page)).scrollLeft)
      .toBeLessThan(resizedState.scrollLeft);
    await settle(page);
    const wrappedState = await state(page);
    const wrapped = await horizontalViewportGeometry(page);
    expect(wrappedState.scrollLeft).toBeLessThanOrEqual(
      Math.max(0, wrappedState.scrollWidth - wrapped.scrollable.width) + 1,
    );
    expectMarkdownPinnedToVisibleViewport(wrapped);

    await control(page, 'set_soft_wrap', false);
    await expect.poll(async () => (await state(page)).softWrap).toBe(false);
    await expect
      .poll(async () => (await state(page)).scrollWidth)
      .toBeGreaterThan(resized.scrollable.width + 100);
    await control(page, 'set_scroll_left', middleRequest);
    await expect
      .poll(async () => (await state(page)).scrollLeft)
      .toBeGreaterThan(0);
    await settle(page);
    expectMarkdownPinnedToVisibleViewport(
      await horizontalViewportGeometry(page),
    );
  } finally {
    reporter.dispose();
  }
});

test('interactive Diago controls pan zoom fit resize and keep sibling state independent', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    const viewports = page.locator(`${zone} ${diagramViewport}`);
    await expect(viewports).toHaveCount(2);
    const large = viewports.nth(0);
    const compact = viewports.nth(1);

    // Before either diagram has been touched, a host resize recomputes the
    // bounded initial fit. Both controllers observe the same public Viewer
    // layout but own independent transforms.
    const compactWide = await viewportGeometry(compact);
    await control(page, 'resize', 420);
    await expect
      .poll(async () => (await viewportGeometry(compact)).wrapperWidth)
      .toBeLessThan(compactWide.wrapperWidth - 20);
    const compactNarrow = await viewportGeometry(compact);
    expect(compactNarrow.scale).toBeGreaterThan(0);
    expect(compactNarrow.scale).toBeLessThanOrEqual(1);
    expectNear(compactNarrow.scaleY, compactNarrow.scale, 0.001);
    expect(compactNarrow.wrapperHeight).toBeLessThanOrEqual(
      compactNarrow.heightLimit + 1,
    );
    expect(compactNarrow.fullyVisible).toBe(true);
    expect(
      Math.abs(compactNarrow.scale - compactWide.scale),
    ).toBeGreaterThan(0.001);

    await large.scrollIntoViewIfNeeded();
    await settle(page);
    await control(page, 'set_model_selection');
    const selectionBeforeInput = (await state(page)).selection;
    const compactBeforeLargeInput = await viewportGeometry(compact);
    const initial = await viewportGeometry(large);
    expect(initial.scale).toBeGreaterThan(0);
    expect(initial.scale).toBeLessThan(1);
    expectNear(initial.wrapperHeight, initial.heightLimit);
    expect(initial.fullyVisible).toBe(true);

    const pan = large.locator('[aria-label="Toggle pan mode"]');
    const zoomOut = large.locator('[aria-label="Zoom out"]');
    const zoomIn = large.locator('[aria-label="Zoom in"]');
    const fit = large.locator('[aria-label="Fit diagram"]');
    await zoomIn.focus();
    const windowWidth = await page.evaluate(() => window.innerWidth);
    await page.mouse.move(windowWidth - 2, 20);
    await expect(large.locator(`:scope > ${diagramControls}`)).toHaveCSS(
      'opacity',
      '1',
    );
    await pan.click();
    await expect(pan).toHaveAttribute('aria-pressed', 'true');
    const panBox = await large.boundingBox();
    expect(panBox).not.toBeNull();
    const panX = panBox.x + panBox.width * 0.35;
    const panY = Math.max(30, Math.min(620, panBox.y + 160));
    await page.mouse.move(panX, panY);
    await page.mouse.down();
    await page.mouse.move(panX + 36, panY + 24, { steps: 3 });
    await page.mouse.up();
    const plainPanned = await viewportGeometry(large);
    expectNear(plainPanned.translateX - initial.translateX, 36, 2);
    expectNear(plainPanned.translateY - initial.translateY, 24, 2);
    await pan.click();
    await expect(pan).toHaveAttribute('aria-pressed', 'false');

    // Alt drag pans while the toggle is off. Its >3px single-move threshold is
    // covered exactly by the reference test; this direct proof uses a clearly
    // visible gesture.
    const altPanBox = await large.boundingBox();
    const altPanX = altPanBox.x + altPanBox.width * 0.35;
    const altPanY = Math.max(30, Math.min(620, altPanBox.y + 190));
    await page.keyboard.down('Alt');
    await page.mouse.move(altPanX, altPanY);
    await page.mouse.down();
    await page.mouse.move(altPanX + 28, altPanY - 20, { steps: 2 });
    await page.mouse.up();
    await page.keyboard.up('Alt');
    const modifierPanned = await viewportGeometry(large);
    expectNear(modifierPanned.translateX - plainPanned.translateX, 28, 2);
    expectNear(modifierPanned.translateY - plainPanned.translateY, -20, 2);

    await zoomOut.click();
    expectNear((await viewportGeometry(large)).scale, initial.scale, 0.001);
    await zoomIn.click();
    expectNear(
      (await viewportGeometry(large)).scale,
      initial.scale * 1.25,
      0.001,
    );
    await fit.click();
    const fitted = await viewportGeometry(large);
    expect(fitted.scale).toBeGreaterThan(0);
    expect(fitted.scale).toBeLessThan(1);
    const fittedRect = await large.evaluate((wrapper) => {
      const svg = wrapper.querySelector(
        ':scope > .moonbit-viewer-markdown-diagram-content > svg',
      );
      const viewportRect = wrapper.getBoundingClientRect();
      const svgRect = svg.getBoundingClientRect();
      return {
        left: svgRect.left - viewportRect.left,
        right: viewportRect.right - svgRect.right,
        top: svgRect.top - viewportRect.top,
        bottom: viewportRect.bottom - svgRect.bottom,
      };
    });
    expect(fittedRect.left).toBeGreaterThanOrEqual(15);
    expect(fittedRect.right).toBeGreaterThanOrEqual(15);
    expect(fittedRect.top).toBeGreaterThanOrEqual(15);
    expect(fittedRect.bottom).toBeGreaterThanOrEqual(15);

    await zoomIn.click();
    const toolbarZoomed = await viewportGeometry(large);
    expectNear(toolbarZoomed.scale, fitted.scale * 1.25, 0.002);
    const wheelOwnership = await large.evaluate((wrapper) => {
      const rect = wrapper.getBoundingClientRect();
      const dispatch = (init) => {
        const event = new WheelEvent('wheel', {
          bubbles: true,
          cancelable: true,
          clientX: rect.left + rect.width / 2,
          clientY: rect.top + Math.min(100, rect.height / 2),
          ...init,
        });
        const returned = wrapper.dispatchEvent(event);
        return { defaultPrevented: event.defaultPrevented, returned };
      };
      return {
        alt: dispatch({ altKey: true, deltaY: -20 }),
        ctrl: dispatch({ ctrlKey: true, deltaY: -2 }),
      };
    });
    expect(wheelOwnership).toEqual({
      alt: { defaultPrevented: true, returned: false },
      ctrl: { defaultPrevented: true, returned: false },
    });
    const modifierZoomed = await viewportGeometry(large);
    expect(modifierZoomed.scale).toBeGreaterThan(toolbarZoomed.scale);

    const clickBox = await large.boundingBox();
    const clickPosition = {
      x: clickBox.width * 0.3,
      y: Math.min(120, clickBox.height * 0.3),
    };
    const beforeAltClick = await viewportGeometry(large);
    await large.click({ position: clickPosition, modifiers: ['Alt'] });
    const afterAltClick = await viewportGeometry(large);
    expect(afterAltClick.scale).toBeGreaterThan(beforeAltClick.scale);
    await large.click({
      position: clickPosition,
      modifiers: ['Alt', 'Shift'],
    });
    expect((await viewportGeometry(large)).scale).toBeLessThan(
      afterAltClick.scale,
    );

    const compactAfterLargeInput = await viewportGeometry(compact);
    expect(compactAfterLargeInput.transform).toBe(
      compactBeforeLargeInput.transform,
    );

    const handle = large.locator(diagramResizeHandle);
    await handle.scrollIntoViewIfNeeded();
    await settle(page);
    const heightBeforePointer = (await viewportGeometry(large)).wrapperHeight;
    const zoneHeightBeforePointer = await large.evaluate(
      (wrapper) =>
        wrapper.closest('.moonbit-viewer-markdown-comment')
          .getBoundingClientRect().height,
    );
    const handleBox = await handle.boundingBox();
    expect(handleBox).not.toBeNull();
    await page.mouse.move(
      handleBox.x + handleBox.width / 2,
      handleBox.y + handleBox.height / 2,
    );
    await page.mouse.down();
    await page.mouse.move(
      handleBox.x + handleBox.width / 2,
      handleBox.y + handleBox.height / 2 + 60,
      { steps: 4 },
    );
    await page.mouse.up();
    await expect
      .poll(async () => (await viewportGeometry(large)).wrapperHeight)
      .toBeGreaterThan(heightBeforePointer + 55);
    await expect
      .poll(() =>
        large.evaluate(
          (wrapper) =>
            wrapper.closest('.moonbit-viewer-markdown-comment')
              .getBoundingClientRect().height,
        ),
      )
      .toBeGreaterThan(zoneHeightBeforePointer + 55);

    await handle.focus();
    const heightBeforeKeyboard = (await viewportGeometry(large)).wrapperHeight;
    await page.keyboard.press('ArrowDown');
    await expect
      .poll(async () => (await viewportGeometry(large)).wrapperHeight)
      .toBeCloseTo(heightBeforeKeyboard + 10, 0);
    await page.keyboard.press('Shift+ArrowDown');
    await expect
      .poll(async () => (await viewportGeometry(large)).wrapperHeight)
      .toBeCloseTo(heightBeforeKeyboard + 60, 0);
    await page.keyboard.press('ArrowUp');
    await expect
      .poll(async () => (await viewportGeometry(large)).wrapperHeight)
      .toBeCloseTo(heightBeforeKeyboard + 50, 0);

    // A custom height wins across a later host resize, while prior fit/pan
    // keeps scale and preserves a visible origin instead of resetting.
    const beforeResponsiveResize = await viewportGeometry(large);
    await control(page, 'resize', 620);
    await expect
      .poll(async () => (await viewportGeometry(large)).wrapperWidth)
      .toBeGreaterThan(beforeResponsiveResize.wrapperWidth + 100);
    const afterResponsiveResize = await viewportGeometry(large);
    expectNear(
      afterResponsiveResize.wrapperHeight,
      beforeResponsiveResize.wrapperHeight,
      1,
    );
    expectNear(afterResponsiveResize.scale, beforeResponsiveResize.scale, 0.002);
    expect(afterResponsiveResize.transform).not.toBe(
      beforeResponsiveResize.transform,
    );

    // A pure horizontal source scroll must not enter the diagram resize or
    // transform paths. In particular, its caller-selected height is stable.
    // Bring the long source sentinel into the vertically rendered range so
    // it contributes the no-wrap horizontal extent used by this gesture.
    await control(page, 'set_scroll_top', 0);
    await settle(page);
    const customHeightBeforeHorizontal = await viewportGeometry(large);
    await control(page, 'set_scroll_left', 200);
    await expect
      .poll(async () => (await state(page)).scrollLeft)
      .toBeGreaterThan(0);
    await settle(page);
    const customHeightAfterHorizontal = await viewportGeometry(large);
    expectNear(
      customHeightAfterHorizontal.wrapperHeight,
      customHeightBeforeHorizontal.wrapperHeight,
    );
    expectNear(
      customHeightAfterHorizontal.inlineHeight,
      customHeightBeforeHorizontal.inlineHeight,
    );
    expect(customHeightAfterHorizontal.transform).toBe(
      customHeightBeforeHorizontal.transform,
    );
    expect((await state(page)).selection).toEqual(selectionBeforeInput);
  } finally {
    reporter.dispose();
  }
});

test('diagram viewports never cover the editor scrollbar rail and real thumb drag preserves selection', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    const large = page.locator(`${zone} ${diagramViewport}`).first();
    const scrollable = page.locator(editorScrollable);
    const verticalBar = scrollable.locator(':scope > .scrollbar.vertical');
    const slider = verticalBar.locator(':scope > .slider');
    await expect(verticalBar).toHaveCount(1);
    await expect(slider).toHaveCount(1);

    // Put the bounded diagram under the scrollbar rail so the hit test would
    // expose even a one-pixel Markdown overflow into the rail.
    const desiredScrollTop = await large.evaluate((wrapper) => {
      const editorRoot = wrapper.closest('.monaco-editor.readonly-editor');
      const editorRect = editorRoot.getBoundingClientRect();
      const wrapperRect = wrapper.getBoundingClientRect();
      const current = Number(
        globalThis.__markdownCommentsControls.state().scrollTop,
      );
      return Math.max(
        0,
        Math.round(current + wrapperRect.top - editorRect.top + 20),
      );
    });
    await control(page, 'set_scroll_top', desiredScrollTop);
    await settle(page);
    await control(page, 'set_model_selection');
    const selectionBeforeDrag = (await state(page)).selection;

    const viewportSize = await page.evaluate(() => ({
      width: window.innerWidth,
      height: window.innerHeight,
    }));
    await page.mouse.move(viewportSize.width - 2, viewportSize.height - 2);
    await expect(verticalBar).toHaveClass(
      /(^|\s)invisible(\s|$).*($|\s)fade(\s|$)/,
      { timeout: 2_500 },
    );
    const hiddenPoint = await slider.evaluate((thumb) => {
      const rect = thumb.getBoundingClientRect();
      const diagram = document.querySelector(
        '.markdown-comments-host .moonbit-viewer-markdown-diagram-viewport',
      );
      const diagramRect = diagram.getBoundingClientRect();
      return {
        x: rect.left + rect.width / 2,
        y: diagramRect.top + diagramRect.height / 2,
      };
    });
    const hiddenHit = await page.evaluate(({ x, y }) => {
      const node = document.elementFromPoint(x, y);
      return {
        hitClass: String(node?.className ?? ''),
        markdownOuter: Boolean(
          node?.closest?.('.moonbit-viewer-markdown-comment'),
        ),
        markdownDescendant: Boolean(
          node?.closest?.('.moonbit-viewer-markdown-comment-content'),
        ),
        diagramDescendant: Boolean(
          node?.closest?.('.moonbit-viewer-markdown-diagram-viewport'),
        ),
      };
    }, hiddenPoint);
    const hiddenPointRelation = await large.evaluate(
      (wrapper, { x, y }) => {
        const viewportRect = wrapper.getBoundingClientRect();
        const outerRect = wrapper
          .closest('.moonbit-viewer-markdown-comment')
          .getBoundingClientRect();
        return {
          overlapsDiagramRow:
            y >= viewportRect.top && y <= viewportRect.bottom,
          atOrBeyondMarkdownRight: x >= outerRect.right - 1,
        };
      },
      hiddenPoint,
    );
    expect(hiddenPointRelation).toEqual({
      overlapsDiagramRow: true,
      atOrBeyondMarkdownRight: true,
    });
    expect(hiddenHit).toMatchObject({
      markdownOuter: false,
      markdownDescendant: false,
      diagramDescendant: false,
    });

    await scrollable.hover({ position: { x: 20, y: 20 } });
    await expect(verticalBar).toHaveClass(/(^|\s)visible(\s|$)/);
    const visiblePoint = await slider.evaluate((thumb) => {
      const rect = thumb.getBoundingClientRect();
      return {
        x: rect.left + rect.width / 2,
        y: rect.top + rect.height / 2,
      };
    });
    const visibleHit = await page.evaluate(({ x, y }) => {
      const thumb = document.querySelector(
        '.markdown-comments-host .monaco-scrollable-element.editor-scrollable'
          + ' > .scrollbar.vertical > .slider',
      );
      const hit = document.elementFromPoint(x, y);
      return {
        slider: hit === thumb || thumb.contains(hit),
        hitClass: String(hit?.className ?? ''),
      };
    }, visiblePoint);
    expect(visibleHit.slider).toBe(true);

    const scrollTopBeforeDrag = (await state(page)).scrollTop;
    await page.mouse.move(visiblePoint.x, visiblePoint.y);
    await page.mouse.down();
    await page.mouse.move(visiblePoint.x, visiblePoint.y + 80, { steps: 4 });
    await page.mouse.up();
    await expect
      .poll(async () => (await state(page)).scrollTop)
      .toBeGreaterThan(scrollTopBeforeDrag);
    expect((await state(page)).selection).toEqual(selectionBeforeDrag);
    expect(await page.evaluate(() => document.getSelection()?.toString())).toBe(
      '',
    );
    await expect(slider).not.toHaveClass(/active/);
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
    const eofContent = page.locator(zone).nth(2).locator(content);
    const initialDiagram = eofContent.locator(diagramViewport).nth(0);
    const oldDiagram = await initialDiagram.elementHandle();
    const oldDiagramContent = await initialDiagram
      .locator(`:scope > ${diagramContent}`)
      .elementHandle();
    const oldPanButton = await initialDiagram
      .locator('[aria-label="Toggle pan mode"]')
      .elementHandle();
    expect(oldDiagram).not.toBeNull();
    expect(oldDiagramContent).not.toBeNull();
    expect(oldPanButton).not.toBeNull();
    const oldPanPressed = await oldPanButton.evaluate((button) =>
      button.getAttribute('aria-pressed'));
    const initialDiagramGeometry = await viewportGeometry(initialDiagram);
    await initialDiagram.locator('[aria-label="Zoom in"]').click();
    const initialResizeHandle = initialDiagram.locator(diagramResizeHandle);
    await initialResizeHandle.focus();
    await page.keyboard.press('ArrowDown');
    const interactedDiagram = await viewportGeometry(initialDiagram);
    expect(interactedDiagram.scale).toBeGreaterThan(
      initialDiagramGeometry.scale,
    );
    await eofContent.evaluate((node) => {
      node.style.display = 'none';
    });
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
      [10, 29],
    ]);
    const replacementDiagrams = eofContent.locator(diagramViewport);
    await expect(replacementDiagrams).toHaveCount(2);
    const replacementDiagram = replacementDiagrams.nth(0);
    const pendingHeight = await replacementDiagram.evaluate(
      (wrapper) => wrapper.style.height,
    );
    expect(pendingHeight).not.toBe('0px');
    expect(await oldDiagram.evaluate((node) => node.isConnected)).toBe(false);
    expect(
      await oldDiagramContent.evaluate((node) => node.isConnected),
    ).toBe(false);
    await oldPanButton.evaluate((button) => button.click());
    expect(
      await oldPanButton.evaluate((button) =>
        button.getAttribute('aria-pressed')),
    ).toBe(oldPanPressed);

    await eofContent.evaluate((node) => {
      node.style.removeProperty('display');
    });
    await expect
      .poll(async () => (await viewportGeometry(replacementDiagram)).wrapperHeight)
      .toBeGreaterThan(0);
    const replacementGeometry = await viewportGeometry(replacementDiagram);
    expect(replacementGeometry.scale).toBeGreaterThan(0);
    expect(replacementGeometry.scale).toBeLessThanOrEqual(1);
    expect(replacementGeometry.fullyVisible).toBe(true);
    expect(
      Math.abs(
        replacementGeometry.wrapperHeight - interactedDiagram.wrapperHeight,
      ),
    ).toBeGreaterThan(5);

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
    expect(await zoneRanges(page)).toEqual([[81, 97]]);
    const retained = await page.locator(zone).elementHandle();
    expect(retained).not.toBeNull();
    await expect(page.locator(zone)).not.toBeVisible();
    const offscreenDiagram = page.locator(`${zone} ${diagramViewport}`);
    await expect(offscreenDiagram).toHaveCount(1);
    expect(
      await offscreenDiagram.evaluate((wrapper) => wrapper.style.height),
    ).toBe('');

    // Eighty short visible lines contribute 1440px. The provisional zone is
    // only one 18px line; crossing this threshold proves the still-offscreen
    // heading/list/image body has already entered scroll geometry.
    await expect
      .poll(async () => (await state(page)).scrollHeight)
      .toBeGreaterThan(1560);
    const wideHeight = (await state(page)).scrollHeight;
    const wideState = await state(page);
    const wideGeometry = await horizontalViewportGeometry(page);
    expect(wideState.softWrap).toBe(false);
    expect(wideState.scrollWidth).toBeGreaterThan(
      wideGeometry.scrollable.width + 100,
    );
    expect(wideGeometry.viewZones.width).toBeGreaterThan(
      wideGeometry.scrollable.width + 100,
    );

    await control(page, 'set_scroll_left', 300);
    await expect
      .poll(async () => (await state(page)).scrollLeft)
      .toBeGreaterThan(0);
    await settle(page);
    const scrolledGeometry = await horizontalViewportGeometry(page);
    expect(scrolledGeometry.source.left).toBeLessThan(
      wideGeometry.source.left - 100,
    );

    await control(page, 'resize', 240);
    await expect(page.locator(zone)).not.toBeVisible();
    await expect
      .poll(async () => (await state(page)).scrollLeft)
      .toBeGreaterThan(0);
    await expect
      .poll(async () => (await state(page)).scrollHeight)
      .toBeLessThan(wideHeight - 20);
    await settle(page);
    const hiddenNarrowGeometry = await horizontalViewportGeometry(page);
    expect(hiddenNarrowGeometry.viewZones.width).toBeGreaterThan(
      hiddenNarrowGeometry.scrollable.width + 100,
    );
    expect(
      await offscreenDiagram.evaluate((wrapper) => wrapper.style.height),
    ).toBe('');
    const narrowHeight = (await state(page)).scrollHeight;

    await control(page, 'scroll_to_bottom');
    await settle(page);
    await expect(page.locator(zone)).toBeVisible();
    await expect
      .poll(async () => (await viewportGeometry(offscreenDiagram)).wrapperHeight)
      .toBeGreaterThan(0);
    const revealedDiagram = await viewportGeometry(offscreenDiagram);
    expectNear(revealedDiagram.scale, 1, 0.001);
    expectNear(revealedDiagram.translateY, 0, 0.01);
    expect(
      await retained.evaluate(
        (node) =>
          node ===
          document.querySelector('.moonbit-viewer-markdown-comment'),
      ),
    ).toBe(true);
    const revealedBounds = await retained.evaluate((outer) => {
      const root = outer.closest('.monaco-editor.readonly-editor');
      const scrollable = root.querySelector(
        '.monaco-scrollable-element.editor-scrollable',
      );
      const rail = scrollable.querySelector(':scope > .scrollbar.vertical');
      const outerRect = outer.getBoundingClientRect();
      const scrollableRect = scrollable.getBoundingClientRect();
      const railRect = rail.getBoundingClientRect();
      return {
        outerLeft: outerRect.left,
        outerRight: outerRect.right,
        scrollableLeft: scrollableRect.left,
        railLeft: railRect.left,
      };
    });
    expectNear(revealedBounds.outerLeft, revealedBounds.scrollableLeft);
    expectNear(revealedBounds.outerRight, revealedBounds.railLeft);
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
    const initialDiagram = page.locator(`${zone} ${diagramViewport}`).first();
    const retainedDiagram = await initialDiagram.elementHandle();
    const retainedPanButton = await initialDiagram
      .locator('[aria-label="Toggle pan mode"]')
      .elementHandle();
    expect(initialRoot).not.toBeNull();
    expect(initialZone).not.toBeNull();
    expect(retainedDiagram).not.toBeNull();
    expect(retainedPanButton).not.toBeNull();
    const retainedPanPressed = await retainedPanButton.evaluate((button) =>
      button.getAttribute('aria-pressed'));
    await initialDiagram.locator('[aria-label="Zoom in"]').click();

    await control(page, 'detach');
    await settle(page);
    // Detach restores the no-model placeholder, which deliberately carries
    // the same editor root classes but has no live view/model DOM.
    await expect(page.locator(editor)).toHaveCount(1);
    await expect(page.locator(`${editor} .lines-content`)).toHaveCount(0);
    await expect(page.locator(zone)).toHaveCount(0);
    expect(await initialRoot.evaluate((node) => node.isConnected)).toBe(false);
    expect(await initialZone.evaluate((node) => node.isConnected)).toBe(false);
    expect(await retainedDiagram.evaluate((node) => node.isConnected)).toBe(
      false,
    );
    expect(
      await retainedDiagram.evaluate((node) => ({
        viewport: node.classList.contains(
          'moonbit-viewer-markdown-diagram-viewport',
        ),
        directSvg: Boolean(node.querySelector(':scope > svg')),
        controls: Boolean(
          node.querySelector(
            ':scope > .moonbit-viewer-markdown-diagram-controls',
          ),
        ),
      })),
    ).toEqual({ viewport: false, directSvg: true, controls: false });
    await retainedPanButton.evaluate((button) => button.click());
    expect(
      await retainedPanButton.evaluate((button) =>
        button.getAttribute('aria-pressed')),
    ).toBe(retainedPanPressed);
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
    await expect(page.locator(`${zone} ${diagramViewport}`)).toHaveCount(2);
    expect(await replacementRoot.evaluate((node) => node.isConnected)).toBe(false);
    expect(await replacementZone.evaluate((node) => node.isConnected)).toBe(false);
    expect(await state(page)).toMatchObject({
      attachedKind: 'primary',
      primaryAttachedEditors: 1,
      replacementAttachedEditors: 0,
    });
    const reattachedZones = await page.locator(zone).elementHandles();
    const reattachedDiagrams = await page
      .locator(`${zone} ${diagramViewport}`)
      .elementHandles();
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
    for (const rendered of reattachedDiagrams) {
      expect(await rendered.evaluate((node) => node.isConnected)).toBe(false);
      expect(
        await rendered.evaluate((node) =>
          node.classList.contains(
            'moonbit-viewer-markdown-diagram-viewport',
          ),
        ),
      ).toBe(false);
    }
  } finally {
    reporter.dispose();
  }
});

test('renders exact Mermaid fences through the pinned CDN module and rerenders them in place for Viewer themes', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    expect((await mermaidLog(page)).moduleLoads).toBe(0);
    await control(page, 'mermaid_source');

    const mermaidDiagram = `${zone} ${diagram}[data-diagram-language="mermaid"]`;
    const mermaidDiagrams = page.locator(mermaidDiagram);
    const renderedSvgs = page.locator(`${mermaidDiagram} > svg`);
    await expect(mermaidDiagrams).toHaveCount(3);
    await expect(renderedSvgs).toHaveCount(2);
    await expect
      .poll(async () => (await mermaidLog(page)).reject.length)
      .toBe(1);
    await expect
      .poll(async () => (await mermaidLog(page)).bind.length)
      .toBe(2);

    const invalid = mermaidDiagrams.filter({ hasText: 'INVALID' });
    await expect(invalid).toHaveCount(1);
    await expect(invalid.locator(':scope > svg')).toHaveCount(0);
    await expect(invalid.locator('.monaco-tokenized-source')).toContainText(
      'INVALID',
    );
    await expect(page.locator(zone)).toContainText('CASE_SENSITIVE_FALLBACK');
    await expect(
      page.locator(
        `${diagram}[data-diagram-language="Mermaid"], ${diagram}[data-diagram-language="CASE_SENSITIVE_FALLBACK"]`,
      ),
    ).toHaveCount(0);

    const initialSvgState = await renderedSvgs.evaluateAll((nodes) =>
      nodes.map((node) => ({
        id: node.getAttribute('data-mermaid-id'),
        source: node.getAttribute('data-mermaid-source'),
        theme: node.getAttribute('data-mermaid-theme'),
      })),
    );
    expect(initialSvgState.map(({ source }) => source).sort()).toEqual([
      'VALID_ONE',
      'VALID_SECOND',
    ]);
    expect(initialSvgState.every(({ theme }) => theme === 'dark')).toBe(true);
    expect(new Set(initialSvgState.map(({ id }) => id)).size).toBe(2);

    const tallMermaid = page.locator(
      `${mermaidDiagram} > svg[data-mermaid-source="VALID_SECOND"]`,
    );
    const tallMermaidLayout = await tallMermaid.evaluate((svg) => {
      const wrapper = svg.parentElement;
      const wrapperRect = wrapper.getBoundingClientRect();
      const svgRect = svg.getBoundingClientRect();
      const viewBox = svg.viewBox.baseVal;
      return {
        heightLimit: Math.min(window.innerHeight * 0.5, 480),
        wrapperHeight: wrapperRect.height,
        svgHeight: svgRect.height,
        svgAspectRatio: svgRect.width / svgRect.height,
        viewBoxAspectRatio: viewBox.width / viewBox.height,
        fullyVisible:
          svgRect.left >= wrapperRect.left - 1 &&
          svgRect.right <= wrapperRect.right + 1 &&
          svgRect.top >= wrapperRect.top - 1 &&
          svgRect.bottom <= wrapperRect.bottom + 1,
        overflowY: window.getComputedStyle(wrapper).overflowY,
      };
    });
    expectNear(tallMermaidLayout.svgHeight, tallMermaidLayout.heightLimit);
    expectNear(
      tallMermaidLayout.wrapperHeight,
      tallMermaidLayout.heightLimit,
    );
    expect(tallMermaidLayout.fullyVisible).toBe(true);
    expect(tallMermaidLayout.overflowY).toBe('auto');
    expect(
      Math.abs(
        tallMermaidLayout.svgAspectRatio -
          tallMermaidLayout.viewBoxAspectRatio,
      ),
    ).toBeLessThan(0.001);

    const initialLog = await mermaidLog(page);
    expect(initialLog.moduleLoads).toBe(1);
    expect(initialLog.render).toHaveLength(3);
    expect(new Set(initialLog.render.map(({ id }) => id)).size).toBe(3);
    for (const options of initialLog.initialize) {
      expect(options).toMatchObject({
        startOnLoad: false,
        securityLevel: 'strict',
        suppressErrorRendering: true,
        theme: 'dark',
      });
      expect(options.secure).toContain('theme');
    }
    expect(initialLog.bind.every(({ rootClass, connected }) =>
      rootClass.includes('moonbit-viewer-markdown-diagram') && connected)).toBe(
      true,
    );

    const retainedZone = await page.locator(zone).elementHandle();
    const retainedWrappers = await mermaidDiagrams.elementHandles();
    const darkHeight = await page
      .locator(zone)
      .evaluate((node) => node.getBoundingClientRect().height);
    expect(retainedZone).not.toBeNull();
    expect(retainedWrappers).toHaveLength(3);

    await control(page, 'theme_light');
    await expect(page.locator(editor)).toHaveAttribute('data-theme', 'light');
    await expect
      .poll(() =>
        renderedSvgs.evaluateAll((nodes) =>
          nodes.map((node) => node.getAttribute('data-mermaid-theme')),
        ),
      )
      .toEqual(['default', 'default']);
    await expect
      .poll(async () => (await mermaidLog(page)).render.length)
      .toBe(6);
    await expect
      .poll(() =>
        page.locator(zone).evaluate((node) => {
          const inner = node.querySelector(
            '.moonbit-viewer-markdown-comment-content',
          );
          const outer = node.getBoundingClientRect().height;
          const style = Number.parseFloat(node.style.height);
          const innerHeight = inner.offsetHeight;
          return (
            Math.abs(outer - innerHeight) <= 1 &&
            Math.abs(style - innerHeight) <= 1
          );
        }),
      )
      .toBe(true);
    const lightGeometry = await page.locator(zone).evaluate((node) => {
      const inner = node.querySelector(
        '.moonbit-viewer-markdown-comment-content',
      );
      return {
        outer: node.getBoundingClientRect().height,
        style: Number.parseFloat(node.style.height),
        inner: inner.offsetHeight,
      };
    });
    expect(Math.abs(lightGeometry.outer - lightGeometry.inner)).toBeLessThanOrEqual(
      1,
    );
    expect(Math.abs(lightGeometry.style - lightGeometry.inner)).toBeLessThanOrEqual(
      1,
    );
    expect(lightGeometry.outer).toBeGreaterThan(darkHeight);
    expect(
      await retainedZone.evaluate(
        (node) =>
          node ===
          document.querySelector(
            '.markdown-comments-host .moonbit-viewer-markdown-comment',
          ),
      ),
    ).toBe(true);
    for (let index = 0; index < retainedWrappers.length; index += 1) {
      expect(
        await retainedWrappers[index].evaluate(
          (node, selectorIndex) =>
            node ===
            document.querySelectorAll(
              '.markdown-comments-host .moonbit-viewer-markdown-diagram[data-diagram-language="mermaid"]',
            )[selectorIndex],
          index,
        ),
      ).toBe(true);
    }

    await control(page, 'theme_dark');
    await expect(page.locator(editor)).toHaveAttribute('data-theme', 'dark');
    await expect
      .poll(() =>
        renderedSvgs.evaluateAll((nodes) =>
          nodes.map((node) => node.getAttribute('data-mermaid-theme')),
        ),
      )
      .toEqual(['dark', 'dark']);
    await expect
      .poll(async () => (await mermaidLog(page)).render.length)
      .toBe(9);
    await expect
      .poll(() =>
        page
          .locator(zone)
          .evaluate((node) => node.getBoundingClientRect().height),
      )
      .toBeLessThan(lightGeometry.outer);

    const finalLog = await mermaidLog(page);
    // The wrappers are retained, but every official render call receives a
    // fresh id so the still-mounted previous SVG cannot collide with
    // Mermaid's temporary render DOM.
    expect(new Set(finalLog.render.map(({ id }) => id)).size).toBe(9);
    expect(finalLog.initialize.map(({ theme }) => theme)).toEqual([
      'dark',
      'dark',
      'dark',
      'default',
      'default',
      'default',
      'dark',
      'dark',
      'dark',
    ]);
    expect(finalLog.bind).toHaveLength(6);
    expect(finalLog.reject).toHaveLength(3);
  } finally {
    reporter.dispose();
  }
});

test('drops delayed Mermaid results after same-key replacement and keeps the ViewZone owner current', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    await control(page, 'mermaid_delayed_old_source');
    await expect
      .poll(async () => (await mermaidLog(page)).pending.length)
      .toBe(1);
    const retainedZone = await page.locator(zone).elementHandle();
    expect(retainedZone).not.toBeNull();
    await expect(page.locator(zone)).toContainText('DELAYED_OLD');
    await expect(
      page.locator(
        `${zone} ${diagram}[data-diagram-language="mermaid"] > svg`,
      ),
    ).toHaveCount(0);

    await page.evaluate(() => {
      globalThis.__markdownCommentsObservedMermaidSources = [];
      globalThis.__markdownCommentsMermaidObserver = new MutationObserver(() => {
        for (const svg of document.querySelectorAll(
          '.markdown-comments-host [data-mermaid-source]',
        )) {
          globalThis.__markdownCommentsObservedMermaidSources.push(
            svg.getAttribute('data-mermaid-source'),
          );
        }
      });
      globalThis.__markdownCommentsMermaidObserver.observe(
        document.querySelector('.markdown-comments-host'),
        { childList: true, subtree: true },
      );
    });

    await control(page, 'mermaid_delayed_new_source');
    await expect(page.locator(zone)).toContainText('CURRENT_NEW');
    expect(
      await retainedZone.evaluate(
        (node) =>
          node ===
          document.querySelector(
            '.markdown-comments-host .moonbit-viewer-markdown-comment',
          ),
      ),
    ).toBe(true);
    expect(await releaseMermaid(page, 'DELAYED_OLD')).toBe(true);

    const currentSvg = page.locator(
      `${zone} ${diagram}[data-diagram-language="mermaid"] > svg`,
    );
    await expect(currentSvg).toHaveCount(1);
    await expect(currentSvg).toHaveAttribute(
      'data-mermaid-source',
      'CURRENT_NEW',
    );
    await settle(page);
    expect(
      await page.evaluate(
        () => globalThis.__markdownCommentsObservedMermaidSources,
      ),
    ).not.toContain('DELAYED_OLD');
    const log = await mermaidLog(page);
    expect(log.render.map(({ source }) => source)).toEqual([
      expect.stringContaining('DELAYED_OLD'),
      expect.stringContaining('CURRENT_NEW'),
    ]);
    expect(new Set(log.render.map(({ id }) => id)).size).toBe(2);
    expect(log.bind).toHaveLength(1);
    expect(log.bind[0]).toMatchObject({
      source: expect.stringContaining('CURRENT_NEW'),
      connected: true,
    });
    const measured = await page.locator(zone).evaluate((node) => {
      const inner = node.querySelector(
        '.moonbit-viewer-markdown-comment-content',
      );
      return {
        outer: node.getBoundingClientRect().height,
        style: Number.parseFloat(node.style.height),
        inner: inner.offsetHeight,
      };
    });
    expect(Math.abs(measured.outer - measured.inner)).toBeLessThanOrEqual(1);
    expect(Math.abs(measured.style - measured.inner)).toBeLessThanOrEqual(1);
  } finally {
    await page.evaluate(() =>
      globalThis.__markdownCommentsMermaidObserver?.disconnect(),
    );
    reporter.dispose();
  }
});

test('commits only the latest theme after rapid light and dark changes while Mermaid is pending', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    await control(page, 'mermaid_delayed_old_source');
    await expect
      .poll(async () =>
        (await mermaidLog(page)).pending.map(({ theme }) => theme),
      )
      .toEqual(['dark']);

    const retainedZone = await page.locator(zone).elementHandle();
    const mermaidWrapper = page.locator(
      `${zone} ${diagram}[data-diagram-language="mermaid"]`,
    );
    const retainedWrapper = await mermaidWrapper.elementHandle();
    expect(retainedZone).not.toBeNull();
    expect(retainedWrapper).not.toBeNull();
    await observeMermaidCommits(page);

    await page.evaluate(() => {
      const controls = globalThis.__markdownCommentsControls;
      controls.theme_light();
      controls.theme_dark();
    });
    await expect(page.locator(editor)).toHaveAttribute('data-theme', 'dark');
    expect(
      await retainedZone.evaluate(
        (node) =>
          node ===
          document.querySelector(
            '.markdown-comments-host .moonbit-viewer-markdown-comment',
          ),
      ),
    ).toBe(true);
    expect(
      await retainedWrapper.evaluate(
        (node) =>
          node ===
          document.querySelector(
            '.markdown-comments-host .moonbit-viewer-markdown-diagram[data-diagram-language="mermaid"]',
          ),
      ),
    ).toBe(true);

    expect(await releaseMermaid(page, 'DELAYED_OLD')).toBe(true);
    await expect
      .poll(async () =>
        (await mermaidLog(page)).pending.map(({ theme }) => theme),
      )
      .toEqual(['default']);
    await expect(mermaidWrapper.locator(':scope > svg')).toHaveCount(0);
    expect(await mermaidCommits(page)).toEqual([]);

    expect(await releaseMermaid(page, 'DELAYED_OLD')).toBe(true);
    await expect
      .poll(async () =>
        (await mermaidLog(page)).pending.map(({ theme }) => theme),
      )
      .toEqual(['dark']);
    await expect(mermaidWrapper.locator(':scope > svg')).toHaveCount(0);
    expect(await mermaidCommits(page)).toEqual([]);

    expect(await releaseMermaid(page, 'DELAYED_OLD')).toBe(true);
    await expect(mermaidWrapper.locator(':scope > svg')).toHaveCount(1);
    await expect(mermaidWrapper.locator(':scope > svg')).toHaveAttribute(
      'data-mermaid-theme',
      'dark',
    );
    await expect
      .poll(async () => (await mermaidCommits(page)).map(({ theme }) => theme))
      .toEqual(['dark']);

    const log = await mermaidLog(page);
    expect(log.render.map(({ theme }) => theme)).toEqual([
      'dark',
      'default',
      'dark',
    ]);
    expect(log.bind).toHaveLength(1);
    expect(log.bind[0]).toMatchObject({
      theme: 'dark',
      connected: true,
    });
    expect(
      await retainedZone.evaluate(
        (node) =>
          node ===
          document.querySelector(
            '.markdown-comments-host .moonbit-viewer-markdown-comment',
          ),
      ),
    ).toBe(true);
    expect(
      await retainedWrapper.evaluate(
        (node) =>
          node ===
          document.querySelector(
            '.markdown-comments-host .moonbit-viewer-markdown-diagram[data-diagram-language="mermaid"]',
          ),
      ),
    ).toBe(true);
  } finally {
    await stopObservingMermaidCommits(page);
    reporter.dispose();
  }
});

test('drops pending Mermaid output after a direct model swap', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    await control(page, 'mermaid_delayed_old_source');
    await expect
      .poll(async () => (await mermaidLog(page)).pending.length)
      .toBe(1);
    const pendingId = (await mermaidLog(page)).pending[0].id;
    const oldZone = await page.locator(zone).elementHandle();
    const oldWrapper = await page
      .locator(
        `${zone} ${diagram}[data-diagram-language="mermaid"]`,
      )
      .elementHandle();
    expect(oldZone).not.toBeNull();
    expect(oldWrapper).not.toBeNull();
    await observeMermaidCommits(page);

    await control(page, 'attach_replacement');
    await expect(page.locator(zone)).toHaveCount(1);
    await expect(page.locator(zone)).toContainText('Replacement comment');
    expect(await state(page)).toMatchObject({
      attachedKind: 'replacement',
      primaryAttachedEditors: 0,
      replacementAttachedEditors: 1,
    });
    expect(await oldZone.evaluate((node) => node.isConnected)).toBe(false);
    expect(await oldWrapper.evaluate((node) => node.isConnected)).toBe(false);

    expect(await releaseMermaid(page, 'DELAYED_OLD')).toBe(true);
    await settle(page);
    await expect(
      page.locator(
        `${zone} ${diagram}[data-diagram-language="mermaid"] > svg`,
      ),
    ).toHaveCount(0);
    expect(await mermaidCommits(page)).toEqual([]);
    expect(
      (await mermaidLog(page)).bind.some(({ id }) => id === pendingId),
    ).toBe(false);
  } finally {
    await stopObservingMermaidCommits(page);
    reporter.dispose();
  }
});

test('keeps an offscreen Mermaid SVG and its ViewZone height synchronized across resize and reveal', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    await control(page, 'mermaid_offscreen_source');
    await expect(page.locator(zone)).toHaveCount(1);
    expect(await zoneRanges(page)).toEqual([[81, 88]]);
    const mermaidWrapper = page.locator(
      `${zone} ${diagram}[data-diagram-language="mermaid"]`,
    );
    const svg = mermaidWrapper.locator(':scope > svg');
    await expect(svg).toHaveCount(1);
    await expect(svg).toHaveAttribute(
      'data-mermaid-source',
      'RESPONSIVE_OFFSCREEN',
    );
    await expect(page.locator(zone)).not.toBeVisible();

    const retainedZone = await page.locator(zone).elementHandle();
    const retainedWrapper = await mermaidWrapper.elementHandle();
    const retainedSvg = await svg.elementHandle();
    expect(retainedZone).not.toBeNull();
    expect(retainedWrapper).not.toBeNull();
    expect(retainedSvg).not.toBeNull();

    const svgContract = await svg.evaluate((node) => ({
      width: node.getAttribute('width'),
      height: node.getAttribute('height'),
      viewBox: node.getAttribute('viewBox'),
    }));
    expect(svgContract).toEqual({
      width: '720',
      height: '240',
      viewBox: '0 0 720 240',
    });
    // The hidden projection has no live layout box or inline height. Eighty
    // padding lines plus mermaid_code_truth contribute a stable 81 * 18px;
    // the remainder is the ViewZone height already owned by scroll geometry.
    const wideScrollHeight = (await state(page)).scrollHeight;
    const wideMeasuredHeight = wideScrollHeight - 81 * 18;
    expect(wideMeasuredHeight).toBeGreaterThan(18);

    await control(page, 'resize', 240);
    await expect(page.locator(zone)).not.toBeVisible();
    await expect
      .poll(async () =>
        Math.abs((await state(page)).scrollHeight - wideScrollHeight),
      )
      .toBeGreaterThan(1);
    const narrowScrollHeight = (await state(page)).scrollHeight;
    const narrowMeasuredHeight = narrowScrollHeight - 81 * 18;
    expect(narrowMeasuredHeight).not.toBe(wideMeasuredHeight);
    expect(narrowMeasuredHeight).toBeGreaterThan(18);
    expect(
      await retainedZone.evaluate(
        (node) =>
          node ===
          document.querySelector(
            '.markdown-comments-host .moonbit-viewer-markdown-comment',
          ),
      ),
    ).toBe(true);
    expect(
      await retainedWrapper.evaluate(
        (node) =>
          node ===
          document.querySelector(
            '.markdown-comments-host .moonbit-viewer-markdown-diagram[data-diagram-language="mermaid"]',
          ),
      ),
    ).toBe(true);
    expect(
      await retainedSvg.evaluate(
        (node) =>
          node ===
          document.querySelector(
            '.markdown-comments-host .moonbit-viewer-markdown-diagram[data-diagram-language="mermaid"] > svg',
          ),
      ),
    ).toBe(true);

    await control(page, 'scroll_to_bottom');
    await settle(page);
    await expect(page.locator(zone)).toBeVisible();
    await expect
      .poll(async () =>
        Math.abs((await state(page)).scrollHeight - narrowScrollHeight),
      )
      .toBeLessThanOrEqual(1);
    const revealed = await page.locator(zone).evaluate((outer) => {
      const inner = outer.querySelector(
        '.moonbit-viewer-markdown-comment-content',
      );
      const rendered = outer.querySelector(
        '.moonbit-viewer-markdown-diagram[data-diagram-language="mermaid"] > svg',
      );
      const svgRect = rendered.getBoundingClientRect();
      return {
        outer: outer.getBoundingClientRect().height,
        style: Number.parseFloat(outer.style.height),
        inner: inner.offsetHeight,
        svgWidth: svgRect.width,
        svgHeight: svgRect.height,
        svgAspectRatio: svgRect.width / svgRect.height,
      };
    });
    expect(revealed.svgWidth).toBeGreaterThan(0);
    expect(revealed.svgHeight).toBeGreaterThan(0);
    expect(revealed.svgWidth).toBeLessThan(720);
    expect(Math.abs(revealed.svgAspectRatio - 3)).toBeLessThan(0.001);
    expect(Math.abs(revealed.outer - revealed.inner)).toBeLessThanOrEqual(1);
    expect(Math.abs(revealed.style - revealed.inner)).toBeLessThanOrEqual(1);
    expect(
      Math.abs(revealed.outer - narrowMeasuredHeight),
    ).toBeLessThanOrEqual(2);
  } finally {
    reporter.dispose();
  }
});

test('invalidates pending Mermaid work on model detach and idempotent Viewer disposal', async ({
  page,
}, testInfo) => {
  const reporter = await mountMarkdownComments(page, testInfo);
  try {
    await control(page, 'mermaid_delayed_old_source');
    await expect
      .poll(async () => (await mermaidLog(page)).pending.length)
      .toBe(1);
    const detachedId = (await mermaidLog(page)).pending[0].id;

    await control(page, 'detach');
    await expect(page.locator(zone)).toHaveCount(0);
    expect(await releaseMermaid(page, 'DELAYED_OLD')).toBe(true);
    await settle(page);
    expect(
      (await mermaidLog(page)).bind.some(({ id }) => id === detachedId),
    ).toBe(false);

    await control(page, 'reattach_primary');
    await expect
      .poll(async () => (await mermaidLog(page)).pending.length)
      .toBe(1);
    const disposedId = (await mermaidLog(page)).pending[0].id;
    expect(disposedId).not.toBe(detachedId);
    await control(page, 'dispose');
    await control(page, 'dispose');
    await expect(page.locator(host)).toBeEmpty();
    expect(await releaseMermaid(page, 'DELAYED_OLD')).toBe(true);
    await settle(page);

    const log = await mermaidLog(page);
    expect(log.bind.some(({ id }) => id === detachedId)).toBe(false);
    expect(log.bind.some(({ id }) => id === disposedId)).toBe(false);
    expect(log.released.map(({ id }) => id)).toEqual([
      detachedId,
      disposedId,
    ]);
    expect(await state(page)).toMatchObject({
      attachedKind: 'none',
      primaryAttachedEditors: 0,
      replacementAttachedEditors: 0,
      disposed: true,
    });
  } finally {
    reporter.dispose();
  }
});

test('renders through the real pinned Mermaid CDN when live diagnostics are enabled', async ({
  page,
}, testInfo) => {
  test.skip(
    !runLiveMermaidCdn,
    'set READONLY_EDITOR_TEST_LIVE_MERMAID_CDN=1 to exercise jsDelivr',
  );
  test.slow();
  const reporter = await mountMarkdownComments(page, testInfo, {
    liveMermaidCdn: true,
  });
  try {
    const moduleRequest = page.waitForRequest(
      (request) => request.url() === mermaidCdnUrl,
    );
    await control(page, 'mermaid_source');
    await moduleRequest;

    const mermaidDiagram = `${zone} ${diagram}[data-diagram-language="mermaid"]`;
    await expect(page.locator(mermaidDiagram)).toHaveCount(3);
    await expect(page.locator(`${mermaidDiagram} > svg`)).toHaveCount(2, {
      timeout: 30_000,
    });
    await expect(
      page.locator(
        `${mermaidDiagram}[data-mermaid-state="rendered"] > svg`,
      ),
    ).toHaveCount(2);
    const sizes = await page
      .locator(`${mermaidDiagram} > svg`)
      .evaluateAll((nodes) =>
        nodes.map((node) => {
          const rect = node.getBoundingClientRect();
          return { width: rect.width, height: rect.height };
        }),
      );
    expect(sizes.every(({ width, height }) => width > 0 && height > 0)).toBe(
      true,
    );
  } finally {
    reporter.dispose();
  }
});
