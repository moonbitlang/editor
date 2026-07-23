import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

const host = '.view-zones-host';

async function settle(page, delay = 80) {
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      ),
  );
  if (delay > 0) await page.waitForTimeout(delay);
}

async function mountViewZones(page, testInfo) {
  const reporter = await installMoonBitReporter(page);
  await page.goto('/browser-tests/component.html?viewZones=1');
  await page.waitForFunction(() => Boolean(globalThis.__viewZonesControls));
  const report = await reporter.waitForReport(testInfo, {
    suite: 'view_zones',
    timeout: 10_000,
  });
  expectMoonBitReportPassed(report, { suite: 'view_zones' });
  expect(report.metrics.registeredZones).toBeGreaterThanOrEqual(7);
  await settle(page);
  return reporter;
}

async function state(page) {
  return page.evaluate(() => globalThis.__viewZonesControls.state());
}

async function control(page, name, ...args) {
  return page.evaluate(
    ({ method, values }) => globalThis.__viewZonesControls[method](...values),
    { method: name, values: args },
  );
}

async function startViewZoneStyleProbe(page) {
  await page.evaluate(() => {
    const fixture = document.querySelector('.view-zones-host');
    const targets = [
      fixture.querySelector('.vz-primary'),
      fixture.querySelector('.vz-primary-margin'),
      fixture.querySelector('.view-zones'),
      fixture.querySelector('.margin-view-zones'),
    ];
    const original = CSSStyleDeclaration.prototype.setProperty;
    const writes = [];
    CSSStyleDeclaration.prototype.setProperty = function (name, value, priority) {
      const index = targets.findIndex((target) => target.style === this);
      if (index >= 0) writes.push({ index, name, value });
      return original.call(this, name, value, priority);
    };
    globalThis.__viewZonesStopStyleProbe = () => {
      CSSStyleDeclaration.prototype.setProperty = original;
      delete globalThis.__viewZonesStopStyleProbe;
      return writes;
    };
  });
}

async function stopViewZoneStyleProbe(page) {
  return page.evaluate(() => globalThis.__viewZonesStopStyleProbe());
}

function expectBefore(values, left, right) {
  expect(values.indexOf(left), `${left} should be present`).toBeGreaterThanOrEqual(0);
  expect(values.indexOf(right), `${right} should be present`).toBeGreaterThanOrEqual(0);
  expect(values.indexOf(left), `${left} should precede ${right}`).toBeLessThan(
    values.indexOf(right),
  );
}

