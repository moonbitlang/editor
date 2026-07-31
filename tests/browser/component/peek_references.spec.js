import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

const codeEditor =
  '.peek-references-code-host > .monaco-editor.readonly-editor';
const codePeek = `${codeEditor} .moonbit-viewer-references-peek`;
const codePreview =
  `${codePeek} .moonbit-viewer-references-peek-preview > ` +
  '.monaco-editor.readonly-editor';
const resultTree = '.moonbit-viewer-reference-results-tree';
const groupRow = '[data-reference-row-kind="group"]';
const referenceRow = '[data-reference-row-kind="reference"]';
const markdownEditor =
  '.peek-references-markdown-host > .moonbit-viewer-markdown-document';
const markdownPeek =
  `${markdownEditor} > .moonbit-viewer-markdown-document-overlays > ` +
  '.moonbit-viewer-references-peek-overlay';
const markdownPreview =
  `${markdownPeek} .moonbit-viewer-references-peek-preview > ` +
  '.moonbit-viewer-markdown-document';
const definitionEditor =
  '.definition-host > .monaco-editor.readonly-editor';
const definitionPeek =
  `${definitionEditor} .moonbit-viewer-references-peek`;

async function settle(page) {
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      ),
  );
}

async function mountPeekReferencesFixture(page, testInfo) {
  const reporter = await installMoonBitReporter(page);
  await page.goto('/browser-tests/peek_references.html');
  await page.waitForFunction(() =>
    Boolean(globalThis.__peekReferencesControls),
  );
  const report = await reporter.waitForReport(testInfo, {
    suite: 'peek_references',
    timeout: 10_000,
  });
  expectMoonBitReportPassed(report, { suite: 'peek_references' });
  await expect(page.locator(codeEditor)).toContainText('anchor here');
  await expect(page.locator(markdownEditor)).toContainText('References');
  await settle(page);
  return reporter;
}

async function mountDefinitionFixture(page, testInfo) {
  const reporter = await installMoonBitReporter(page);
  await page.goto('/browser-tests/definition.html');
  await page.waitForFunction(() => Boolean(globalThis.__definitionControls));
  const report = await reporter.waitForReport(testInfo, {
    suite: 'definition',
    timeout: 10_000,
    attachmentName: 'definition-moonbit-browser-report',
  });
  expectMoonBitReportPassed(report, { suite: 'definition' });
  await expect(page.locator(definitionEditor)).toContainText(
    'definition_alpha',
  );
  await settle(page);
  return reporter;
}

async function control(page, method) {
  await page.evaluate(
    (name) => globalThis.__peekReferencesControls[name](),
    method,
  );
}

async function state(page) {
  return page.evaluate(() => globalThis.__peekReferencesControls.state());
}

function treeIn(page, peekSelector = codePeek) {
  return page.locator(peekSelector).locator(resultTree);
}

function group(tree, index) {
  return tree.locator(
    `${groupRow}[data-reference-group-index="${index}"]`,
  );
}

function reference(tree, flatIndex) {
  return tree.locator(
    `${referenceRow}[data-reference-flat-index="${flatIndex}"]`,
  );
}

