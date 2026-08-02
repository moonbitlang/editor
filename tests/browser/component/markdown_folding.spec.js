import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

const host = '.markdown-folding-host';
const root = `${host} > .moonbit-viewer-markdown-document`;
const viewport = `${root} > .moonbit-viewer-markdown-document-viewport`;
const article = `${viewport} > .moonbit-viewer-markdown-document-article`;
const overlays = `${root} > .moonbit-viewer-markdown-document-overlays`;
const hoverWidget = `${overlays} .moonbit-viewer-markdown-hover-widget`;
const toggle = `${article} .moonbit-viewer-markdown-fold-toggle`;

async function openFoldingScenario(page, testInfo) {
  const reporter = await installMoonBitReporter(page);
  await page.goto('/browser-tests/component.html?markdownFolding=1');
  await page.waitForFunction(() =>
    Boolean(globalThis.__markdownFoldingControls),
  );
  const report = await reporter.waitForReport(testInfo, {
    suite: 'markdown_folding',
  });
  expectMoonBitReportPassed(report, { suite: 'markdown_folding' });
  expect(report.metrics.initialCollapsedCount).toBe(1);
  return report;
}

function foldFacts(page) {
  return page.evaluate(() =>
    globalThis.__markdownFoldingControls.getFoldFacts(),
  );
}

function hoverCalls(page) {
  return page.evaluate(() =>
    globalThis.__markdownFoldingControls.getHoverCalls(),
  );
}

function projectionGeneration(page) {
  return page
    .locator(root)
    .getAttribute('data-markdown-projection-generation');
}

function visibleByText(page, text) {
  return page.locator(`${article} > *`, { hasText: text }).first()
    .evaluate((node) => getComputedStyle(node).display !== 'none');
}

async function moveToSourceText(page, text, utf16Delta = 0) {
  const point = await page.locator(article).evaluate(
    (articleNode, { text, utf16Delta }) => {
      const walker = document.createTreeWalker(
        articleNode,
        NodeFilter.SHOW_TEXT,
      );
      let node;
      while ((node = walker.nextNode())) {
        const index = String(node.textContent || '').indexOf(text);
        if (index < 0) continue;
        node.parentElement?.scrollIntoView({ block: 'center' });
        const range = document.createRange();
        const boundary = Math.min(
          index + utf16Delta,
          String(node.textContent || '').length,
        );
        range.setStart(node, boundary);
        range.setEnd(
          node,
          Math.min(boundary + 1, String(node.textContent || '').length),
        );
        const rect = range.getBoundingClientRect();
        return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
      }
      throw new Error(`text node not found: ${text}`);
    },
    { text, utf16Delta },
  );
  // Two-step move with jitter: a move to coordinates the pointer already
  // occupies emits no mousemove, and the bridge only requests on real events.
  await page.mouse.move(point.x + 14, point.y + 6);
  await page.mouse.move(point.x, point.y, { steps: 2 });
  return point;
}

async function releaseLatestHover(page, expectedCount, outcome) {
  await page.waitForFunction(
    (count) =>
      globalThis.__markdownFoldingControls.getHoverCalls().length >= count,
    expectedCount,
    { timeout: 4_000 },
  );
  const calls = await hoverCalls(page);
  expect(calls.length).toBe(expectedCount);
  await page.evaluate(
    ({ id, outcome }) =>
      globalThis.__markdownFoldingControls.releaseHover(id, outcome),
    { id: calls[calls.length - 1].id, outcome },
  );
  return calls[calls.length - 1];
}

