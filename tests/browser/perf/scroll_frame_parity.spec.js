import { expect, test } from '../support/test.js';

const quickMatrix = process.env.SCROLL_PARITY_QUICK === '1';
const viewportLines = quickMatrix ? [10] : [10, 37, 100];
const smoothValues = [false, true];
const inputs = ['physical', 'trackpad'];
const axes = ['vertical', 'horizontal'];
const locations = quickMatrix ? ['mid'] : ['boundary', 'mid'];
const repetitions = 3;
const frameCount = 40;

test.describe('source-relative scroll frame evidence', () => {
  // A retry gets a fresh Playwright worker when a long-lived browser process
  // suffers host scheduler jitter; the first failure and trace remain visible.
  test.describe.configure({ retries: 1 });
  test(
    'compares scroll frames and mutations with the pinned Monaco oracle',
    compareScrollFrameParity,
  );
});

async function compareScrollFrameParity({ page }, testInfo) {
  test.setTimeout(420_000);
  await page.addInitScript(installScrollProbe);
  const cells = [];

  for (const lines of viewportLines) {
    for (const smooth of smoothValues) {
      for (const input of inputs) {
        for (const axis of axes) {
          for (const location of locations) {
            const config = { lines, smooth, input, axis, location };
            const monaco = await measureImplementation(page, 'monaco', config);
            const local = await measureImplementation(page, 'local', config);
            const cell = { ...config, monaco, local };
            cells.push(cell);
            console.log('[perf] scroll cell', JSON.stringify({
              ...config,
              monaco: summarizeSamples(monaco.samples),
              local: summarizeSamples(local.samples),
              monacoCallbacks: summarizeCallbackSpans(monaco.samples),
              localCallbacks: summarizeCallbackSpans(local.samples),
            }));

            const start = startPosition(config);
            const delta = input === 'physical' ? 50 : 3;
            const expected = axis === 'vertical'
              ? { top: start.top + delta, left: start.left }
              : { top: start.top, left: start.left + delta };
            for (const sample of [...monaco.samples, ...local.samples]) {
              expect(sample.finalScrollTop).toBeCloseTo(expected.top, 5);
              expect(sample.finalScrollLeft).toBeCloseTo(expected.left, 5);
              expect(sample.analysis.stateCount).toBeGreaterThan(0);
              expect(sample.analysis.commitCount).toBeGreaterThan(0);
              expect(sample.analysis.coalescedStateCount).toBe(0);
              expect(sample.analysis.unmatchedStateCount).toBe(0);
              expect(sample.analysis.unmatchedCommitCount).toBe(0);
              if (smooth && input === 'physical') {
                expect(sample.distinctPositions).toBeGreaterThan(2);
              } else {
                expect(sample.distinctPositions).toBeLessThanOrEqual(2);
              }
            }
            for (let index = 0; index < repetitions; index++) {
              const localSample = local.samples[index];
              const monacoSample = monaco.samples[index];
              expect(localSample.analysis.worstStateToCommitLag).toBeLessThanOrEqual(
                monacoSample.analysis.worstStateToCommitLag,
              );
              expect(localSample.analysis.missingRenderCount).toBe(0);
              if (smooth && input === 'physical') {
                expect(localSample.analysis.worstStateToCommitLag).toBe(0);
                expect(localSample.analysis.worstStateToRenderStartLag).toBe(0);
                expect(localSample.analysis.worstStateToRenderFinishLag).toBe(0);
              }
            }

            if (input === 'trackpad' && location === 'mid') {
              // Same-window steady movement must not invoke either renderer
              // batch or replace rendered HTML.
              for (const sample of local.samples) {
                expect(sample.viewerMetrics.viewLayer ?? {}).toEqual({});
                expect(sample.mutations.innerHTMLWrites ?? 0).toBe(0);
                expect(sample.mutations.insertAdjacentHTML ?? 0).toBe(0);
                expect(sample.mutations.replaceChild ?? 0).toBe(0);
                expect(sample.mutations.attributeWrites ?? 0).toBeLessThanOrEqual(18);
                expect(sample.mutations.styleWrites ?? 0).toBe(0);
                expect(sample.viewerMetrics.styleWritesByKey).toEqual(
                  axis === 'vertical'
                    ? { 'lines-content:top': 1 }
                    : { 'lines-content:left': 1 },
                );
              }
            }
          }
        }
      }
    }
  }

  const observedCadence = percentile(
    cells.flatMap((cell) => [
      ...cell.local.samples.flatMap((sample) => sample.intervals),
      ...cell.monaco.samples.flatMap((sample) => sample.intervals),
    ]),
    0.5,
  );
  const report = {
    suite: 'scroll_frame_parity',
    status: 'passed',
    repetitions,
    frameCount,
    observedCadenceHz: Math.round(1000 / observedCadence),
    deferredCadences: observedCadence < 12
      ? [{ hz: 60, reason: 'this host exposes only the approximately 120Hz rAF cadence' }]
      : [{ hz: 120, reason: 'this host exposes only the approximately 60Hz rAF cadence' }],
    cells,
  };
  await testInfo.attach('scroll-frame-parity', {
    body: JSON.stringify(report, null, 2),
    contentType: 'application/json',
  });
  console.log('[perf] scroll frame parity', JSON.stringify({
    cells: cells.length,
    observedCadenceHz: report.observedCadenceHz,
    worstLocalCommitLag: Math.max(...cells.flatMap(
      (cell) => cell.local.samples.map((sample) => sample.analysis.worstStateToCommitLag),
    )),
    worstMonacoCommitLag: Math.max(...cells.flatMap(
      (cell) => cell.monaco.samples.map((sample) => sample.analysis.worstStateToCommitLag),
    )),
    maxLocalDroppedRatio: Math.max(...cells.map((cell) => cell.local.medianDroppedFrameRatio)),
    maxMonacoDroppedRatio: Math.max(...cells.map((cell) => cell.monaco.medianDroppedFrameRatio)),
  }));
}

