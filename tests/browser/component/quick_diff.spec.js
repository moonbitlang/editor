import { expect, test } from '../support/test.js';
import {
  expectMoonBitReportPassed,
  installMoonBitReporter,
} from '../support/moonbit_reporter.js';

// End-to-end coverage for the quick-diff git gutter
// (tests/browser/moonbit/quick_diff): a baseline in the quick-diff service
// differing from the model by one modification (line 2), one insertion
// (line 4), and one trailing deletion (after line 5) must paint one
// dirty-diff gutter piece of each kind in the `.cldr` lane, on those lines,
// with the editorGutter theme colors resolved.
//
// NOTE: view-line text uses non-breaking spaces, so text needles must be
// space-free.

const editor = '.monaco-editor.readonly-editor';

// The margin overlay row that holds a given gutter piece also holds the
// line number, so rows tie decorations to lines.
function rowWithPiece(page, pieceSelector) {
  return page
    .locator('.margin-view-overlays > div')
    .filter({ has: page.locator(pieceSelector) })
    .locator('.line-numbers');
}

test('quick diff: gutter shows added, modified, and deleted markers on the right lines', async ({ page }, testInfo) => {
  const reporter = await installMoonBitReporter(page);
  try {
    await page.goto('/browser-tests/quick_diff.html');
    await expect(page.locator(editor)).toContainText('bravo_changed', {
      timeout: 10_000,
    });
    const report = await reporter.waitForReport(testInfo, {
      suite: 'quick_diff',
    });
    expectMoonBitReportPassed(report, { suite: 'quick_diff' });

    const modified = page.locator(
      '.margin-view-overlays .cldr.dirty-diff-modified',
    );
    const added = page.locator('.margin-view-overlays .cldr.dirty-diff-added');
    const deleted = page.locator(
      '.margin-view-overlays .cldr.dirty-diff-deleted',
    );
    await expect(modified).toHaveCount(1);
    await expect(added).toHaveCount(1);
    await expect(deleted).toHaveCount(1);

    // Line placement: modified on 2 (bravo_changed), added on 4
    // (inserted_line), deleted pinned to 5 (the line "echo" followed).
    await expect(
      rowWithPiece(page, '.cldr.dirty-diff-modified'),
    ).toHaveText('2');
    await expect(rowWithPiece(page, '.cldr.dirty-diff-added')).toHaveText('4');
    await expect(rowWithPiece(page, '.cldr.dirty-diff-deleted')).toHaveText(
      '5',
    );

    // The dark-theme editorGutter colors resolve through the CSS variables
    // (dark_modern.json: modified #0078d4, added #2ea043).
    await expect(modified).toHaveCSS('border-left-color', 'rgb(0, 120, 212)');
    await expect(added).toHaveCSS('border-left-color', 'rgb(46, 160, 67)');
  } finally {
    reporter.dispose();
  }
});