test('public locations render an accessible lazy tree, snippets, and decorated previews', async ({
  page,
}, testInfo) => {
  const reporter = await mountPeekReferencesFixture(page, testInfo);
  try {
    await control(page, 'show_code');

    const dialog = page.locator(codePeek);
    const tree = treeIn(page);
    await expect(dialog).toHaveAttribute('role', 'dialog');
    await expect(dialog).toHaveAttribute('aria-label', 'Peek References');
    await expect(tree).toHaveAttribute('role', 'tree');
    await expect(tree).toHaveAttribute(
      'aria-label',
      'Found 6 results in 3 files',
    );
    await expect(dialog.locator(groupRow)).toHaveCount(3);

    const remoteGroup = group(tree, 0);
    const sourceGroup = group(tree, 1);
    const otherGroup = group(tree, 2);
    await expect(remoteGroup).toHaveAttribute('aria-expanded', 'false');
    await expect(remoteGroup).toHaveAttribute(
      'aria-label',
      '2 results in remote.mbt, full path /workspace/lib',
    );
    await expect(sourceGroup).toHaveAttribute('aria-expanded', 'true');
    await expect(sourceGroup).toContainText('source.mbt');
    await expect(sourceGroup).toContainText('/workspace/src');
    await expect(sourceGroup).toContainText('3');
    await expect(otherGroup).toHaveAttribute('aria-expanded', 'false');

    const initial = reference(tree, 4);
    await expect(initial).toHaveAttribute('aria-selected', 'true');
    await expect(initial).toHaveAttribute('tabindex', '0');
    await expect(initial).toHaveAttribute(
      'aria-label',
      'target again in source.mbt on line 3 at column 1',
    );
    await expect(
      initial.locator('.moonbit-viewer-reference-results-snippet-match'),
    ).toHaveText('target');
    await expect(page.locator(codePreview)).toContainText('target again');
    await expect
      .poll(async () => (await state(page)).resolverCalls)
      .toBe(0);

    await expect(
      page.locator(
        `${codePreview} ` +
          '.moonbit-viewer-references-peek-reference-match-selected',
      ),
    ).toHaveCount(1);
    await expect(
      page.locator(
        `${codePreview} ` +
          '.moonbit-viewer-references-peek-reference-match',
      ),
    ).toHaveCount(3);

    await remoteGroup.click();
    await expect(remoteGroup).toHaveAttribute('aria-expanded', 'true');
    await expect
      .poll(async () => (await state(page)).resolverCalls)
      .toBe(1);
    const firstRemote = reference(tree, 0);
    await expect(
      firstRemote.locator(
        '.moonbit-viewer-reference-results-snippet-match',
      ),
    ).toHaveText('target');
    await expect(firstRemote).toHaveAttribute(
      'aria-label',
      'remote target value in remote.mbt on line 1 at column 8',
    );

    await remoteGroup.click();
    await expect(remoteGroup).toHaveAttribute('aria-expanded', 'false');
    await remoteGroup.click();
    await expect(remoteGroup).toHaveAttribute('aria-expanded', 'true');
    expect((await state(page)).resolverCalls).toBe(1);

    await firstRemote.click();
    await expect(firstRemote).toHaveAttribute('aria-selected', 'true');
    await expect
      .poll(async () => (await state(page)).resolverCalls)
      .toBe(2);
    await expect(page.locator(codePreview)).toContainText(
      'remote target value',
    );
    await expect(
      page.locator(
        `${codePreview} ` +
          '.moonbit-viewer-references-peek-reference-match-selected',
      ),
    ).toHaveCount(1);
    await expect(
      page.locator(
        `${codePreview} ` +
          '.moonbit-viewer-references-peek-reference-match',
      ),
    ).toHaveCount(2);

    await page.keyboard.press('Escape');
    await expect(dialog).toHaveCount(0);
    await expect
      .poll(async () => (await state(page)).resolverReleases)
      .toBe(2);
    await expect
      .poll(async () => (await state(page)).codeHasTextFocus)
      .toBe(true);
  } finally {
    reporter.dispose();
  }
});