test('classifies callback order and mutation microtasks by native frame timestamp', async ({ page }) => {
  await page.addInitScript(installScrollProbe);
  await page.goto('/browser-tests/monaco-oracle.html');
  const trace = await page.evaluate(() => new Promise((resolve) => {
    const rail = document.createElement('div');
    rail.style.top = '0px';
    rail.style.left = '0px';
    document.body.appendChild(rail);
    const probe = globalThis.__scrollProbe;
    probe.attachRail(rail, 'classifier-fixture');
    probe.reset();
    probe.start('classifier-fixture');
    requestAnimationFrame(() => {
      probe.recordMarker('first');
      rail.style.top = '-10px';
      requestAnimationFrame(() => {
        probe.recordMarker('nested-next');
        setTimeout(() => {
          probe.stop();
          resolve(probe.snapshot().trace);
        }, 0);
      });
    });
    requestAnimationFrame(() => probe.recordMarker('second'));
  }));
  const first = trace.events.find((event) => event.name === 'first');
  const second = trace.events.find((event) => event.name === 'second');
  const nested = trace.events.find((event) => event.name === 'nested-next');
  const commit = trace.events.find((event) => event.kind === 'commit');
  expect(first.frameId).toBe(second.frameId);
  expect(first.nativeTimestamp).toBe(second.nativeTimestamp);
  expect(commit.frameId).toBe(first.frameId);
  expect(commit.nativeTimestamp).toBe(first.nativeTimestamp);
  expect(nested.frameId).toBe(first.frameId + 1);
  expect(nested.nativeTimestamp).toBeGreaterThan(first.nativeTimestamp);
  expect(trace.rawMutations.length).toBeGreaterThanOrEqual(1);
});

test('model exits cancel retired smooth state and rail commits', async ({ page }) => {
  await page.addInitScript(installScrollProbe);
  for (const action of ['replaceModel', 'detachModel', 'dispose']) {
    await page.goto('/browser-tests/component.html?scrollPerf=1&lines=37&smooth=true');
    await expect(page.locator('.scroll-perf-host[data-scroll-ready="true"]')).toHaveCount(1, {
      timeout: 15_000,
    });
    const result = await page.evaluate(async ({ action }) => {
      const controls = globalThis.__scrollPerfControls;
      const probe = globalThis.__scrollProbe;
      probe.attachRail(document.querySelector('.lines-content'), `retired-${action}`);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      probe.reset();
      probe.start(`retired-${action}`);
      const publicEventsBefore = controls.getPublicScrollEvents();
      const event = new WheelEvent('wheel', {
        deltaY: 40,
        deltaMode: 0,
        bubbles: true,
        cancelable: true,
      });
      document.querySelector('.overflow-guard').dispatchEvent(event);
      controls[action]();
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      probe.stop();
      return {
        publicEventDelta: controls.getPublicScrollEvents() - publicEventsBefore,
        mutations: probe.snapshot(),
      };
    }, { action });
    expect(result.publicEventDelta).toBe(0);
    expect(result.mutations.trace.events.filter(
      (event) => event.kind === 'state-committed' || event.kind === 'commit',
    )).toEqual([]);
    expect(result.mutations.trace.rawMutations).toEqual([]);
    if (action !== 'replaceModel') {
      expect(result.mutations.trace.events).toEqual([]);
    }
  }
});