test('ViewZones preserve caller DOM and use generated transaction IDs', async ({
  page,
}, testInfo) => {
  const reporter = await mountViewZones(page, testInfo);
  try {
    const initial = await state(page);
    const generatedIds = [
      initial.primaryId,
      initial.secondaryId,
      initial.errorId,
      initial.safeId,
      initial.suppressId,
      initial.omittedId,
      initial.lineHeightId,
      initial.negativeZeroId,
      initial.offscreenId,
    ];
    expect(generatedIds.every(Boolean)).toBe(true);
    expect(new Set(generatedIds).size).toBe(generatedIds.length);
    expect(initial.primaryId).toBe(initial.initialPrimaryId);
    expect(initial.negativeZeroCallbackPreserved).toBe(true);

    const primary = page.locator(`${host} .vz-primary`);
    const primaryChild = primary.locator('.vz-primary-child');
    const primaryMargin = page.locator(`${host} .vz-primary-margin`);
    await expect(primary).toHaveAttribute('monaco-view-zone', initial.primaryId);
    await expect(primaryMargin).toHaveAttribute(
      'monaco-view-zone',
      initial.primaryId,
    );
    await expect(primary).toHaveAttribute('data-caller-owned', 'primary');
    await expect(primaryMargin).toHaveAttribute('data-caller-owned', 'margin');
    await expect(primary).toHaveClass(/\bhost-primary\b/);
    await expect(primary).toHaveClass(/\bpreserved-class\b/);
    await expect(primary).not.toHaveClass(/\bview-zone\b/);
    await expect(primary).toHaveCSS('color', 'rgb(1, 2, 3)');
    await expect(primary).toHaveCSS('border-left-color', 'rgb(4, 5, 6)');
    await expect(primary).toHaveCSS('padding-left', '7px');
    await expect(primary).toHaveCSS('position', 'absolute');
    expect(await primary.evaluate((node) => node.style.width)).toBe('100%');
    await expect(primary).toContainText('preserved descendant');
    await expect(primaryChild).toHaveAttribute('data-caller-state', 'preserved');
    await expect(primaryMargin).toHaveClass(/\bpreserved-margin-class\b/);
    await expect(primaryMargin).toHaveCSS(
      'background-color',
      'rgb(7, 8, 9)',
    );
    await expect(primaryMargin).toHaveCSS(
      'border-right-color',
      'rgb(10, 11, 12)',
    );
    await expect(primaryMargin).toContainText('preserved margin content');
    expect(await primary.getAttribute('data-view-zone-id')).toBeNull();

    expect(await control(page, 'identity')).toEqual({
      primary: true,
      child: true,
      margin: true,
      primaryState: true,
      childState: true,
      marginState: true,
      replacementConnected: false,
      replacementMarginConnected: false,
      invalidConnected: false,
    });
    expect(JSON.parse(initial.primaryComputedPhase)).toEqual({
      nodeConnected: false,
      nodeParent: false,
      nodePosition: 'relative',
      nodeWidth: '37px',
      nodeDisplay: 'inline',
      nodeTop: '7px',
      nodeHeight: '9px',
      nodeZoneAttr: null,
      nodeVisibleAttr: null,
      marginConnected: false,
      marginParent: false,
      marginPosition: 'relative',
      marginWidth: '19px',
      marginDisplay: 'inline',
      marginTop: '4px',
      marginHeight: '8px',
      marginZoneAttr: null,
    });
    await control(page, 'click_original_child');
    await control(page, 'click_original_margin');
    expect(await control(page, 'click_counts')).toEqual({
      primary: 1,
      child: 1,
      margin: 1,
    });

    const attachment = await page.locator(host).evaluate((fixture) => {
      const margin = fixture.querySelector('.margin');
      const linesContent = fixture.querySelector('.lines-content');
      const contentContainer = fixture.querySelector('.view-zones');
      const marginContainer = fixture.querySelector('.margin-view-zones');
      const contentChildren = Array.from(linesContent.children);
      const marginChildren = Array.from(margin.children);
      const zoneChildren = Array.from(contentContainer.children);
      const primaryNode = fixture.querySelector('.vz-primary');
      const secondaryNode = fixture.querySelector('.vz-secondary');
      const primaryMarginNode = fixture.querySelector('.vz-primary-margin');
      return {
        contentRole: contentContainer.getAttribute('role'),
        contentAria: contentContainer.getAttribute('aria-hidden'),
        contentDataPart: contentContainer.getAttribute('data-view-part'),
        contentPosition: contentContainer.style.position,
        contentTop: contentContainer.style.top,
        contentLeft: contentContainer.style.left,
        contentZIndex: contentContainer.style.zIndex,
        marginRole: marginContainer.getAttribute('role'),
        marginAria: marginContainer.getAttribute('aria-hidden'),
        marginDataPart: marginContainer.getAttribute('data-view-part'),
        marginPosition: marginContainer.style.position,
        marginChildren: marginChildren.map((node) => node.className),
        contentChildren: contentChildren.map((node) => node.className),
        zoneChildren: zoneChildren.map((node) => node.className),
        primaryTop: Number.parseFloat(primaryNode.style.top),
        secondaryTop: Number.parseFloat(secondaryNode.style.top),
        primaryHeight: Number.parseFloat(primaryNode.style.height),
        marginTop: Number.parseFloat(primaryMarginNode.style.top),
        marginHeight: Number.parseFloat(primaryMarginNode.style.height),
        marginDisplay: primaryMarginNode.style.display,
        primaryDisplay: primaryNode.style.display,
      };
    });
    expect(attachment).toMatchObject({
      contentRole: 'presentation',
      contentAria: 'true',
      contentDataPart: null,
      contentPosition: 'absolute',
      contentTop: '',
      contentLeft: '',
      contentZIndex: '',
      marginRole: 'presentation',
      marginAria: 'true',
      marginDataPart: null,
      marginPosition: 'absolute',
      marginChildren: ['margin-view-zones', 'margin-view-overlays'],
      primaryHeight: 32,
      marginHeight: 32,
      marginDisplay: 'block',
      primaryDisplay: 'block',
    });
    expect(attachment.marginTop).toBe(attachment.primaryTop);
    expect(attachment.contentChildren.indexOf('view-overlays')).toBeLessThan(
      attachment.contentChildren.indexOf('view-zones'),
    );
    expect(attachment.contentChildren.indexOf('view-zones')).toBeLessThan(
      attachment.contentChildren.indexOf('view-lines'),
    );
    expect(attachment.zoneChildren[0]).toContain('vz-primary');
    expect(attachment.zoneChildren[1]).toContain('vz-secondary');
    // DOM order is source add order; ordinal independently puts secondary first.
    expect(attachment.secondaryTop).toBeLessThan(attachment.primaryTop);

    const beforeLayout = await state(page);
    await control(page, 'layout_primary');
    await settle(page);
    const afterLayout = await state(page);
    expect(afterLayout.primaryId).toBe(initial.primaryId);
    expect(afterLayout.zoneEvents).toBe(beforeLayout.zoneEvents + 1);
    expect(afterLayout.primaryComputedCount).toBeGreaterThan(
      beforeLayout.primaryComputedCount,
    );
    // layout_zone retains insertion-time minimum width and ordinal.
    expect(afterLayout.scrollWidth).toBe(beforeLayout.scrollWidth);
    expect(afterLayout.scrollWidth).toBeGreaterThanOrEqual(700);
    expect(await control(page, 'identity')).toMatchObject({
      primary: true,
      child: true,
      margin: true,
      replacementConnected: false,
      replacementMarginConnected: false,
    });
    await expect(primary).toHaveCSS('height', '36px');
    const laidOutTops = await page.locator(host).evaluate((fixture) => ({
      primary: Number.parseFloat(fixture.querySelector('.vz-primary').style.top),
      secondary: Number.parseFloat(
        fixture.querySelector('.vz-secondary').style.top,
      ),
    }));
    expect(laidOutTops.secondary).toBeLessThan(laidOutTops.primary);

    // Force the same ViewZones render once more. The part is dirty and its
    // callbacks run, but cached main/margin zone and container styles must not
    // issue even idempotent setProperty writes.
    await startViewZoneStyleProbe(page);
    await control(page, 'layout_primary');
    await page.waitForTimeout(100);
    expect(await stopViewZoneStyleProbe(page)).toEqual([]);

    const eventsBeforeInvalid = (await state(page)).zoneEvents;
    for (const action of ['normalAdd', 'normalRemove', 'normalLayout']) {
      const result = await control(page, 'invoke_invalid', action);
      expect(result.name).toBe(action);
      // MoonBit's JS panic erases the abort payload. Browser evidence pins all
      // three methods throwing; the exact source abort text is PORTED only.
      expect(result.thrown).toBe(true);
    }
    expect((await state(page)).zoneEvents).toBe(eventsBeforeInvalid);
    expect((await control(page, 'identity')).invalidConnected).toBe(false);

    const retainedPrimary = await primary.elementHandle();
    const retainedChild = await primaryChild.elementHandle();
    const retainedMargin = await primaryMargin.elementHandle();
    expect(retainedPrimary).not.toBeNull();
    expect(retainedChild).not.toBeNull();
    expect(retainedMargin).not.toBeNull();
    await control(page, 'remove_primary');
    await settle(page);
    expect(await retainedPrimary.getAttribute('monaco-view-zone')).toBeNull();
    expect(await retainedPrimary.getAttribute('monaco-visible-view-zone')).toBeNull();
    expect(await retainedMargin.getAttribute('monaco-view-zone')).toBeNull();
    expect(await retainedPrimary.evaluate((node) => node.isConnected)).toBe(false);
    expect(
      await retainedChild.evaluate(
        (node, parent) => node.parentNode === parent,
        retainedPrimary,
      ),
    ).toBe(true);
    await control(page, 'click_original_child');
    await control(page, 'click_original_margin');
    expect(await control(page, 'click_counts')).toEqual({
      primary: 2,
      child: 2,
      margin: 2,
    });

    await control(page, 'readd_primary');
    await settle(page);
    const afterReadd = await state(page);
    expect(afterReadd.primaryId).not.toBe(initial.primaryId);
    expect(await retainedPrimary.getAttribute('monaco-view-zone')).toBe(
      afterReadd.primaryId,
    );
    expect(await retainedMargin.getAttribute('monaco-view-zone')).toBe(
      afterReadd.primaryId,
    );
    expect(await retainedPrimary.evaluate((node) => node.isConnected)).toBe(true);
    expect(await control(page, 'identity')).toMatchObject({
      primary: true,
      child: true,
      margin: true,
    });
  } finally {
    reporter.dispose();
  }
});

