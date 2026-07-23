import { expect, test } from '../support/test.js';

const editorSelector = '.async-feature-host > .monaco-editor[data-uri]';
const visibleHoverSelector =
  '[data-content-widget="editor.contrib.resizableContentHoverWidget"] .monaco-hover:not(.hidden)';

const source = (marker) => `pub fn target() -> Int { // ${marker}\n  1\n}\n`;

async function started(page) {
  return page.evaluate(() => globalThis.__asyncFeatureControls.started());
}

async function state(page) {
  return page.evaluate(() => globalThis.__asyncFeatureControls.state());
}

async function waitForNewHover(page, afterId = 0) {
  await expect
    .poll(
      async () =>
        (await started(page)).filter(
          (call) => call.kind === 'hover' && call.id > afterId,
        ).length,
      { timeout: 5_000 },
    )
    .toBeGreaterThan(0);
  return (await started(page)).find(
    (call) => call.kind === 'hover' && call.id > afterId,
  );
}

async function waitForSettled(page, callIds) {
  await expect
    .poll(async () => {
      const calls = await started(page);
      return callIds.every((id) => calls.find((call) => call.id === id)?.settled);
    })
    .toBe(true);
}

async function waitForCancelled(page, callIds) {
  await expect
    .poll(async () => {
      const calls = await started(page);
      return callIds.every((id) => calls.find((call) => call.id === id)?.cancelled);
    })
    .toBe(true);
}

async function waitForRenderedTurn(page) {
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      ),
  );
}

async function release(page, call, outcome) {
  expect(
    await page.evaluate(
      ({ callId, value }) => globalThis.__asyncFeatureControls.release(callId, value),
      { callId: call.id, value: outcome },
    ),
  ).toBe(true);
}

async function hoverTarget(page) {
  const line = page.locator('.async-feature-host .view-line').filter({ hasText: 'target' });
  await expect(line).toBeVisible();
  const point = await line.evaluate((node) => {
    const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
    for (let text = walker.nextNode(); text; text = walker.nextNode()) {
      const index = text.textContent.indexOf('target');
      if (index < 0) continue;
      const range = document.createRange();
      range.setStart(text, index);
      range.setEnd(text, index + 'target'.length);
      const rect = range.getBoundingClientRect();
      return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
    }
    return null;
  });
  expect(point).not.toBeNull();
  await page.mouse.move(0, 0);
  await page.mouse.move(point.x, point.y);
}

async function expectNoHoverDom(page) {
  await expect(page.locator('.async-feature-host .hoverHighlight')).toHaveCount(0);
  await expect(
    page.locator(
      '.async-feature-host [data-content-widget="editor.contrib.resizableContentHoverWidget"]',
    ),
  ).toHaveCount(0);
}