test.describe('mobile touch commit-frame evidence', () => {
  test.use({
    hasTouch: true,
    isMobile: true,
    viewport: { width: 390, height: 844 },
  });

  test('compares vertical horizontal and diagonal touch inertia', async ({ page }, testInfo) => {
    test.setTimeout(360_000);
    await page.addInitScript(installScrollProbe);
    const cdp = await page.context().newCDPSession(page);
    const cells = [];
    for (const lines of viewportLines) {
      const touchLocations = lines === 37 ? ['boundary', 'mid'] : ['mid'];
      for (const location of touchLocations) {
        for (const axis of ['vertical', 'horizontal', 'diagonal']) {
          const config = { lines, smooth: false, axis, location };
          const monaco = await measureTouchImplementation(
            page, cdp, 'monaco', config,
          );
          const local = await measureTouchImplementation(
            page, cdp, 'local', config,
          );
          const cell = { ...config, monaco, local };
          cells.push(cell);
          console.log('[perf] touch cell', JSON.stringify({
            ...config,
            monaco: summarizeSamples(monaco.samples),
            local: summarizeSamples(local.samples),
          }));
          const start = startPosition(config);
          for (let index = 0; index < repetitions; index++) {
            const monacoSample = monaco.samples[index];
            const localSample = local.samples[index];
            for (const sample of [monacoSample, localSample]) {
              expect(sample.analysis.stateCount).toBeGreaterThan(0);
              expect(sample.analysis.commitCount).toBeGreaterThan(0);
              expect(sample.analysis.coalescedStateCount).toBe(0);
              expect(sample.analysis.unmatchedStateCount).toBe(0);
              expect(sample.analysis.unmatchedCommitCount).toBe(0);
              const topDelta = sample.finalScrollTop - start.top;
              const leftDelta = sample.finalScrollLeft - start.left;
              expect(sample.settled).toBeTruthy();
              if (axis === 'vertical') {
                expect(topDelta).toBeGreaterThan(10);
                expect(topDelta).toBeLessThan(1_000);
                expect(Math.abs(leftDelta)).toBeLessThan(0.01);
              } else if (axis === 'horizontal') {
                expect(leftDelta).toBeGreaterThan(10);
                expect(leftDelta).toBeLessThan(1_000);
                expect(Math.abs(topDelta)).toBeLessThan(0.01);
              } else {
                expect(topDelta).toBeGreaterThan(10);
                expect(topDelta).toBeLessThan(1_000);
                expect(leftDelta).toBeGreaterThan(10);
                expect(leftDelta).toBeLessThan(1_000);
              }
            }
            expect(localSample.analysis.missingRenderCount).toBe(0);
            expect(localSample.analysis.worstStateToCommitLag).toBeLessThanOrEqual(
              monacoSample.analysis.worstStateToCommitLag,
            );
            expect(localSample.analysis.animationStateCount).toBeGreaterThan(0);
            expect(localSample.analysis.worstAnimationStateToCommitLag).toBe(0);
            expect(localSample.analysis.worstAnimationStateToRenderStartLag).toBe(0);
            expect(localSample.analysis.worstAnimationStateToRenderFinishLag).toBe(0);
          }
        }
      }
    }
    await testInfo.attach('touch-scroll-frame-parity', {
      body: JSON.stringify({ cells, repetitions }, null, 2),
      contentType: 'application/json',
    });
  });

  test('disposal cancels pending touch inertia without late commits', async ({ page }) => {
    await page.addInitScript(installScrollProbe);
    const cdp = await page.context().newCDPSession(page);
    const config = {
      lines: 37,
      smooth: false,
      axis: 'vertical',
      location: 'mid',
    };
    await openImplementation(page, 'local', config);
    await page.evaluate(async ({ start }) => {
      globalThis.__scrollPerfControls.setScrollPosition(start.top, start.left);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    }, { start: startPosition(config) });
    await dispatchTouchGesture(page, cdp, '.overflow-guard', 'vertical');
    const result = await page.evaluate(async () => {
      const controls = globalThis.__scrollPerfControls;
      const probe = globalThis.__scrollProbe;
      probe.reset();
      probe.start('disposed-touch-local');
      const publicEventsBefore = controls.getPublicScrollEvents();
      controls.dispose();
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      probe.stop();
      return {
        publicEventDelta: controls.getPublicScrollEvents() - publicEventsBefore,
        mutations: probe.snapshot(),
      };
    });
    expect(result.publicEventDelta).toBe(0);
    expect(result.mutations.trace.events).toEqual([]);
    expect(result.mutations.trace.rawMutations).toEqual([]);
  });
});

test('covers unchanged, overlap, jump, entering, leaving, and invalid row batches', async ({ page }) => {
  await page.addInitScript(installScrollProbe);
  await page.goto('/browser-tests/component.html?scrollPerf=1&lines=10&smooth=false');
  await expect(page.locator('.scroll-perf-host[data-scroll-ready="true"]')).toHaveCount(1, {
    timeout: 15_000,
  });
  // Seed retained geometry, then move inside the same line band.
  await applyMutationStep(page, 3);
  const unchanged = await applyMutationStep(page, 6);
  expect(unchanged.viewerMetrics.viewLayer ?? {}).toEqual({});
  expect(unchanged.mutations.innerHTMLWrites ?? 0).toBe(0);
  expect(unchanged.mutations.insertAdjacentHTML ?? 0).toBe(0);

  const oneLineOverlap = await applyMutationStep(page, 24);
  expect(oneLineOverlap.viewerMetrics.viewLayer['new-batch']).toBeGreaterThanOrEqual(1);
  const multiLineOverlap = await applyMutationStep(page, 114);
  expect(multiLineOverlap.viewerMetrics.viewLayer['new-batch']).toBeGreaterThanOrEqual(1);
  const noOverlapJump = await applyMutationStep(page, 18_000);
  expect(noOverlapJump.viewerMetrics.viewLayer['new-batch']).toBeGreaterThanOrEqual(1);

  const invalid = await page.evaluate(async () => {
    globalThis.__moonbitViewerScrollMetrics = {};
    globalThis.__scrollProbe.reset();
    globalThis.__scrollProbe.start();
    const visibleLine = Math.floor(globalThis.__scrollPerfControls.getScrollTop() / 18) + 2;
    globalThis.__scrollPerfControls.setSelection(visibleLine);
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    globalThis.__scrollProbe.stop();
    return {
      viewerMetrics: globalThis.__moonbitViewerScrollMetrics,
      mutations: globalThis.__scrollProbe.snapshot(),
    };
  });
  expect(invalid.viewerMetrics.viewLayer['invalid-batch']).toBeGreaterThanOrEqual(1);
  expect(invalid.viewerMetrics.viewLayer['new-batch'] ?? 0).toBe(0);
});