test('ViewZones contain callback failures and preserve transaction ordering', async ({
  page,
}, testInfo) => {
  const reporter = await mountViewZones(page, testInfo);
  try {
    const initial = await state(page);
    expect(initial.safeTopCount).toBeGreaterThan(0);
    expect(initial.logs.map((entry) => entry.message)).toEqual(
      expect.arrayContaining([
        'onComputedHeight callback failed',
        'onDomNodeTop callback failed',
      ]),
    );
    expect(initial.logs.every((entry) => entry.category === 'viewer.viewZones')).toBe(
      true,
    );
    await expect(page.locator(`${host} .vz-error`)).toBeVisible();
    await expect(page.locator(`${host} .vz-safe`)).toBeVisible();

    await control(page, 'start_order_probe');
    await control(page, 'noop');
    await page.waitForTimeout(100);
    const noopOrder = await control(page, 'stop_order_probe');
    expect(noopOrder[0]).toBe('callback:noop');
    expect(noopOrder.filter((entry) => entry === 'raf-request')).toHaveLength(1);
    expect(noopOrder).not.toContain('public');
    expect((await state(page)).zoneEvents).toBe(initial.zoneEvents);

    for (const [method, callbackLabel] of [
      ['empty_remove', 'callback:empty-remove'],
      ['missing_layout', 'callback:missing-layout'],
    ]) {
      await control(page, 'start_order_probe');
      await control(page, method);
      await page.waitForTimeout(100);
      const order = await control(page, 'stop_order_probe');
      expect(order[0]).toBe(callbackLabel);
      expect(order.filter((entry) => entry === 'raf-request')).toHaveLength(1);
      expect(order).not.toContain('public');
      expect((await state(page)).zoneEvents).toBe(initial.zoneEvents);
    }

    await control(page, 'start_order_probe');
    await control(page, 'throw_noop');
    await page.waitForTimeout(100);
    const throwNoopOrder = await control(page, 'stop_order_probe');
    expect(throwNoopOrder[0]).toBe('callback:throw-noop');
    expect(
      throwNoopOrder.filter((entry) => entry === 'raf-request'),
    ).toHaveLength(1);
    expect(throwNoopOrder).not.toContain('public');
    expect((await state(page)).zoneEvents).toBe(initial.zoneEvents);
    for (const action of ['throwAdd', 'throwRemove', 'throwLayout']) {
      expect((await control(page, 'invoke_invalid', action)).thrown).toBe(true);
    }

    await control(page, 'start_order_probe');
    await control(page, 'add_then_throw');
    await page.waitForTimeout(100);
    const addOrder = await control(page, 'stop_order_probe');
    expectBefore(addOrder, 'callback:add', 'computed:add');
    expectBefore(addOrder, 'computed:add', 'callback:throw-after-add');
    expectBefore(addOrder, 'callback:throw-after-add', 'public');
    // Whitespace height changes may schedule from ViewLayout before the public
    // event. The live root transaction still coalesces to one final frame.
    expectBefore(addOrder, 'public', 'top:add');
    if (addOrder.includes('rendered')) {
      expectBefore(addOrder, 'top:add', 'rendered');
    }
    expect(addOrder.filter((entry) => entry === 'raf-request')).toHaveLength(1);
    const afterAdd = await state(page);
    expect(afterAdd.zoneEvents).toBe(initial.zoneEvents + 1);
    expect(afterAdd.orderedId).not.toBe('');
    await expect(page.locator(`${host} .vz-ordered-throw`)).toHaveAttribute(
      'monaco-view-zone',
      afterAdd.orderedId,
    );
    await expect(page.locator(`${host} .vz-ordered-throw`)).toBeVisible();
    expect(afterAdd.logs.map((entry) => entry.message)).toEqual(
      expect.arrayContaining(['changeViewZones callback failed']),
    );
    await expect(page.locator(`${host} .view-lines`)).toContainText(
      'view_zone_line_',
    );

    const beforeLineHeight = await state(page);
    await control(page, 'start_order_probe');
    await control(page, 'set_line_height', 30);
    await page.waitForTimeout(100);
    const lineHeightOrder = await control(page, 'stop_order_probe');
    const afterLineHeight = await state(page);
    expect(afterLineHeight.lineHeightComputedCount).toBe(
      beforeLineHeight.lineHeightComputedCount + 1,
    );
    expect(afterLineHeight.lineHeightLastComputed).toBe(45);
    expect(afterLineHeight.zoneEvents).toBe(beforeLineHeight.zoneEvents + 1);
    expectBefore(lineHeightOrder, 'computed:line-height', 'public');
    expect(
      lineHeightOrder.filter((entry) => entry === 'raf-request'),
    ).toHaveLength(1);
  } finally {
    reporter.dispose();
  }
});

