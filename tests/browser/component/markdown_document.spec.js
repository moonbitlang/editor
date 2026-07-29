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
    expect(report.metrics.codeBlocks).toBe(1);
    expect(report.metrics.keywordTokens).toBeGreaterThan(0);
    expect(report.metrics.sourceUri).toBe(
      'inmemory://component/literate.mbt.md',
    );

    await expect(page.locator(root)).toHaveCount(1);
    await expect(page.locator(`${host} > .monaco-editor`)).toHaveCount(0);
    await expect(page.locator(article)).toContainText(
      'Readonly Markdown document',
    );
    await expect(
      page.locator(`${article} [data-markdown-code-block="0"]`),
    ).toHaveAttribute('data-markdown-semantic', 'moonbit-check');
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
    await expect(page.locator(article)).toContainText('replacement_answer');
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

    await page.evaluate(() =>
      globalThis.__markdownDocumentControls.updateTheme(
        'markdown-component-theme',
      ),
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

    await page.evaluate(() => globalThis.__markdownDocumentControls.dispose());
    await expect(page.locator(root)).toHaveCount(0);
    await expect(page.locator(`${host} > .monaco-editor`)).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});