async function applyMutationStep(page, scrollTop) {
  return page.evaluate(async ({ scrollTop }) => {
    globalThis.__moonbitViewerScrollMetrics = {};
    globalThis.__scrollProbe.reset();
    globalThis.__scrollProbe.start();
    globalThis.__scrollPerfControls.setScrollTop(scrollTop);
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    globalThis.__scrollProbe.stop();
    return {
      viewerMetrics: globalThis.__moonbitViewerScrollMetrics,
      mutations: globalThis.__scrollProbe.snapshot(),
    };
  }, { scrollTop });
}

async function measureImplementation(page, implementation, config) {
  await openImplementation(page, implementation, config);

  // Seed retained-row geometry caches without affecting the wheel classifier.
  await page.evaluate(async () => {
    globalThis.__scrollPerfControls.setScrollPosition(3, 3);
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    globalThis.__scrollPerfControls.reset();
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  });
  // Monaco's wheel classifier and wheel-scroll position both acquire history
  // on the first moving sample. Run the exact measured setup once and discard
  // it so all three retained repetitions start from an established source and
  // axis without accepting a first-event no-op as parity evidence.
  await prepareWheelSample(page, config);
  await runTrace(page, config, implementation);

  const samples = [];
  for (let repetition = 0; repetition < repetitions; repetition++) {
    await prepareWheelSample(page, config);
    samples.push(await runTrace(page, config, implementation));
  }
  return {
    samples,
    medianDroppedFrameRatio: median(samples.map((sample) => sample.droppedFrameRatio)),
    medianP95FrameInterval: median(samples.map((sample) => sample.p95FrameInterval)),
  };
}

async function prepareWheelSample(page, config) {
  const start = startPosition(config);
  const seed = config.axis === 'vertical'
    ? { top: start.top + 1, left: start.left }
    : { top: start.top, left: start.left + 1 };
  await page.evaluate(async ({ start, seed }) => {
    globalThis.__scrollPerfControls.setScrollPosition(start.top, start.left);
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    // A same-window move seeds cached row/rail styles that initial batched HTML
    // does not publish to FastDomNode. Return to the exact start before enabling
    // metrics, matching the steady-scroll smoke contract.
    globalThis.__scrollPerfControls.setScrollPosition(seed.top, seed.left);
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    globalThis.__scrollPerfControls.setScrollPosition(start.top, start.left);
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  }, { start, seed });
}

async function openImplementation(page, implementation, config) {
  if (implementation === 'local') {
    await page.goto(
      `/browser-tests/component.html?scrollPerf=1&lines=${config.lines}` +
      `&smooth=${config.smooth}&wide=${config.axis !== 'vertical'}`,
    );
    await expect(page.locator('.scroll-perf-host[data-scroll-ready="true"]')).toHaveCount(1, {
      timeout: 15_000,
    });
    await page.evaluate(() => {
      globalThis.__scrollPerfControls.wheelTarget = document.querySelector('.overflow-guard');
      globalThis.__scrollProbe.attachRail(
        document.querySelector('.lines-content'),
        'local',
      );
    });
  } else {
    await page.goto('/browser-tests/monaco-oracle.html');
    await setupMonaco(page, config);
  }
}

async function measureTouchImplementation(page, cdp, implementation, config) {
  await openImplementation(page, implementation, config);
  const samples = [];
  for (let repetition = 0; repetition < repetitions; repetition++) {
    const start = startPosition(config);
    await page.evaluate(async ({ start }) => {
      globalThis.__scrollPerfControls.setScrollPosition(start.top, start.left);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    }, { start });
    samples.push(await runTouchTrace(page, cdp, implementation, config));
  }
  return { samples };
}

async function runTouchTrace(page, cdp, implementation, config) {
  await startTraceCollection(page, config.axis, implementation, true);
  const targetSelector = implementation === 'local'
    ? '.overflow-guard'
    : '.monaco-editor[role="code"]';
  await dispatchTouchGesture(page, cdp, targetSelector, config.axis);
  return finishTraceCollection(page, implementation);
}

async function dispatchTouchGesture(page, cdp, targetSelector, axis) {
  const box = await page.locator(targetSelector).boundingBox();
  expect(box).not.toBeNull();
  const startX = Math.round(Math.min(box.x + box.width * 0.65, 300));
  const startY = Math.round(box.y + Math.min(box.height * 0.6, 140));
  const totalX = axis === 'vertical' ? 0 : -48;
  const totalY = axis === 'horizontal' ? 0 : -48;
  const touchPoint = (step) => ({
    x: Math.round(startX + totalX * step / 4),
    y: Math.round(startY + totalY * step / 4),
    radiusX: 1,
    radiusY: 1,
    force: 1,
    id: 1,
  });
  await cdp.send('Input.dispatchTouchEvent', {
    type: 'touchStart',
    touchPoints: [touchPoint(0)],
  });
  for (let step = 1; step <= 4; step++) {
    await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(resolve)));
    await cdp.send('Input.dispatchTouchEvent', {
      type: 'touchMove',
      touchPoints: [touchPoint(step)],
    });
  }
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(resolve)));
  await cdp.send('Input.dispatchTouchEvent', {
    type: 'touchEnd',
    touchPoints: [],
  });
}