test('auto-fold seeds the bulky deep section and real clicks fold and reveal', async ({ page }, testInfo) => {
  await openFoldingScenario(page, testInfo);
  const facts = await foldFacts(page);
  expect(facts.collapsed).toEqual([facts.deep]);
  // The seeded collapse is real layout removal, not decoration.
  await expect.poll(() => visibleByText(page, 'deep three')).toBe(false);
  await expect.poll(() => visibleByText(page, 'alpha prose')).toBe(true);

  // Every foldable heading carries one accessible control.
  await expect(page.locator(toggle)).toHaveCount(4);
  const deepToggle = page.locator(`${toggle}[data-collapsed="true"]`);
  await expect(deepToggle).toHaveAttribute('aria-expanded', 'false');

  const generationBefore = await projectionGeneration(page);

  // A real click expands the seeded section...
  await deepToggle.click();
  await expect.poll(() => visibleByText(page, 'deep three')).toBe(true);
  expect((await foldFacts(page)).collapsed).toEqual([]);

  // ...and a real click on Alpha's toggle collapses Alpha, hiding its fence
  // while Beta's fence stays live for semantic hover.
  const alphaToggle = page.locator(toggle).nth(1);
  await alphaToggle.click();
  await expect(alphaToggle).toHaveAttribute('aria-expanded', 'false');
  await expect.poll(() => visibleByText(page, 'alpha_answer')).toBe(false);
  await expect.poll(() => visibleByText(page, 'beta_answer')).toBe(true);

  await moveToSourceText(page, 'beta_answer', 2);
  await releaseLatestHover(page, 1, 'sibling section hover');
  await expect(page.locator(hoverWidget)).toContainText(
    'sibling section hover',
  );
  await expect(page.locator(hoverWidget)).toBeVisible();

  // Expanding Alpha brings its fence straight back to hover life -- and the
  // whole fold conversation never re-parsed the document.
  await page.mouse.move(5, 5);
  await alphaToggle.click();
  await expect.poll(() => visibleByText(page, 'alpha_answer')).toBe(true);
  await moveToSourceText(page, 'alpha_answer', 2);
  await releaseLatestHover(page, 2, 'revealed fence hover');
  await expect(page.locator(hoverWidget)).toContainText(
    'revealed fence hover',
  );
  expect(await projectionGeneration(page)).toBe(generationBefore);
});

test('section fold controls occupy the left heading gutter', async ({
  page,
}, testInfo) => {
  await openFoldingScenario(page, testInfo);
  const controls = page.locator(toggle);
  await expect(controls).toHaveCount(4);

  const geometry = await controls.nth(1).evaluate((button) => {
    const heading = button.parentElement;
    const articleNode = heading.closest(
      '.moonbit-viewer-markdown-document-article',
    );
    const textNode = Array.from(heading.childNodes).find(
      (node) => node.nodeType === Node.TEXT_NODE && node.textContent.trim(),
    );
    const textRange = document.createRange();
    textRange.selectNodeContents(textNode);
    const buttonRect = button.getBoundingClientRect();
    const headingRect = heading.getBoundingClientRect();
    const articleRect = articleNode.getBoundingClientRect();
    const textRect = textRange.getBoundingClientRect();
    return {
      articleLeft: articleRect.left,
      buttonBottom: buttonRect.bottom,
      buttonHeight: buttonRect.height,
      buttonLeft: buttonRect.left,
      buttonRight: buttonRect.right,
      buttonTop: buttonRect.top,
      buttonWidth: buttonRect.width,
      firstLineBottom:
        headingRect.top +
        Number.parseFloat(getComputedStyle(heading).lineHeight),
      headingLeft: headingRect.left,
      headingTop: headingRect.top,
      textLeft: textRect.left,
    };
  });

  expect(geometry.buttonWidth).toBe(24);
  expect(geometry.buttonHeight).toBe(24);
  expect(geometry.buttonLeft).toBeGreaterThanOrEqual(
    geometry.articleLeft - 0.5,
  );
  expect(geometry.buttonRight).toBeLessThanOrEqual(geometry.headingLeft + 0.5);
  expect(geometry.buttonTop).toBeGreaterThanOrEqual(geometry.headingTop - 0.5);
  expect(geometry.buttonBottom).toBeLessThanOrEqual(
    geometry.firstLineBottom + 0.5,
  );
  expect(geometry.textLeft).toBeCloseTo(geometry.headingLeft, 1);
});