test('F4 and Shift+F4 cycle across resources while preview focus stays inside Peek', async ({
  page,
}, testInfo) => {
  const reporter = await mountPeekReferencesFixture(page, testInfo);
  try {
    await control(page, 'show_code');
    const tree = treeIn(page);
    await expect(page.locator(codePreview)).toContainText('target again');
    await page.locator(codePreview).focus();

    await page.keyboard.press('F4');
    await expect(reference(tree, 5)).toHaveAttribute(
      'aria-selected',
      'true',
    );
    await expect(page.locator(codePreview)).toContainText('third target');
    await expect
      .poll(() =>
        page.evaluate(
          (selector) =>
            document.querySelector(selector)?.contains(
              document.activeElement,
            ) ?? false,
          codePreview,
        ),
      )
      .toBe(true);

    await page.keyboard.press('Shift+F4');
    await expect(reference(tree, 4)).toHaveAttribute(
      'aria-selected',
      'true',
    );
    await expect(page.locator(codePreview)).toContainText('target again');
    await expect
      .poll(() =>
        page.evaluate(
          (selector) =>
            document.querySelector(selector)?.contains(
              document.activeElement,
            ) ?? false,
          codePreview,
        ),
      )
      .toBe(true);

    await page.keyboard.press('Escape');
    await expect(page.locator(codePeek)).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});

test('Enter uses Current and Ctrl+Enter uses Side before closing Peek', async ({
  page,
}, testInfo) => {
  const reporter = await mountPeekReferencesFixture(page, testInfo);
  try {
    await control(page, 'clear_opens');
    await control(page, 'show_code');
    const tree = treeIn(page);
    await group(tree, 0).click();
    const firstRemote = reference(tree, 0);
    await firstRemote.click();
    await expect(page.locator(codePreview)).toContainText(
      'remote target value',
    );
    await page.keyboard.press('Enter');
    await expect(page.locator(codePeek)).toHaveCount(0);
    await expect
      .poll(async () => (await state(page)).openModes)
      .toEqual(['Current']);
    expect((await state(page)).openUris[0]).toContain(
      '/workspace/lib/remote.mbt',
    );
    expect((await state(page)).openLines).toEqual([1]);
    expect((await state(page)).openColumns).toEqual([8]);

    await control(page, 'clear_opens');
    await control(page, 'show_code');
    const selected = reference(treeIn(page), 4);
    await expect(selected).toHaveAttribute('aria-selected', 'true');
    await selected.press('Control+Enter');
    await expect(page.locator(codePeek)).toHaveCount(0);
    await expect
      .poll(async () => (await state(page)).openModes)
      .toEqual(['Side']);
    expect((await state(page)).openUris[0]).toContain(
      '/workspace/src/source.mbt',
    );
    expect((await state(page)).openLines).toEqual([3]);
    expect((await state(page)).openColumns).toEqual([1]);

    await control(page, 'clear_opens');
    await control(page, 'show_code');
    await expect(reference(treeIn(page), 4)).toHaveAttribute(
      'aria-selected',
      'true',
    );
    await reference(treeIn(page), 4).press('Enter');
    await expect(page.locator(codePeek)).toHaveCount(0);
    await expect
      .poll(async () => (await state(page)).codePosition)
      .toEqual({ line: 3, column: 1 });
    expect((await state(page)).openModes).toEqual([]);
  } finally {
    reporter.dispose();
  }
});

test('same anchor toggles, a new anchor replaces, and empty references stay accessible', async ({
  page,
}, testInfo) => {
  const reporter = await mountPeekReferencesFixture(page, testInfo);
  try {
    await control(page, 'show_code');
    await expect(page.locator(codePeek)).toHaveCount(1);
    await control(page, 'show_code');
    await expect(page.locator(codePeek)).toHaveCount(0);

    await control(page, 'show_code');
    await control(page, 'show_code_other_anchor');
    await expect(page.locator(codePeek)).toHaveCount(1);
    await expect
      .poll(() =>
        page.evaluate(
          (selector) =>
            document.querySelector(selector)?.contains(
              document.activeElement,
            ) ?? false,
          codePeek,
        ),
      )
      .toBe(true);
    await page.keyboard.press('Escape');
    await expect(page.locator(codePeek)).toHaveCount(0);

    await control(page, 'show_code_empty');
    const dialog = page.locator(codePeek);
    await expect(dialog).toHaveCount(1);
    await expect(
      dialog.locator('.moonbit-viewer-references-peek-empty'),
    ).toHaveText('No references found');
    await expect(dialog.locator(resultTree)).toBeHidden();
    await control(page, 'show_code_empty');
    await expect(dialog).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});

test('Markdown mounts a bounded overlay with a flattened reference tree', async ({
  page,
}, testInfo) => {
  const reporter = await mountPeekReferencesFixture(page, testInfo);
  try {
    await control(page, 'focus_markdown');
    await control(page, 'show_markdown');
    const dialog = page.locator(markdownPeek);
    const tree = treeIn(page, markdownPeek);
    await expect(dialog).toHaveAttribute('aria-label', 'Peek References');
    await expect(dialog.locator(groupRow)).toHaveCount(0);
    await expect(dialog.locator(referenceRow)).toHaveCount(2);
    await expect(
      reference(tree, 1).locator(
        '.moonbit-viewer-reference-results-snippet-match',
      ),
    ).toHaveText('target');
    await expect(page.locator(markdownPreview)).toContainText('References');

    await page.locator('.peek-references-markdown-host').evaluate((host) => {
      host.style.width = '640px';
    });
    await settle(page);
    const geometry = await dialog.evaluate((root) => {
      const editor = root.closest('.moonbit-viewer-markdown-document');
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
    await expect(dialog).toHaveCount(0);
    await expect
      .poll(async () => (await state(page)).markdownHasTextFocus)
      .toBe(true);
  } finally {
    reporter.dispose();
  }
});

test('Definition still opens through the shared Peek dialog and result tree', async ({
  page,
}, testInfo) => {
  const reporter = await mountDefinitionFixture(page, testInfo);
  try {
    await page.evaluate(() => {
      globalThis.__definitionControls.select_reference();
      globalThis.__definitionControls.focus_outer();
    });
    await page.keyboard.press('Alt+F12');
    const dialog = page.locator(definitionPeek);
    await expect(dialog).toHaveAttribute('aria-label', 'Peek Definition');
    await expect(dialog.locator(resultTree)).toHaveAttribute('role', 'tree');
    await expect(dialog.locator(referenceRow)).toHaveCount(1);
    await expect(
      dialog.locator('.moonbit-viewer-references-peek-title-filename'),
    ).toHaveText('Definitions');
    await expect(
      dialog.locator('.moonbit-viewer-references-peek-preview'),
    ).toContainText('definition_alpha');

    await page.keyboard.press('Escape');
    await expect(dialog).toHaveCount(0);
  } finally {
    reporter.dispose();
  }
});