async function setupMonaco(page, config) {
  await page.evaluate(async ({ lines, smooth, axis }) => {
    const monaco = await import('/browser-tests/monaco-oracle.mjs');
    const host = document.querySelector('#monaco-host');
    host.style.width = '800px';
    host.style.height = `${lines * 18}px`;
    const tail = 'alpha beta gamma delta epsilon zeta eta theta '.repeat(
      axis === 'vertical' ? 1 : 24,
    );
    const text = Array.from(
      { length: 3000 },
      (_, index) => `perf line ${index + 1} ${tail}\n`,
    ).join('');
    const editor = monaco.editor.create(host, {
      value: text,
      language: 'plaintext',
      readOnly: true,
      automaticLayout: false,
      dimension: { width: 800, height: lines * 18 },
      lineHeight: 18,
      fontSize: 13,
      smoothScrolling: smooth,
      scrollBeyondLastLine: false,
      folding: false,
      minimap: { enabled: false },
      scrollbar: { mouseWheelSmoothScroll: true },
    });
    const decorations = [];
    for (let line = 2; line <= 3000; line += 2) {
      decorations.push({
        range: new monaco.Range(line, 1, line, 10),
        options: {
          className: 'scroll-perf-line',
          inlineClassName: 'scroll-perf-inline',
          description: 'scroll performance oracle',
        },
      });
    }
    editor.createDecorationsCollection(decorations);
    editor.changeViewZones((accessor) => {
      const node = document.createElement('div');
      node.textContent = 'scroll performance view zone';
      accessor.addZone({
        afterLineNumber: 5,
        heightInPx: 18,
        domNode: node,
      });
    });
    editor.layout({ width: 800, height: lines * 18 });
    editor.onDidScrollChange((event) => {
      if (event.scrollTopChanged || event.scrollLeftChanged) {
        globalThis.__scrollProbe.recordMonacoState({
          scrollTop: event.scrollTop,
          scrollLeft: event.scrollLeft,
        });
      }
    });
    globalThis.__scrollPerfControls = {
      reset: () => editor.setScrollPosition({ scrollTop: 0, scrollLeft: 0 }, 1),
      setScrollPosition: (top, left) => editor.setScrollPosition({
        scrollTop: top,
        scrollLeft: left,
      }, 1),
      setScrollTop: (top) => editor.setScrollPosition({ scrollTop: top }, 1),
      setScrollLeft: (left) => editor.setScrollPosition({ scrollLeft: left }, 1),
      getScrollTop: () => editor.getScrollTop(),
      getScrollLeft: () => editor.getScrollLeft(),
      setSelection: (line) => editor.setSelection(new monaco.Selection(line, 1, line, 5)),
      wheelTarget: document.querySelector('.monaco-editor[role="code"]'),
    };
    globalThis.__scrollProbe.attachRail(
      host.querySelector('.lines-content'),
      'monaco',
    );
  }, config);
}

async function runTrace(page, config, implementation) {
  await startTraceCollection(page, config.axis, implementation);
  await dispatchSyntheticWheel(page, config.input, config.axis, 1);
  return finishTraceCollection(page, implementation);
}

async function dispatchSyntheticWheel(page, input, axis, direction) {
  await page.evaluate(({ input, axis, direction }) => {
    const delta = input === 'trackpad' ? 2.37 : 40;
    const event = new WheelEvent('wheel', {
      deltaX: axis === 'horizontal' ? delta * direction : 0,
      deltaY: axis === 'vertical' ? delta * direction : 0,
      deltaMode: 0,
      bubbles: true,
      cancelable: true,
    });
    // Chromium synthesizes legacy wheelDelta accessors as zero for a JS-made
    // WheelEvent. Shadow them with undefined so Monaco's StandardWheelEvent
    // takes the modern deltaX/deltaY branch, matching the local normalizer.
    for (const key of ['wheelDelta', 'wheelDeltaX', 'wheelDeltaY']) {
      Object.defineProperty(event, key, { value: undefined });
    }
    globalThis.__scrollPerfControls.wheelTarget.dispatchEvent(event);
  }, { input, axis, direction });
}

