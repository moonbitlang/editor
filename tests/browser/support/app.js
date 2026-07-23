import { expect } from './test.js';

const defaultWorkspaceRoot = 'readonly-remote://workspace';

export async function gotoApp(page, path = '/') {
  await page.goto(path);
  await waitForReady(page);
}

export async function waitForReady(page, options = {}) {
  await expect(page.locator('.editor-shell')).toHaveAttribute('data-status', 'ready', {
    timeout: options.timeout ?? 60_000,
  });
}

export function workspaceItem(path, options = {}) {
  const root = options.root ?? defaultWorkspaceRoot;
  return `[data-workspace-id="${root}/${path}"]`;
}

export async function openMainFixture(page, options = {}) {
  await openWorkspaceFile(page, 'src/main.mbt', options);
}

export async function openWorkspaceFile(page, workspacePath, options = {}) {
  const timeout = options.timeout ?? 60_000;
  const root = options.root ?? defaultWorkspaceRoot;
  await waitForReady(page, { timeout });

  if (options.waitForActiveReveal !== false) {
    const activeUri = await page.locator('.editor-shell').getAttribute('data-source-uri');
    if (activeUri) {
      await expect(page.locator(`[data-workspace-id="${activeUri}"]`)).toHaveAttribute(
        'aria-selected',
        'true',
        { timeout },
      );
    }
  }

  const segments = workspacePath.split('/');
  let prefix = '';
  for (const segment of segments.slice(0, -1)) {
    prefix = prefix ? `${prefix}/${segment}` : segment;
    const folder = page.locator(workspaceItem(prefix, { root }));
    await expect(folder).toBeVisible({ timeout });
    if ((await folder.getAttribute('aria-expanded')) !== 'true') {
      await folder.click();
    }
  }

  const item = page.locator(workspaceItem(workspacePath, { root }));
  await expect(item).toBeVisible({ timeout });
  await item.click();
  await waitForReady(page, { timeout });
  await expect(page.locator('.editor-shell')).toHaveAttribute(
    'data-source-uri',
    `${root}/${workspacePath}`,
    { timeout },
  );
}

export function collectReadonlyEvents(page) {
  const messages = [];
  page.on('console', (message) => {
    if (message.text().includes('[readonly-editor]')) {
      messages.push(message.text());
    }
  });
  return {
    count(name) {
      return messages.filter((event) => event.includes(name)).length;
    },
    async some(name, options = {}) {
      await expect
        .poll(() => messages.some((event) => event.includes(name)), {
          timeout: options.timeout ?? 5_000,
        })
        .toBeTruthy();
      return true;
    },
    messages,
  };
}

export function lastScrollTop(events) {
  const latest = events.messages
    .filter((event) => event.includes('view:scroll'))
    .at(-1);
  if (!latest) {
    return 0;
  }
  const match = latest.match(/"scrollTop":([0-9.]+)/);
  return match ? Number(match[1]) : 0;
}

export async function firstVisibleLine(page) {
  return page.evaluate(() => {
    const root = document.querySelector('.monaco-editor.readonly-editor');
    const rootRect = root?.getBoundingClientRect();
    if (!rootRect) {
      return 0;
    }
    for (const line of document.querySelectorAll('.view-line[data-line]')) {
      const rect = line.getBoundingClientRect();
      if (rect.bottom >= rootRect.top && rect.top <= rootRect.bottom) {
        return Number(line.getAttribute('data-line') || 0);
      }
    }
    return 0;
  });
}
