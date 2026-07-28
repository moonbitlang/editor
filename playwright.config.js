import { defineConfig } from '@playwright/test';

const configuredBaseURL = process.env.READONLY_EDITOR_BASE_URL;
const baseURL = configuredBaseURL || 'http://127.0.0.1:5174';
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
    command: `just serve ROOT=tests/fixtures/workspace PORT=${serverPort}`,
    url: baseURL,
    reuseExistingServer: Boolean(configuredBaseURL),
    timeout: 60_000
  }
});