test('ViewZones use offscreen callback tops and retain widths when none are visible', async ({
  page,
}, testInfo) => {
  const reporter = await mountViewZones(page, testInfo);
  try {
    const initial = await state(page);
    expect(initial.primaryLastTop).toBeGreaterThan(-1_000_000);
    expect(initial.offscreenLastTop).toBe(-1_000_000);
    const containers = await page.locator(host).evaluate((fixture) => ({
      contentWidth: Number.parseFloat(
        fixture.querySelector('.view-zones').style.width,
      ),
      marginWidth: Number.parseFloat(
        fixture.querySelector('.margin-view-zones').style.width,
      ),
      contentWidthText: fixture.querySelector('.view-zones').style.width,
      marginWidthText: fixture.querySelector('.margin-view-zones').style.width,
    }));
    expect(containers.contentWidth).toBe(
      Math.max(initial.scrollWidth, initial.contentWidth),
    );
    expect(containers.marginWidth).toBe(initial.contentLeft);
    await expect(page.locator(`${host} .vz-offscreen`)).not.toHaveAttribute(
      'monaco-visible-view-zone',
      'true',
    );
    await expect(page.locator(`${host} .vz-offscreen`)).toHaveCSS(
      'display',
      'none',
    );
    await expect(page.locator(`${host} .vz-offscreen`)).toHaveCSS('top', '0px');
    await expect(page.locator(`${host} .vz-offscreen`)).toHaveCSS(
      'height',
      '0px',
    );

    // The content rail is translated while the merged local `.margin` root is
    // viewport-fixed. ViewZones must nevertheless keep its gutter companion
    // at the exact same client-space top after a nonzero scroll.
    await control(page, 'set_scroll_top', 20);
    await settle(page);
    const pairedRects = await page.locator(host).evaluate((fixture) => ({
      content: fixture.querySelector('.vz-suppress').getBoundingClientRect().top,
      margin: fixture
        .querySelector('.vz-suppress-margin')
        .getBoundingClientRect().top,
      contentInlineTop: fixture.querySelector('.vz-suppress').style.top,
      marginInlineTop: fixture.querySelector('.vz-suppress-margin').style.top,
    }));
    expect(pairedRects.marginInlineTop).toBe(pairedRects.contentInlineTop);
    expect(Math.abs(pairedRects.content - pairedRects.margin)).toBeLessThanOrEqual(
      1,
    );

    // This scroll band lies after every top zone and before the line-40 zone.
    await control(page, 'set_scroll_top', 400);
    await settle(page);
    const gap = await state(page);
    expect(gap.scrollTop).toBe(400);
    await expect(page.locator(`${host} [monaco-visible-view-zone]`)).toHaveCount(
      0,
    );
    expect(gap.primaryLastTop).toBe(-1_000_000 - gap.scrollTop);
    expect(gap.offscreenLastTop).toBe(-1_000_000 - gap.scrollTop);
    const retainedWidths = await page.locator(host).evaluate((fixture) => ({
      content: fixture.querySelector('.view-zones').style.width,
      margin: fixture.querySelector('.margin-view-zones').style.width,
    }));
    expect(retainedWidths).toEqual({
      content: containers.contentWidthText,
      margin: containers.marginWidthText,
    });

    await control(page, 'show_offscreen');
    await settle(page);
    const visible = await state(page);
    await expect(page.locator(`${host} .vz-offscreen`)).toHaveAttribute(
      'monaco-visible-view-zone',
      'true',
    );
    await expect(page.locator(`${host} .vz-offscreen`)).toHaveCSS(
      'display',
      'block',
    );
    await expect(page.locator(`${host} .vz-offscreen`)).toHaveCSS(
      'height',
      '28px',
    );
    expect(visible.offscreenLastTop).toBeGreaterThanOrEqual(0);
    expect(visible.offscreenLastTop).toBeLessThan(260);
  } finally {
    reporter.dispose();
  }
});

