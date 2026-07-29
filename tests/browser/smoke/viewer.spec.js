import { promises as fs } from 'node:fs';
import { expect, test } from '../support/test.js';
import {
  collectReadonlyEvents,
  openMainFixture,
  openWorkspaceFile,
  waitForReady,
  workspaceItem,
} from '../support/app.js';

const mainFixture = 'tests/fixtures/workspace/src/main.mbt';

async function waitForSourceText(page, needle) {
  await expect
    .poll(
      () =>
        page.evaluate(
          (text) => globalThis.__readonlyEditorSource?.includes(text) ?? false,
          needle,
        ),
      { timeout: 7_000 },
    )
    .toBeTruthy();
}

async function unfoldMainBody(page) {
  const collapsed = page.locator(
    '.margin-view-overlays .cldr.codicon-folding-collapsed',
  );
  await expect(collapsed).toHaveCount(1, { timeout: 7_000 });
  await collapsed.click({ force: true });
}

test('starts from native-served static assets', async ({ page }) => {
  const requestedPaths = [];
  page.on('request', (request) => {
    requestedPaths.push(new URL(request.url()).pathname);
  });

  await page.goto('/');
  await expect(page.locator('.editor-shell')).toBeVisible();

  expect(requestedPaths).toContain('/style.css');
  expect(requestedPaths).toContain('/editor.mjs');
  expect(requestedPaths.some((path) => path.endsWith('/src/bootstrap.js'))).toBeFalsy();
  expect(requestedPaths.some((path) => path.includes('/web/generated/'))).toBeFalsy();
  expect(requestedPaths.some((path) => path.includes('/@vite/'))).toBeFalsy();
});

test('renders fixture workspace through the native protocol', async ({ page }) => {
  const events = collectReadonlyEvents(page);

  await page.goto('/');
  await openMainFixture(page);

  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');
  await expect(page.locator('.editor-shell')).toHaveAttribute(
    'data-source-uri',
    'readonly-remote://workspace/src/main.mbt',
  );
  await expect(page.locator('.monaco-editor.readonly-editor')).toContainText('fn main');
  await expect(page.locator('.monaco-editor.readonly-editor')).not.toContainText(
    'startup_event',
  );
  await expect(
    page.locator('.margin-view-overlays .cldr.codicon-folding-collapsed'),
  ).toHaveCount(1);
  await expect(page.locator('.editor-shell')).not.toContainText('readonly provider');

  const mainSymbol = page.locator('.view-line span', { hasText: 'main' }).first();
  await mainSymbol.hover();
  await mainSymbol.dblclick();

  expect(await events.some('moonbit:render')).toBeTruthy();
  expect(await events.some('dom:mounted')).toBeTruthy();
});

test('opens MoonBit models as a top-level outline without enforcing later folds', async ({
  page,
}) => {
  await page.goto('/');
  await openWorkspaceFile(page, 'src/events.mbt');

  const editor = page.locator('.monaco-editor.readonly-editor');
  const collapsed = page.locator(
    '.margin-view-overlays .cldr.codicon-folding-collapsed',
  );
  await expect(editor).toContainText('pub struct StartupEvent');
  await expect(editor).toContainText('pub fn startup_event');
  await expect(editor).not.toContainText('message : String');
  await expect(editor).not.toContainText('readonly fixture ready');
  await expect(collapsed).toHaveCount(2);

  const functionLine = editor.locator('.view-line', {
    hasText: 'pub fn startup_event',
  });
  await expect(functionLine.locator('.inline-folded')).toHaveCount(0);
  expect((await functionLine.innerText()).replaceAll('\u00a0', ' ').trim()).toBe(
    'pub fn startup_event() -> StartupEvent {',
  );
  // The struct remains an ordinary fold with Monaco's trailing ellipsis.
  await expect(editor.locator('.inline-folded')).toHaveCount(1);

  // The policy is initial, not enforced: an ordinary chevron click leaves the
  // selected top-level declaration expanded for the rest of this model.
  await collapsed.first().click({ force: true });
  await expect(editor).toContainText('message : String');
  await expect(collapsed).toHaveCount(1);

  await collapsed.first().click({ force: true });
  await expect(editor).toContainText('readonly fixture ready');
  await expect(collapsed).toHaveCount(0);
});

