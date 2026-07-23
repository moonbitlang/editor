import { defineConfig } from '@playwright/test';

const baseURL = process.env.READONLY_EDITOR_BASE_URL || 'http://127.0.0.1:5173';
const serverPort = new URL(baseURL).port || '5173';

export default defineConfig({
  testDir: 'tests/browser',
  outputDir: 'test-results/browser',
  timeout: 30_000,
  workers: 1,
  use: {
    baseURL,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure'
  },
  webServer: {
    command: `just dev ROOT=tests/fixtures/workspace PORT=${serverPort}`,
    url: `http://127.0.0.1:${serverPort}`,
    reuseExistingServer: true,
    timeout: 60_000
  }
});