async function startTraceCollection(page, axis, implementation, waitForSettle = false) {
  await page.evaluate(({ frameCount, axis, implementation, waitForSettle }) => {
    globalThis.__moonbitViewerScrollMetrics = {};
    const probe = globalThis.__scrollProbe;
    probe.reset();
    probe.start(implementation);
    const timestamps = [];
    const positions = [];
    let stableFrames = 0;
    let previousPosition = null;
    globalThis.__scrollTracePromise = new Promise((resolve) => {
      const sample = (timestamp) => {
        timestamps.push(timestamp);
        const position = {
          top: globalThis.__scrollPerfControls.getScrollTop(),
          left: globalThis.__scrollPerfControls.getScrollLeft(),
        };
        positions.push(position);
        if (previousPosition && position.top === previousPosition.top &&
            position.left === previousPosition.left) {
          stableFrames += 1;
        } else {
          stableFrames = 0;
        }
        previousPosition = position;
        const minimumReached = timestamps.length >= frameCount;
        const settled = stableFrames >= 4;
        if ((!waitForSettle && minimumReached) ||
            (waitForSettle && minimumReached && settled) ||
            timestamps.length >= 120) {
          resolve();
        } else {
          requestAnimationFrame(sample);
        }
      };
      requestAnimationFrame(sample);
      }).then(() => new Promise((resolve) => setTimeout(resolve, 0))).then(() => {
        probe.stop();
        const intervals = timestamps.slice(1).map(
          (time, index) => time - timestamps[index],
        );
        const cadence = percentileInBrowser(intervals, 0.5);
        const longFrames = intervals.filter(
          (interval) => interval > cadence * 1.5,
        ).length;
        return {
          timestamps,
          positions,
          intervals,
          finalScrollTop: globalThis.__scrollPerfControls.getScrollTop(),
          finalScrollLeft: globalThis.__scrollPerfControls.getScrollLeft(),
          settled: stableFrames >= 4,
          distinctPositions: new Set(
            positions.map((position) => {
              if (axis === 'vertical') return position.top;
              if (axis === 'horizontal') return position.left;
              return `${position.top}:${position.left}`;
            }),
          ).size,
          longFrameCount: longFrames,
          droppedFrameRatio: intervals.length ? longFrames / intervals.length : 0,
          p50FrameInterval: cadence,
          p95FrameInterval: percentileInBrowser(intervals, 0.95),
          mutations: probe.snapshot(),
          viewerMetrics: globalThis.__moonbitViewerScrollMetrics,
        };
      });
  }, { frameCount, axis, implementation, waitForSettle });
}

async function finishTraceCollection(page, implementation) {
  const sample = await page.evaluate(() => globalThis.__scrollTracePromise);
  sample.analysis = analyzeCommitTrace(sample.mutations.trace, implementation);
  return sample;
}

function percentile(values, quantile) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * quantile))];
}

function median(values) {
  return percentile(values, 0.5);
}

function startPosition(config) {
  if (config.location === 'mid') {
    // Offset from the 18px line boundary so the 3px trackpad cell stays in
    // one retained row window; boundary transitions have their own cells.
    return { top: 18_003, left: config.axis === 'vertical' ? 0 : 400 };
  }
  return { top: 0, left: 0 };
}

function summarizeSamples(samples) {
  return samples.map((sample) => ({
    final: [sample.finalScrollTop, sample.finalScrollLeft],
    states: sample.analysis.stateCount,
    commits: sample.analysis.commitCount,
    coalesced: sample.analysis.coalescedStateCount,
    unmatchedStates: sample.analysis.unmatchedStateCount,
    unmatchedCommits: sample.analysis.unmatchedCommitCount,
    worstLag: sample.analysis.worstStateToCommitLag,
  }));
}

function analyzeCommitTrace(trace, implementation) {
  const events = trace?.events ?? [];
  const stateKind = implementation === 'local' ? 'state-committed' : 'state';
  const states = events.filter((event) => event.kind === stateKind);
  const commits = events.filter((event) => event.kind === 'commit');
  const renderStarts = events.filter((event) => event.kind === 'render-started');
  const renderFinishes = events.filter((event) => event.kind === 'render-finished');
  const usedCommits = new Set();
  const stateToCommitLags = [];
  const animationStateToCommitLags = [];
  const stateToRenderStartLags = [];
  const stateToRenderFinishLags = [];
  const animationStateToRenderStartLags = [];
  const animationStateToRenderFinishLags = [];
  let coalescedStateCount = 0;
  let unmatchedStateCount = 0;
  let missingRenderCount = 0;

  for (let index = 0; index < states.length; index++) {
    const state = states[index];
    const nextState = states[index + 1];
    const firstCommitAfter = commits.find(
      (commit, commitIndex) =>
        !usedCommits.has(commitIndex) &&
        commit.eventSequence > state.eventSequence,
    );
    if (nextState && (!firstCommitAfter ||
        nextState.eventSequence < firstCommitAfter.eventSequence)) {
      coalescedStateCount += 1;
      continue;
    }
    const commitIndex = commits.findIndex(
      (commit, candidateIndex) =>
        !usedCommits.has(candidateIndex) &&
        commit.eventSequence > state.eventSequence &&
        samePosition(commit, state),
    );
    if (commitIndex < 0) {
      unmatchedStateCount += 1;
      continue;
    }
    usedCommits.add(commitIndex);
    const commit = commits[commitIndex];
    const stateToCommitLag = commit.frameId - state.frameId;
    stateToCommitLags.push(stateToCommitLag);
    if (state.inRaf) animationStateToCommitLags.push(stateToCommitLag);
    if (implementation === 'local') {
      const renderStart = renderStarts.find(
        (event) => event.eventSequence > state.eventSequence &&
          event.eventSequence < commit.eventSequence &&
          samePosition(event, state),
      );
      const renderFinish = renderFinishes.find(
        (event) => event.eventSequence > state.eventSequence &&
          event.eventSequence < commit.eventSequence &&
          samePosition(event, state),
      );
      if (!renderStart || !renderFinish ||
          renderStart.eventSequence >= renderFinish.eventSequence) {
        missingRenderCount += 1;
      } else {
        const startLag = renderStart.frameId - state.frameId;
        const finishLag = renderFinish.frameId - state.frameId;
        stateToRenderStartLags.push(startLag);
        stateToRenderFinishLags.push(finishLag);
        if (state.inRaf) {
          animationStateToRenderStartLags.push(startLag);
          animationStateToRenderFinishLags.push(finishLag);
        }
      }
    }
  }

  return {
    stateCount: states.length,
    commitCount: commits.length,
    coalescedStateCount,
    unmatchedStateCount,
    unmatchedCommitCount: commits.length - usedCommits.size,
    missingRenderCount,
    worstStateToCommitLag: maxOrZero(stateToCommitLags),
    animationStateCount: animationStateToCommitLags.length,
    worstAnimationStateToCommitLag: maxOrZero(animationStateToCommitLags),
    worstStateToRenderStartLag: maxOrZero(stateToRenderStartLags),
    worstStateToRenderFinishLag: maxOrZero(stateToRenderFinishLags),
    worstAnimationStateToRenderStartLag: maxOrZero(
      animationStateToRenderStartLags,
    ),
    worstAnimationStateToRenderFinishLag: maxOrZero(
      animationStateToRenderFinishLags,
    ),
    stateToCommitLags,
    animationStateToCommitLags,
    stateToRenderStartLags,
    stateToRenderFinishLags,
  };
}

