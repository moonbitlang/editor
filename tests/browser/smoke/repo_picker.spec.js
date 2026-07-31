import { expect, test } from '../support/test.js';

// The workspace switch is server-process-wide state, so this test restores
// the original fixture root before finishing; a mid-test failure leaves the
// server on the other fixture, which the failure report will show anyway.
test('browses the host filesystem and switches repositories', async ({ page }) => {
  await page.goto('/');
  await expect(
    page.locator('[data-workspace-id="readonly-remote://workspace/src/main.mbt"]'),
  ).toBeVisible();

  // The picker opens at the served root and lists its child directories.
  await page.locator('[data-action="open-repository"]').click();
  await expect(page.locator('.repo-picker')).toBeVisible();
  await expect(page.locator('.repo-picker-path')).toContainText('tests/fixtures/workspace');
  await expect(page.locator('.repo-picker-entry[data-repo-path$="/src"]')).toBeVisible();

  // ".." lists the fixtures directory, where both workspaces carry the
  // repository badge from their moon.mod files.
  await page.locator('.repo-picker-parent').click();
  const secondFixture = page.locator('.repo-picker-entry[data-repo-path$="/workspace-two"]');
  await expect(secondFixture).toBeVisible();
  await expect(secondFixture.locator('.repo-picker-badge')).toHaveText('repo');

  // Navigating into the second fixture and confirming re-roots the server:
  // the picker closes, the explorer re-resolves, and auto-open lands on the
  // new workspace's first MoonBit file.
  await secondFixture.click();
  await expect(page.locator('.repo-picker-path')).toContainText('workspace-two');
  await page.locator('[data-action="confirm-repo-picker"]').click();
  await expect(page.locator('.repo-picker')).toHaveCount(0);
  await expect(
    page.locator('[data-workspace-id="readonly-remote://workspace/src/hello.mbt"]'),
  ).toBeVisible();
  await expect(page.locator('.editor-shell')).toHaveAttribute(
    'data-source-uri',
    'readonly-remote://workspace/src/hello.mbt',
  );

  // Switch back so later tests see the original fixture workspace.
  await page.locator('[data-action="open-repository"]').click();
  await page.locator('.repo-picker-parent').click();
  await page.locator('.repo-picker-entry[data-repo-path$="/workspace"]').click();
  await page.locator('[data-action="confirm-repo-picker"]').click();
  await expect(page.locator('.repo-picker')).toHaveCount(0);
  await expect(
    page.locator('[data-workspace-id="readonly-remote://workspace/src/main.mbt"]'),
  ).toBeVisible();
});