test('ViewZones render visible DOM on the aligned 500k rail', async ({
  page,
}, testInfo) => {
  const reporter = await mountViewZones(page, testInfo);
  try {
    await control(page, 'enable_rail');
    await settle(page);
    const rail = await state(page);
    expect(rail.railSpacerId).not.toBe('');
    expect(rail.railTargetId).not.toBe('');
    expect(rail.scrollTop).toBeGreaterThan(500_000);
    expect(rail.railTopCount).toBeGreaterThan(0);
    expect(rail.railLastTop).toBeGreaterThanOrEqual(0);
    expect(rail.railLastTop).toBeLessThan(260);
    const geometry = await page.locator(host).evaluate((fixture) => ({
      targetTop: Number.parseFloat(
        fixture.querySelector('.vz-rail-target').style.top,
      ),
      marginContainerTop: Number.parseFloat(
        fixture.querySelector('.margin-view-zones').style.top,
      ),
    }));
    await expect(page.locator(`${host} .vz-rail-target`)).toHaveAttribute(
      'monaco-visible-view-zone',
      'true',
    );
    const bigNumbersDelta =
      rail.scrollTop + rail.railLastTop - geometry.targetTop;
    expect(bigNumbersDelta).toBe(499_986);
    expect(bigNumbersDelta).toBeGreaterThan(0);
    expect(bigNumbersDelta % 18).toBe(0);
    expect(geometry.targetTop + geometry.marginContainerTop).toBe(
      rail.railLastTop,
    );
  } finally {
    reporter.dispose();
  }
});