test('a pending hover never lands on content collapsed or rewritten under it', async ({ page }, testInfo) => {
  await openFoldingScenario(page, testInfo);
  const facts = await foldFacts(page);

  // Interleaving (a): pending hover -> programmatic collapse -> provider
  // completes. The toggle is programmatic so the pointer stays parked over
  // the fence; only layout_changed may save us, and it must.
  await moveToSourceText(page, 'beta_answer', 2);
  await page.waitForFunction(
    () => globalThis.__markdownFoldingControls.getHoverCalls().length >= 1,
    { timeout: 4_000 },
  );
  await page.evaluate(
    (offset) => globalThis.__markdownFoldingControls.toggleAtOffset(offset),
    facts.beta,
  );
  await expect.poll(() => visibleByText(page, 'beta_answer')).toBe(false);
  const collapseCall = await releaseLatestHover(page, 1, 'stale after collapse');
  expect(collapseCall.cancelled).toBe(true);
  await page.waitForTimeout(150);
  await expect(page.locator(hoverWidget)).toHaveAttribute(
    'data-markdown-hover-visible',
    'false',
  );
  await expect(page.locator(hoverWidget)).not.toContainText(
    'stale after collapse',
  );

  // Re-expand Beta for the second interleaving.
  await page.evaluate(
    (offset) => globalThis.__markdownFoldingControls.toggleAtOffset(offset),
    facts.beta,
  );
  await expect.poll(() => visibleByText(page, 'beta_answer')).toBe(true);

  // Interleaving (b): pending hover -> agent replace_source -> fold
  // reconciliation -> provider completes. The stale result must never reach
  // the widget; the rewritten Beta opens because its fingerprint changed.
  await page.mouse.move(5, 5);
  await moveToSourceText(page, 'beta_answer', 2);
  await page.waitForFunction(
    () => globalThis.__markdownFoldingControls.getHoverCalls().length >= 2,
    { timeout: 4_000 },
  );
  await page.evaluate(() =>
    globalThis.__markdownFoldingControls.replaceSource(),
  );
  await releaseLatestHover(page, 2, 'stale after replace');
  await page.waitForTimeout(150);
  await expect(page.locator(hoverWidget)).toHaveAttribute(
    'data-markdown-hover-visible',
    'false',
  );
  await expect(page.locator(hoverWidget)).not.toContainText(
    'stale after replace',
  );
  await expect.poll(() => visibleByText(page, 'rewritten')).toBe(true);
  // The rewrite touched only Beta, so Beta opened (fingerprint mismatch)
  // while the untouched Deep section carried its collapse across the
  // reprojection -- conservative reconciliation in both directions.
  const after = await foldFacts(page);
  expect(after.collapsed).toEqual([after.deep]);

  // Disposal retains no controls and throws nothing.
  await page.evaluate(() => globalThis.__markdownFoldingControls.dispose());
  await expect(page.locator(toggle)).toHaveCount(0);
});

const tocBar = `${root} > .moonbit-viewer-markdown-toc`;
const tocToggle = `${tocBar} .moonbit-viewer-markdown-toc-toggle`;
const tocRow = `${tocBar} .moonbit-viewer-markdown-toc-row`;

test('the pinned toc bar outlines sections and navigation expands the chain', async ({ page }, testInfo) => {
  await openFoldingScenario(page, testInfo);
  const facts = await foldFacts(page);

  // Rendered, collapsed to the summary row, and outside the article.
  await expect(page.locator(tocBar)).toHaveAttribute('data-toc-visible', 'true');
  await expect(page.locator(tocToggle)).toContainText('4 sections');
  await expect(page.locator(tocRow).first()).toBeHidden();
  const collapsedTocBox = await page.locator(tocBar).boundingBox();
  const titleBox = await page.locator(`${article} > h1`).boundingBox();
  expect(collapsedTocBox).not.toBeNull();
  expect(titleBox).not.toBeNull();
  expect(titleBox.y).toBeGreaterThanOrEqual(
    collapsedTocBox.y + collapsedTocBox.height - 1,
  );

  // Expanding shows one row per section, indented by structural depth.
  await page.locator(tocToggle).click();
  await expect(page.locator(tocToggle)).toHaveAttribute('aria-expanded', 'true');
  await expect(page.locator(tocRow)).toHaveCount(4);
  await expect(page.locator(tocRow).nth(3)).toHaveAttribute('data-toc-depth', '3');

  // The Deep section starts auto-collapsed; clicking its row expands it and
  // scrolls its heading into the viewport.
  expect(facts.collapsed).toEqual([facts.deep]);
  await page.locator(tocRow, { hasText: 'Deep' }).click();
  await expect.poll(() => visibleByText(page, 'deep three')).toBe(true);
  expect((await foldFacts(page)).collapsed).toEqual([]);
  const deepVisible = await page.locator(`${article} > *`, { hasText: 'deep one' })
    .first()
    .evaluate((node) => {
      const rect = node.getBoundingClientRect();
      const viewport = node.closest('.moonbit-viewer-markdown-document-viewport')
        .getBoundingClientRect();
      return rect.top >= viewport.top - 1 && rect.top <= viewport.bottom;
    });
  expect(deepVisible).toBe(true);

  // A revealed-by-navigation fence hovers, and the fold conversation still
  // never re-parsed the document.
  const generation = await projectionGeneration(page);
  await moveToSourceText(page, 'beta_answer', 2);
  await releaseLatestHover(page, 1, 'post-navigation hover');
  await expect(page.locator(hoverWidget)).toContainText('post-navigation hover');
  expect(await projectionGeneration(page)).toBe(generation);
});
