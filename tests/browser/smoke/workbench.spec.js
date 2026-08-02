import { expect, test } from '../support/test.js';

async function renderedWorkspaceLevel(page, prefix) {
  return page.locator('.workspace-sidebar [data-workspace-id]').evaluateAll(
    (rows, levelPrefix) =>
      rows
        .filter((row) => {
          const id = row.getAttribute('data-workspace-id') ?? '';
          if (!id.startsWith(levelPrefix)) return false;
          const relative = id.slice(levelPrefix.length);
          return relative.length > 0 && !relative.includes('/');
        })
        .map((row) => ({
          name: row.querySelector('.workspace-label')?.textContent?.trim() ?? '',
          kind: row.getAttribute('data-workspace-kind'),
        })),
    prefix,
  );
}

test('defaults to the dark theme and persists the toggled choice', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-theme', 'dark');

  await page.locator('[data-action="toggle-theme"]').click();
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-theme', 'light');

  await page.reload();
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-theme', 'light');

  await page.locator('[data-action="toggle-theme"]').click();
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-theme', 'dark');
});

test('toggles the explorer without giving up its editor space', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');

  const toggle = page.locator('[data-action="toggle-explorer"]');
  const explorer = page.locator('#workspace-explorer');
  const viewerHost = page.locator('.viewer-host');
  const initialWidth = await viewerHost.evaluate((element) =>
    element.getBoundingClientRect().width,
  );

  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  await expect(toggle).toHaveAttribute('aria-label', 'Show Explorer');
  await expect(explorer).toBeHidden();
  await expect(page.locator('.editor-shell')).toHaveAttribute(
    'data-explorer-visible',
    'false',
  );
  const hiddenWidth = await viewerHost.evaluate((element) =>
    element.getBoundingClientRect().width,
  );
  expect(hiddenWidth).toBeGreaterThan(initialWidth + 150);

  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  await expect(toggle).toHaveAttribute('aria-label', 'Hide Explorer');
  await expect(explorer).toBeVisible();
});

test('keeps the explorer compact and lets its desktop width resize', async ({
  page,
}) => {
  await page.goto('/');
  await expect(page.locator('.editor-shell')).toHaveAttribute(
    'data-status',
    'ready',
  );

  const explorer = page.locator('#workspace-explorer');
  const viewerHost = page.locator('.viewer-host');
  const title = explorer.locator('.workspace-title');
  const rows = explorer.locator('.workspace-item');
  await expect(explorer).toHaveCSS('resize', 'horizontal');
  await expect(explorer).toHaveCSS('width', '280px');
  await expect(title).toHaveCSS('height', '30px');
  await expect(rows.first()).toHaveCSS('height', '20px');

  const before = await page.locator('.editor-main').evaluate((main) => {
    const sidebar = main.querySelector('#workspace-explorer')
      .getBoundingClientRect();
    const viewer = main.querySelector('.viewer-host').getBoundingClientRect();
    return { sidebarWidth: sidebar.width, viewerLeft: viewer.left };
  });
  await explorer.evaluate((element) => {
    element.style.width = '340px';
  });
  const after = await page.locator('.editor-main').evaluate((main) => {
    const sidebar = main.querySelector('#workspace-explorer')
      .getBoundingClientRect();
    const viewer = main.querySelector('.viewer-host').getBoundingClientRect();
    return {
      sidebarRight: sidebar.right,
      sidebarWidth: sidebar.width,
      viewerLeft: viewer.left,
    };
  });
  expect(after.sidebarWidth).toBe(340);
  expect(after.viewerLeft - before.viewerLeft).toBeCloseTo(60, 1);
  expect(after.viewerLeft).toBeCloseTo(after.sidebarRight, 1);

  await explorer.evaluate((element) => {
    element.style.width = '';
  });
  await page.setViewportSize({ width: 640, height: 700 });
  await expect(explorer).toHaveCSS('width', '148px');
  await expect(explorer).toHaveCSS('resize', 'none');
  await expect(viewerHost).toBeVisible();
});

test('renders explorer rows with twisties and file icons', async ({ page }) => {
  await page.goto('/');

  // src/main.mbt becomes visible once auto-reveal expands src.
  await expect(
    page.locator(
      '[data-workspace-id="readonly-remote://workspace/src"] .workspace-twistie svg',
    ),
  ).toBeVisible();
  await expect(
    page.locator(
      '[data-workspace-id="readonly-remote://workspace/src/main.mbt"] .workspace-file-icon svg',
    ),
  ).toBeVisible();
});

test('orders rendered explorer names lexicographically within policy groups', async ({
  page,
}) => {
  await page.goto('/');
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready');

  const root = await renderedWorkspaceLevel(page, 'readonly-remote://workspace/');
  expect(root[0]).toEqual({ name: 'README.md', kind: 'file' });
  const rootDirectories = root.filter((entry) => entry.kind === 'folder');
  const rootFiles = root.slice(1).filter((entry) => entry.kind === 'file');
  expect(root.slice(1)).toEqual([...rootDirectories, ...rootFiles]);
  expect(rootDirectories.map((entry) => entry.name)).toEqual(
    rootDirectories.map((entry) => entry.name).sort(),
  );
  expect(rootFiles.map((entry) => entry.name)).toEqual(
    rootFiles.map((entry) => entry.name).sort(),
  );

  // This level distinguishes lexical order from String::compare shortlex:
  // `main.mbt` is shorter than `errors.mbt`, but must render after it.
  const src = await renderedWorkspaceLevel(
    page,
    'readonly-remote://workspace/src/',
  );
  expect(src[0]).toEqual({ name: 'moon.pkg', kind: 'file' });
  expect(src.slice(1).map((entry) => entry.name)).toEqual(
    src
      .slice(1)
      .map((entry) => entry.name)
      .sort(),
  );
});