function samePosition(left, right) {
  return Math.abs(left.scrollTop - right.scrollTop) < 0.01 &&
    Math.abs(left.scrollLeft - right.scrollLeft) < 0.01;
}

function maxOrZero(values) {
  return values.length ? Math.max(...values) : 0;
}

function summarizeCallbackSpans(samples) {
  const summary = {
    stateWithoutRailCommit: 0,
    stateWithRailCommit: 0,
    railCommitWithoutState: 0,
    styleWrites: 0,
    attributeWrites: 0,
    innerHTMLWrites: 0,
  };
  for (const sample of samples) {
    summary.styleWrites += sample.mutations.styleWrites ?? 0;
    summary.attributeWrites += sample.mutations.attributeWrites ?? 0;
    summary.innerHTMLWrites += sample.mutations.innerHTMLWrites ?? 0;
    for (const span of sample.mutations.callbackSpans ?? []) {
      const stateChanged = span.before.scrollTop !== span.after.scrollTop ||
        span.before.scrollLeft !== span.after.scrollLeft;
      const railChanged = span.before.top !== span.after.top ||
        span.before.left !== span.after.left;
      if (stateChanged && railChanged) summary.stateWithRailCommit += 1;
      else if (stateChanged) summary.stateWithoutRailCommit += 1;
      else if (railChanged) summary.railCommitWithoutState += 1;
    }
  }
  return summary;
}