test('same-model flush retains and recomputes the live ViewZones registry', async ({
  page,
}, testInfo) => {
  const reporter = await mountViewZones(page, testInfo);
  try {
    const initial = await state(page);
    const initialRegistrySize = await page
      .locator(`${host} [monaco-view-zone]`)
      .count();
    await control(page, 'set_model_line_count', 2);
    await settle(page);
    const shrunk = await state(page);
    expect(shrunk.modelLineCount).toBe(2);
    expect(shrunk.primaryId).toBe(initial.primaryId);
    expect(shrunk.offscreenId).toBe(initial.offscreenId);
    expect(shrunk.lineHeightId).toBe(initial.lineHeightId);
    expect(shrunk.primaryTopCount).toBeGreaterThan(
      initial.primaryTopCount,
    );
    expect(
      await page.locator(`${host} [monaco-view-zone]`).count(),
    ).toBe(initialRegistrySize);
    await expect(page.locator(`${host} .vz-line-height`)).toHaveAttribute(
      'monaco-view-zone',
      initial.lineHeightId,
    );
    await control(page, 'set_model_line_count', 80);
    await settle(page);
    const grown = await state(page);
    expect(grown.modelLineCount).toBe(80);
    expect(grown.primaryId).toBe(initial.primaryId);
    expect(grown.offscreenId).toBe(initial.offscreenId);
    expect(grown.lineHeightId).toBe(initial.lineHeightId);
    expect(grown.primaryTopCount).toBeGreaterThan(
      shrunk.primaryTopCount,
    );
    expect(
      await page.locator(`${host} [monaco-view-zone]`).count(),
    ).toBe(initialRegistrySize);
    await expect(page.locator(`${host} .vz-line-height`)).toHaveAttribute(
      'monaco-view-zone',
      initial.lineHeightId,
    );
  } finally {
    reporter.dispose();
  }
});