test('renders MoonBit documentation comments through the real workbench', async ({
  page,
}) => {
  await page.goto('/');
  await openMainFixture(page);

  const markdown = page.locator(
    '.moonbit-viewer-markdown-comment[data-start-line="1"][data-end-line="5"]',
  );
  await expect(markdown).toBeVisible();
  await expect(markdown).toHaveAttribute('data-documentation-foldable', 'true');
  await expect(markdown).toHaveAttribute('data-documentation-expanded', 'false');
  const preview = markdown.locator('.moonbit-viewer-markdown-comment-preview');
  const full = markdown.locator('.moonbit-viewer-markdown-comment-full');
  const toggle = markdown.getByRole('button', {
    name: 'Expand API documentation',
  });
  await expect(preview).toBeVisible();
  await expect(preview.locator('hr + h1')).toHaveText('Fixture entry point');
  await expect(preview).not.toContainText('native shell');
  await expect(full).toBeHidden();
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  const collapsedBox = await markdown.boundingBox();
  const toggleBox = await toggle.boundingBox();
  expect(collapsedBox).not.toBeNull();
  expect(toggleBox).not.toBeNull();
  expect(toggleBox.y + toggleBox.height).toBeLessThanOrEqual(
    collapsedBox.y + collapsedBox.height + 1,
  );

  await toggle.click();
  await expect(markdown).toHaveAttribute('data-documentation-expanded', 'true');
  await expect(preview).toBeHidden();
  await expect(full).toBeVisible();
  await expect(full.locator('strong')).toHaveText('native shell');
  await expect
    .poll(async () => (await markdown.boundingBox())?.height ?? 0)
    .toBeGreaterThan(collapsedBox?.height ?? 0);
  const expandedHeight = (await markdown.boundingBox())?.height ?? 0;

  const collapse = markdown.getByRole('button', {
    name: 'Collapse API documentation',
  });
  await collapse.focus();
  await collapse.press('Enter');
  await expect(markdown).toHaveAttribute('data-documentation-expanded', 'false');
  await expect(preview).toBeVisible();
  await expect(full).toBeHidden();
  await expect
    .poll(async () => (await markdown.boundingBox())?.height ?? 0)
    .toBeLessThan(expandedHeight);
  await expect(markdown).not.toContainText('|');

  // The gutter chevron shares the code-folding column: same codicon family,
  // horizontally centered on the collapsed `fn main` chevron, and it drives
  // the same fold state with the mouse.
  const gutterToggle = page.locator(
    '.moonbit-viewer-markdown-comment-margin-toggle',
  );
  await expect(gutterToggle).toHaveClass(/codicon-folding-collapsed/);
  const codeChevron = page.locator(
    '.margin-view-overlays .cldr.codicon-folding-collapsed',
  );
  const gutterBox = await gutterToggle.boundingBox();
  const codeBox = await codeChevron.boundingBox();
  expect(gutterBox).not.toBeNull();
  expect(codeBox).not.toBeNull();
  expect(
    Math.abs(gutterBox.x + gutterBox.width / 2 - (codeBox.x + codeBox.width / 2)),
  ).toBeLessThanOrEqual(1);

  await gutterToggle.click();
  await expect(markdown).toHaveAttribute('data-documentation-expanded', 'true');
  await expect(gutterToggle).toHaveClass(/codicon-folding-expanded/);
  await gutterToggle.click();
  await expect(markdown).toHaveAttribute('data-documentation-expanded', 'false');
  await expect(gutterToggle).toHaveClass(/codicon-folding-collapsed/);
  await expect(page.locator('.view-lines')).not.toContainText('Fixture entry point');
  expect(await page.evaluate(() => globalThis.__readonlyEditorSource)).toContain(
    '///|\n/// # Fixture entry point',
  );
});