function installScrollProbe() {
  const metrics = {};
  let active = false;
  let trace = { events: [], rawMutations: [] };
  let nativeFrameId = 0;
  let lastNativeTimestamp = null;
  let callbackSequence = 0;
  let eventSequence = 0;
  let activeFrame = null;
  let lastFrame = null;
  let rail = null;
  let railLabel = null;
  let railObserver = null;
  let railPosition = { scrollTop: 0, scrollLeft: 0 };
  const nativeRequestAnimationFrame = globalThis.requestAnimationFrame.bind(globalThis);
  const readScrollSnapshot = () => {
    const controls = globalThis.__scrollPerfControls;
    const rail = document.querySelector('.lines-content');
    if (!controls || !rail) return null;
    return {
      scrollTop: controls.getScrollTop(),
      scrollLeft: controls.getScrollLeft(),
      top: rail.style.top,
      left: rail.style.left,
    };
  };
  globalThis.requestAnimationFrame = (callback) =>
    nativeRequestAnimationFrame((timestamp) => {
      if (timestamp !== lastNativeTimestamp) {
        lastNativeTimestamp = timestamp;
        nativeFrameId += 1;
        callbackSequence = 0;
      }
      const frame = {
        frameId: nativeFrameId,
        nativeTimestamp: timestamp,
        callbackSequence: ++callbackSequence,
      };
      const previousActiveFrame = activeFrame;
      activeFrame = frame;
      const record = active;
      const before = record ? readScrollSnapshot() : null;
      try {
        return callback(timestamp);
      } finally {
        const after = record ? readScrollSnapshot() : null;
        if (before && after && (
          before.scrollTop !== after.scrollTop ||
          before.scrollLeft !== after.scrollLeft ||
          before.top !== after.top ||
          before.left !== after.left
        )) {
          metrics.callbackSpans ??= [];
          metrics.callbackSpans.push({ timestamp, before, after });
        }
        lastFrame = frame;
        activeFrame = previousActiveFrame;
      }
    });
  const stamp = () => {
    const frame = activeFrame ?? lastFrame ?? {
      frameId: 0,
      nativeTimestamp: null,
      callbackSequence: 0,
    };
    return {
      ...frame,
      inRaf: activeFrame !== null,
      eventSequence: ++eventSequence,
      now: performance.now(),
    };
  };
  const recordEvent = (kind, payload = {}) => {
    if (!active) return;
    trace.events.push({ kind, ...payload, ...stamp() });
  };
  const normalizeZero = (value) => Object.is(value, -0) ? 0 : value;
  const readEffectiveRailPosition = () => {
    if (!rail) return { scrollTop: 0, scrollLeft: 0 };
    const top = Number.parseFloat(rail.style.top || '0');
    const left = Number.parseFloat(rail.style.left || '0');
    return {
      scrollTop: normalizeZero(-(Number.isFinite(top) ? top : 0)),
      scrollLeft: normalizeZero(-(Number.isFinite(left) ? left : 0)),
    };
  };
  const attachRail = (nextRail, label) => {
    railObserver?.disconnect();
    rail = nextRail;
    railLabel = label;
    railPosition = readEffectiveRailPosition();
    if (!rail) return;
    railObserver = new MutationObserver((records) => {
      const nextPosition = readEffectiveRailPosition();
      if (active) {
        const batchSequence = eventSequence + 1;
        records.forEach((record, recordIndex) => {
          trace.rawMutations.push({
            label: railLabel,
            batchSequence,
            recordIndex,
            oldValue: record.oldValue,
            currentStyle: rail.getAttribute('style'),
            ...nextPosition,
            ...stamp(),
          });
        });
        if (nextPosition.scrollTop !== railPosition.scrollTop ||
            nextPosition.scrollLeft !== railPosition.scrollLeft) {
          recordEvent('commit', { label: railLabel, ...nextPosition });
        }
      }
      railPosition = nextPosition;
    });
    railObserver.observe(rail, {
      attributes: true,
      attributeFilter: ['style'],
      attributeOldValue: true,
    });
  };
  const frameClock = () => globalThis.requestAnimationFrame(frameClock);
  globalThis.requestAnimationFrame(frameClock);
  const increment = (key) => {
    if (active) metrics[key] = (metrics[key] || 0) + 1;
  };
  const wrapMethod = (prototype, key, metric) => {
    const original = prototype[key];
    if (typeof original !== 'function') return;
    prototype[key] = function (...args) {
      increment(metric);
      return original.apply(this, args);
    };
  };
  wrapMethod(Element.prototype, 'setAttribute', 'attributeWrites');
  wrapMethod(Element.prototype, 'insertAdjacentHTML', 'insertAdjacentHTML');
  wrapMethod(Node.prototype, 'insertBefore', 'insertBefore');
  wrapMethod(Node.prototype, 'appendChild', 'appendChild');
  wrapMethod(Node.prototype, 'removeChild', 'removeChild');
  wrapMethod(Node.prototype, 'replaceChild', 'replaceChild');
  wrapMethod(Element.prototype, 'getBoundingClientRect', 'forcedLayoutReads');
  wrapMethod(Element.prototype, 'getClientRects', 'forcedLayoutReads');
  const innerHTML = Object.getOwnPropertyDescriptor(Element.prototype, 'innerHTML');
  if (innerHTML?.set) {
    Object.defineProperty(Element.prototype, 'innerHTML', {
      ...innerHTML,
      set(value) {
        increment('innerHTMLWrites');
        if (active) {
          metrics.innerHTMLTargets ??= [];
          metrics.innerHTMLTargets.push(this.className || this.tagName);
        }
        return innerHTML.set.call(this, value);
      },
    });
  }
  for (const key of ['top', 'left', 'width', 'height', 'lineHeight', 'transform', 'contain']) {
    const descriptor = Object.getOwnPropertyDescriptor(CSSStyleDeclaration.prototype, key);
    if (!descriptor?.set) continue;
    Object.defineProperty(CSSStyleDeclaration.prototype, key, {
      ...descriptor,
      set(value) {
        increment('styleWrites');
        return descriptor.set.call(this, value);
      },
    });
  }
  for (const key of [
    'offsetWidth', 'offsetHeight', 'clientWidth', 'clientHeight',
    'scrollWidth', 'scrollHeight',
  ]) {
    const descriptor = Object.getOwnPropertyDescriptor(HTMLElement.prototype, key);
    if (!descriptor?.get) continue;
    Object.defineProperty(HTMLElement.prototype, key, {
      ...descriptor,
      get() {
        increment('forcedLayoutReads');
        return descriptor.get.call(this);
      },
    });
  }
  globalThis.__scrollProbe = {
    reset() {
      for (const key of Object.keys(metrics)) delete metrics[key];
      trace = { events: [], rawMutations: [] };
      eventSequence = 0;
    },
    start(implementation = 'fixture') {
      trace.implementation = implementation;
      railPosition = readEffectiveRailPosition();
      active = true;
    },
    stop() {
      active = false;
    },
    snapshot() {
      return {
        ...metrics,
        trace: {
          ...trace,
          events: [...trace.events],
          rawMutations: [...trace.rawMutations],
        },
      };
    },
    attachRail,
    recordLocalPhase(payload) {
      recordEvent(payload.phase, payload);
    },
    recordMonacoState(payload) {
      recordEvent('state', payload);
    },
    recordMarker(name, payload = {}) {
      recordEvent('marker', { name, ...payload });
    },
  };
  globalThis.percentileInBrowser = (values, quantile) => {
    if (!values.length) return 0;
    const sorted = [...values].sort((a, b) => a - b);
    return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * quantile))];
  };
}
