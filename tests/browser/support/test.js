import { expect, test as base } from '@playwright/test';
import { createTestLogger, installPageLogging, withLoggedOperation } from './logger.js';

export { expect };

export const test = base.extend({
  page: async ({ page }, use, testInfo) => {
    const logger = createTestLogger(testInfo);
    const removePageLogging = installPageLogging(page, logger);
    const started = Date.now();
    logger.log({
      level: 'info',
      category: 'test',
      message: 'start',
      details: { title: testInfo.title },
    });
    try {
      await withLoggedOperation(logger, 'test', 'body', () => use(page));
      logger.log({
        level: 'info',
        category: 'test',
        message: 'end',
        details: {
          title: testInfo.title,
          durationMs: String(Date.now() - started),
        },
      });
    } catch (error) {
      const screenshotPath = testInfo.outputPath('failure.png');
      await page.screenshot({ path: screenshotPath, fullPage: true }).catch(() => {});
      await testInfo.attach('failure screenshot', {
        path: screenshotPath,
        contentType: 'image/png',
      }).catch(() => {});
      logger.log({
        level: 'error',
        category: 'test',
        message: 'failed',
        details: {
          title: testInfo.title,
          durationMs: String(Date.now() - started),
          error: error?.message || String(error),
        },
      });
      throw error;
    } finally {
      removePageLogging();
      logger.flush();
    }
  },
});
