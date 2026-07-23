import { promises as fs } from 'node:fs';
import { expect, test } from '../support/test.js';
import {
  collectReadonlyEvents,
  openMainFixture,
  openWorkspaceFile,
  workspaceItem,
} from '../support/app.js';

const mainFixture = 'tests/fixtures/workspace/src/main.mbt';

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
  await expect(page.locator('.monaco-editor.readonly-editor')).toContainText('startup_event');
  await expect(page.locator('.editor-shell')).not.toContainText('readonly provider');

  const mainSymbol = page.locator('.view-line span', { hasText: 'main' }).first();
  await mainSymbol.hover();
  await mainSymbol.dblclick();

  expect(await events.some('moonbit:render')).toBeTruthy();
  expect(await events.some('dom:mounted')).toBeTruthy();
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
  await expect(markdown.locator('h1')).toHaveText('Fixture entry point');
  await expect(markdown.locator('strong')).toHaveText('native shell');
  await expect(markdown).not.toContainText('|');
  await expect(page.locator('.view-lines')).not.toContainText('Fixture entry point');
  expect(await page.evaluate(() => globalThis.__readonlyEditorSource)).toContain(
    '///|\n/// # Fixture entry point',
  );
});

test('shows hover through pointer interaction', async ({ page }) => {
  await page.goto('/');
  await openMainFixture(page);

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
    await expect(page.locator('.mtk5')).toContainText('"restored from disk"', {
      timeout: 7_000,
    });
  } finally {
    await fs.writeFile(mainFixture, original, 'utf8');
  }
});