for (const [name, disposeMethod] of [
  ['Viewer dispose', 'dispose_viewer'],
  ['model dispose', 'dispose_model'],
]) {
  test(`${name} loses the active ViewZones registry`, async ({
    page,
  }, testInfo) => {
    const reporter = await mountViewZones(page, testInfo);
    try {
      expect(await page.locator(`${host} [monaco-view-zone]`).count()).toBeGreaterThan(
        0,
      );
      await control(page, disposeMethod);
      await settle(page);
      await control(page, 'probe_after_dispose');
      const disposed = await state(page);
      expect(disposed.hasViewDom).toBe(false);
      expect(disposed.postDisposeCallbackCount).toBe(0);
      expect(disposed.postDisposeId).toBe('');
      expect(await page.locator(`${host} [monaco-view-zone]`).count()).toBe(0);
      expect(
        await page.locator(`${host} .vz-post-dispose`).count(),
      ).toBe(0);
    } finally {
      reporter.dispose();
    }
  });
}

async function zonePoint(locator) {
  const box = await locator.boundingBox();
  expect(box).not.toBeNull();
  // Content-zone width follows scrollWidth and can extend far beyond the
  // clipped editor viewport; choose a point near its visible left edge.
  return {
    x: box.x + Math.min(box.width / 2, 20),
    y: box.y + box.height / 2,
  };
}

async function mouseDownAt(page, point, button = 'left') {
  await page.mouse.move(point.x, point.y);
  await page.mouse.down({ button });
  await page.mouse.up({ button });
  await page.waitForTimeout(30);
}