test('rejects stale async hover results across model ownership changes', async ({
  page,
}) => {
  await page.goto('/browser-tests/component.html?asyncFeatures=1');
  await page.waitForFunction(() => Boolean(globalThis.__asyncFeatureControls));
  await expect(page.locator(editorSelector)).toContainText('initial');

  const initialState = await state(page);
  const uri = initialState.currentUri;
  const modelOne = initialState.currentModelId;
  await hoverTarget(page);
  const initialHover = await waitForNewHover(page);

  await page.evaluate(
    (value) => globalThis.__asyncFeatureControls.set_value(value),
    source('same-object'),
  );
  await expect(page.locator(editorSelector)).toContainText('same-object');
  const afterSetValue = await state(page);
  expect(afterSetValue.currentModelId).toBe(modelOne);
  expect(afterSetValue.internalVersion).toBeGreaterThan(initialState.internalVersion);
  await waitForCancelled(page, [initialHover.id]);
  await hoverTarget(page);
  const sameModelHover = await waitForNewHover(page, initialHover.id);

  const reportsBeforeOld = (await state(page)).resolveReports;
  await release(page, initialHover, 'old-first hover');
  await waitForSettled(page, [initialHover.id]);
  await waitForRenderedTurn(page);
  await expect.poll(async () => (await state(page)).resolveReports).toBe(reportsBeforeOld);
  await expect(page.locator(visibleHoverSelector)).not.toContainText('old-first hover');

  await page.evaluate(
    (value) => globalThis.__asyncFeatureControls.replace_same_uri(value),
    source('replacement-newest'),
  );
  await expect(page.locator(editorSelector)).toContainText('replacement-newest');
  await waitForCancelled(page, [sameModelHover.id]);
  await expect.poll(async () => (await state(page)).currentModelId).not.toBe(modelOne);
  const replacementState = await state(page);
  expect(replacementState.currentUri).toBe(uri);
  expect(replacementState.currentHostVersion).toBe(initialState.currentHostVersion);
  expect(replacementState.currentRevision).toBe(initialState.currentRevision);
  await hoverTarget(page);
  const replacementHover = await waitForNewHover(page, sameModelHover.id);
  expect(replacementHover.modelId).toBe(replacementState.currentModelId);
  expect(replacementHover.modelId).not.toBe(modelOne);

  const reportsBeforeNewest = (await state(page)).resolveReports;
  await release(page, replacementHover, 'newest hover');
  await waitForSettled(page, [replacementHover.id]);
  await expect
    .poll(async () => (await state(page)).resolveReports)
    .toBe(reportsBeforeNewest + 1);
  const newestResolvedState = await state(page);
  expect(newestResolvedState.reports.at(-1)).toEqual({
    ok: true,
    revision: replacementState.currentRevision,
  });
  const hover = page.locator(visibleHoverSelector);
  await expect(hover).toContainText('newest hover');
  await expect(page.locator('.async-feature-host .hoverHighlight')).toHaveCount(1);

  const reportsAfterNewest = (await state(page)).resolveReports;
  await release(page, sameModelHover, 'old-last hover');
  await waitForSettled(page, [sameModelHover.id]);
  await waitForRenderedTurn(page);
  await expect.poll(async () => (await state(page)).resolveReports).toBe(reportsAfterNewest);
  await expect(hover).toContainText('newest hover');
  await expect(hover).not.toContainText('old-last hover');

  const editorBox = await page.locator(editorSelector).boundingBox();
  expect(editorBox).not.toBeNull();
  const hoverWidget = page.locator(
    '.async-feature-host [data-content-widget="editor.contrib.resizableContentHoverWidget"]',
  );
  await hoverWidget.dispatchEvent('mouseleave', { clientX: -10, clientY: -10 });
  await expect(page.locator(visibleHoverSelector)).toHaveCount(0);

  let lastCall = replacementHover.id;
  await page.evaluate(
    (value) => globalThis.__asyncFeatureControls.set_value(value),
    source('model-dispose-pending'),
  );
  await hoverTarget(page);
  const modelDisposeHover = await waitForNewHover(page, lastCall);
  lastCall = modelDisposeHover.id;
  const reportsBeforeModelDispose = (await state(page)).resolveReports;
  await page.evaluate(() => globalThis.__asyncFeatureControls.dispose_model());
  await waitForCancelled(page, [modelDisposeHover.id]);
  await release(page, modelDisposeHover, 'cancelled-empty');
  await waitForSettled(page, [modelDisposeHover.id]);
  await expect.poll(async () => (await state(page)).resolveReports).toBe(
    reportsBeforeModelDispose,
  );
  await expectNoHoverDom(page);

  await page.evaluate(
    (value) => globalThis.__asyncFeatureControls.replace_same_uri(value),
    source('detach-pending'),
  );
  await hoverTarget(page);
  const detachHover = await waitForNewHover(page, lastCall);
  lastCall = detachHover.id;
  const reportsBeforeDetach = (await state(page)).resolveReports;
  await page.evaluate(() => globalThis.__asyncFeatureControls.detach());
  await waitForCancelled(page, [detachHover.id]);
  await release(page, detachHover, 'error');
  await waitForSettled(page, [detachHover.id]);
  await expect.poll(async () => (await state(page)).resolveReports).toBe(reportsBeforeDetach);
  await expectNoHoverDom(page);

  await page.evaluate(
    (value) => globalThis.__asyncFeatureControls.replace_same_uri(value),
    source('dispose-pending'),
  );
  await hoverTarget(page);
  const disposeHover = await waitForNewHover(page, lastCall);
  const reportsBeforeDispose = (await state(page)).resolveReports;
  await page.evaluate(() => globalThis.__asyncFeatureControls.dispose());
  await waitForCancelled(page, [disposeHover.id]);
  await release(page, disposeHover, 'disposed stale hover');
  await waitForSettled(page, [disposeHover.id]);
  await expect.poll(async () => (await state(page)).resolveReports).toBe(reportsBeforeDispose);
  await expectNoHoverDom(page);
  await expect.poll(async () => (await state(page)).pending).toBe(0);
});
