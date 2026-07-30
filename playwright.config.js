import { defineConfig } from '@playwright/test';

const configuredBaseURL = process.env.READONLY_EDITOR_BASE_URL;
const baseURL = configuredBaseURL || 'http://127.0.0.1:5174';
const serverPort = new URL(baseURL).port || '5173';

// The webServer readiness probe honors proxy environment variables; a local
// HTTP proxy answering for the loopback port makes Playwright report it as
// already in use before the server even starts.
const loopback = ['127.0.0.1', 'localhost'];
for (const name of ['NO_PROXY', 'no_proxy']) {
  process.env[name] = [process.env[name], ...loopback].filter(Boolean).join(',');
}

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
    command: `just ROOT=tests/fixtures/workspace PORT=${serverPort} serve`,
    url: baseURL,
    reuseExistingServer: Boolean(configuredBaseURL),
    timeout: 60_000
  }
});