test('ViewZone suppressMouseDown is live for content and gutter hits', async ({
  page,
}, testInfo) => {
  const reporter = await mountViewZones(page, testInfo);
  try {
    const initial = await state(page);
    const omitted = page.locator(`${host} .vz-omitted-suppress`);
    const primaryMargin = page.locator(`${host} .vz-primary-margin`);
    const suppressed = page.locator(`${host} .vz-suppress`);
    const suppressedMargin = page.locator(`${host} .vz-suppress-margin`);
    await expect(omitted).toBeVisible();
    await expect(primaryMargin).toBeVisible();
    await expect(suppressed).toBeVisible();
    await expect(suppressedMargin).toBeVisible();

    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(omitted));
    let records = await control(page, 'mouse_records');
    expect(records).toHaveLength(1);
    expect(records[0]).toMatchObject({
      button: 0,
      defaultPrevented: false,
      activeRoot: false,
    });
    expect(await state(page)).toMatchObject({
      mouseTargetId: initial.omittedId,
      mouseTargetKind: 'content',
    });

    // Omitted suppressMouseDown is false for a gutter companion too.
    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(primaryMargin));
    records = await control(page, 'mouse_records');
    expect(records).toHaveLength(1);
    expect(records[0]).toMatchObject({
      button: 0,
      defaultPrevented: false,
      activeRoot: false,
    });
    expect(await state(page)).toMatchObject({
      mouseTargetId: initial.primaryId,
      mouseTargetKind: 'gutter',
    });

    // Explicit false is the same branch, read live from the retained delegate.
    await control(page, 'set_primary_suppress', false);
    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(primaryMargin));
    records = await control(page, 'mouse_records');
    expect(records[0]).toMatchObject({
      button: 0,
      defaultPrevented: false,
      activeRoot: false,
    });

    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(suppressed));
    records = await control(page, 'mouse_records');
    expect(records).toHaveLength(1);
    expect(records[0]).toMatchObject({
      button: 0,
      defaultPrevented: true,
      activeRoot: true,
    });
    expect(await state(page)).toMatchObject({
      mouseTargetId: initial.suppressId,
      mouseTargetKind: 'content',
    });

    // Middle-button is still a handled mouse-down when suppression is live.
    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(suppressed), 'middle');
    records = await control(page, 'mouse_records');
    expect(records).toHaveLength(1);
    expect(records[0]).toMatchObject({
      button: 1,
      defaultPrevented: true,
      activeRoot: true,
    });

    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(suppressedMargin));
    records = await control(page, 'mouse_records');
    expect(records).toHaveLength(1);
    expect(records[0]).toMatchObject({
      button: 0,
      defaultPrevented: true,
      activeRoot: true,
    });
    expect(await state(page)).toMatchObject({
      mouseTargetId: initial.suppressId,
      mouseTargetKind: 'gutter',
    });

    // A right-button mousedown is not a handled selection start.
    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(suppressed), 'right');
    records = await control(page, 'mouse_records');
    expect(records).toHaveLength(1);
    expect(records[0]).toMatchObject({
      button: 2,
      defaultPrevented: false,
      activeRoot: false,
    });
    expect(await state(page)).toMatchObject({
      mouseTargetId: initial.suppressId,
      mouseTargetKind: 'content',
    });

    // The delegate is read live; no layout transaction is required.
    await control(page, 'set_suppress', false);
    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(suppressed));
    records = await control(page, 'mouse_records');
    expect(records[0]).toMatchObject({
      defaultPrevented: false,
      activeRoot: false,
    });
    expect(await state(page)).toMatchObject({
      mouseTargetId: initial.suppressId,
      mouseTargetKind: 'content',
    });

    await control(page, 'focus_sink');
    await control(page, 'clear_mouse');
    await mouseDownAt(page, await zonePoint(suppressedMargin));
    records = await control(page, 'mouse_records');
    expect(records[0]).toMatchObject({
      button: 0,
      defaultPrevented: false,
      activeRoot: false,
    });
    expect(await state(page)).toMatchObject({
      mouseTargetId: initial.suppressId,
      mouseTargetKind: 'gutter',
    });
    expect((await state(page)).mouseEvents).toBe(initial.mouseEvents + 9);
  } finally {
    reporter.dispose();
  }
});