test('renders Markdown files as a whole-document reading surface', async ({
  page,
}) => {
  await page.goto('/');
  await openWorkspaceFile(page, 'README.md');

  const markdown = page.locator(
    '.moonbit-viewer-markdown-comment[data-markdown-document="true"]',
  );
  await expect(markdown).toBeVisible();
  await expect(markdown.locator('h1')).toHaveText('Fixture Workspace');
  await expect(markdown.locator('strong')).toHaveText('whole document');
  // Diago renders synchronously without network access; the Mermaid fence
  // keeps its queued wrapper even when the pinned CDN is unreachable.
  await expect(
    markdown.locator('[data-diagram-language="diago"] svg').first(),
  ).toBeVisible();
  await expect(
    markdown.locator('[data-diagram-language="mermaid"]'),
  ).toHaveCount(1);
  await expect(
    markdown.locator('.monaco-tokenized-source', { hasText: 'readme_snippet' }),
  ).toBeVisible();
  // A whole document reads at full width and exposes no fold control.
  await expect(markdown).toHaveAttribute('data-documentation-foldable', 'false');
  await expect(
    markdown.locator('.moonbit-viewer-markdown-comment-toggle'),
  ).toBeHidden();
  // The replaced source stays hidden while the model remains truthful.
  await expect(page.locator('.view-lines')).not.toContainText('# Fixture Workspace');
  expect(await page.evaluate(() => globalThis.__readonlyEditorSource)).toContain(
    '# Fixture Workspace',
  );
});

test('renders undocumented MoonBit item anchors as horizontal separators', async ({
  page,
}) => {
  await page.goto('/');
  await openWorkspaceFile(page, 'src/events.mbt');

  const first = page.locator(
    '.moonbit-viewer-markdown-comment[data-start-line="1"][data-end-line="2"]',
  );
  const second = page.locator(
    '.moonbit-viewer-markdown-comment[data-start-line="6"][data-end-line="7"]',
  );
  await expect(first.locator('hr')).toBeVisible();
  await expect(second.locator('hr')).toBeVisible();
  await expect(first).toHaveAttribute('data-documentation-foldable', 'false');
  await expect(second).toHaveAttribute('data-documentation-foldable', 'false');
  await expect(first.locator('.moonbit-viewer-markdown-comment-toggle')).toBeHidden();
  await expect(second.locator('.moonbit-viewer-markdown-comment-toggle')).toBeHidden();
  const marginToggles = page.locator(
    '.moonbit-viewer-markdown-comment-margin-toggle',
  );
  await expect(marginToggles).toHaveCount(2);
  await expect(marginToggles.nth(0)).toBeHidden();
  await expect(marginToggles.nth(1)).toBeHidden();
  const firstBox = await first.boundingBox();
  const firstCodeLineBox = await page
    .locator('.view-line[data-line="2"]')
    .boundingBox();
  expect(firstBox?.height).toBe(firstCodeLineBox?.height);
  await expect(page.locator('.view-lines')).not.toContainText('///|');
  expect(await page.evaluate(() => globalThis.__readonlyEditorSource)).toContain(
    '///|\npub struct StartupEvent',
  );
});

test('shows hover through pointer interaction', async ({ page }) => {
  await page.goto('/');
  await waitForReady(page);
  await expect(page.locator('.editor-shell')).toHaveAttribute(
    'data-source-uri',
    'readonly-remote://workspace/src/main.mbt',
  );
  await unfoldMainBody(page);

  const symbol = page.locator('.view-line span', { hasText: 'startup_event' }).first();
  await expect(symbol).toBeVisible();
  await expect(async () => {
    await symbol.hover();
    const hover = page.locator('[data-content-widget="editor.contrib.resizableContentHoverWidget"] .monaco-hover');
    await expect(hover).toBeVisible({ timeout: 3_000 });
    await expect
      .poll(() => hover.textContent().then((text) => text.trim().length), {
        timeout: 3_000,
      })
      .toBeGreaterThan(0);
  }).toPass({ timeout: 60_000 });
});

test('lazily expands explorer folders and auto-reveals the active file', async ({ page }) => {
  await page.goto('/');
  const initialHref = await page.evaluate(() => window.location.href);

  // Startup auto-opens the first MoonBit file; auto-reveal expands its
  // ancestor chain and selects its row.
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');
  await expect(page.locator(workspaceItem('moon.mod'))).toHaveAttribute(
    'data-workspace-kind',
    'file',
  );
  await expect(page.locator(workspaceItem('src'))).toHaveAttribute('aria-expanded', 'true');
  await expect(page.locator(workspaceItem('src/main.mbt'))).toHaveAttribute(
    'aria-selected',
    'true',
  );
  await expect(page.locator(workspaceItem('src/errors.mbt'))).toHaveAttribute(
    'data-workspace-kind',
    'file',
  );

  // Collapsing hides children without forgetting the resolved level.
  await page.locator(workspaceItem('src')).click();
  await expect(page.locator(workspaceItem('src'))).toHaveAttribute('aria-expanded', 'false');
  await expect(page.locator(workspaceItem('src/main.mbt'))).toHaveCount(0);

  await page.locator(workspaceItem('src')).click();
  await page.locator(workspaceItem('src/events.mbt')).click();
  await expect(page.locator(workspaceItem('src/events.mbt'))).toHaveAttribute(
    'aria-selected',
    'true',
  );
  await expect(page.locator(workspaceItem('src/main.mbt'))).toHaveAttribute(
    'aria-selected',
    'false',
  );
  expect(await page.evaluate(() => window.location.href)).toBe(initialHref);
});

test('highlights MoonBit sources through the registered language tokenizer', async ({ page }) => {
  await page.goto('/');
  await openWorkspaceFile(page, 'src/errors.mbt');

  // The type color (mtk9) only comes from the MoonBit lexer (capitalized
  // identifier); the plain fallback never emits it.
  await expect(page.locator('.mtk9', { hasText: 'FixtureError' }).first()).toBeVisible();
  await expect(page.locator('.mtk3', { hasText: 'suberror' }).first()).toBeVisible();
});

test('renders unregistered languages with default/plain spans', async ({ page }) => {
  await page.goto('/');
  await openWorkspaceFile(page, 'notes.txt');

  await expect(page.locator('.monaco-editor.readonly-editor')).toContainText('Fixture notes');
  await expect(page.locator('.mtk1', { hasText: 'value' }).first()).toBeVisible();
  // Registry misses intentionally do not run the generic fallback lexer; the
  // line renderer fills the content with default-foreground (mtk1) spans, never
  // the variable/type/punctuation colors.
  await expect(page.locator('.view-line span.mtk4')).toHaveCount(0);
  await expect(page.locator('.view-line span.mtk9')).toHaveCount(0);
  await expect(page.locator('.view-line span.mtk8')).toHaveCount(0);
});

test('updates and recovers watched fixture files from disk changes', async ({ page }) => {
  const original = await fs.readFile(mainFixture, 'utf8');

  try {
    await page.goto('/');
    await openMainFixture(page);
    await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');

    await fs.writeFile(
      mainFixture,
      original.replace('println(event.message)', 'println("synced from disk")'),
      'utf8',
    );
    await waitForSourceText(page, 'println("synced from disk")');
    await unfoldMainBody(page);
    await expect(page.locator('.mtk5')).toContainText('"synced from disk"', {
      timeout: 7_000,
    });

    await fs.rm(mainFixture);
    await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'missing', {
      timeout: 7_000,
    });
    await expect(page.locator('.source-message')).toContainText('Source file is missing.');

    await fs.writeFile(
      mainFixture,
      original.replace('println(event.message)', 'println("restored from disk")'),
      'utf8',
    );
    await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready', {
      timeout: 7_000,
    });
    await waitForSourceText(page, 'println("restored from disk")');
    await unfoldMainBody(page);
    await expect(page.locator('.mtk5')).toContainText('"restored from disk"', {
      timeout: 7_000,
    });
  } finally {
    await fs.writeFile(mainFixture, original, 'utf8');
  }
});

test('keeps one tab watch active after another tab disconnects', async ({
  context,
  page,
}) => {
  const original = await fs.readFile(mainFixture, 'utf8');
  const remainingPage = await context.newPage();

  try {
    await Promise.all([page.goto('/'), remainingPage.goto('/')]);
    await Promise.all([openMainFixture(page), openMainFixture(remainingPage)]);
    await page.close();

    await fs.writeFile(
      mainFixture,
      original.replace(
        'println(event.message)',
        'println("remaining tab still watched")',
      ),
      'utf8',
    );
    await waitForSourceText(
      remainingPage,
      'println("remaining tab still watched")',
    );
    await unfoldMainBody(remainingPage);
    await expect(remainingPage.locator('.mtk5')).toContainText(
      '"remaining tab still watched"',
      { timeout: 7_000 },
    );
  } finally {
    await fs.writeFile(mainFixture, original, 'utf8');
  }
});
