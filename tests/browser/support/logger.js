import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

export class FileLogger {
  constructor(path) {
    this.path = path;
    mkdirSync(dirname(path), { recursive: true });
    appendFileSync(this.path, '', 'utf8');
  }

  log(entry) {
    appendFileSync(this.path, `${JSON.stringify(entry)}\n`, 'utf8');
  }

  flush() {}
}

export class ConsoleLogger {
  constructor(enabled) {
    this.enabled = enabled;
  }

  log(entry) {
    if (this.enabled) {
      console.log(`[browser-test] ${entry.level} ${entry.category}: ${entry.message}`);
    }
  }

  flush() {}
}

export class MultiLogger {
  constructor(loggers) {
    this.loggers = loggers;
  }

  log(entry) {
    for (const logger of this.loggers) {
      logger.log(entry);
    }
  }

  flush() {
    for (const logger of this.loggers) {
      logger.flush();
    }
  }
}

export function createTestLogger(testInfo) {
  const verbose = process.env.READONLY_EDITOR_TEST_VERBOSE === '1' ||
    process.env.PW_VERBOSE === '1';
  return new MultiLogger([
    new FileLogger(testInfo.outputPath('runner.log')),
    new ConsoleLogger(verbose),
  ]);
}

export async function withLoggedOperation(logger, category, message, operation) {
  const started = Date.now();
  logger.log({ level: 'info', category, message: `${message}:start`, details: {} });
  try {
    const result = await operation();
    logger.log({
      level: 'info',
      category,
      message: `${message}:end`,
      details: { durationMs: String(Date.now() - started) },
    });
    return result;
  } catch (error) {
    logger.log({
      level: 'error',
      category,
      message: `${message}:error`,
      details: {
        durationMs: String(Date.now() - started),
        error: error?.message || String(error),
      },
    });
    throw error;
  }
}

export function installPageLogging(page, logger) {
  const onConsole = (message) => {
    logger.log({
      level: consoleLevel(message.type()),
      category: 'browser.console',
      message: message.text(),
      details: { type: message.type(), location: JSON.stringify(message.location()) },
    });
  };
  const onPageError = (error) => {
    logger.log({
      level: 'error',
      category: 'browser.pageError',
      message: error?.message || String(error),
      details: { stack: error?.stack || '' },
    });
  };
  const onRequestFailed = (request) => {
    logger.log({
      level: 'warning',
      category: 'browser.requestFailed',
      message: request.url(),
      details: {
        method: request.method(),
        failure: request.failure()?.errorText || '',
      },
    });
  };
  const onResponse = (response) => {
    if (response.status() >= 400) {
      logger.log({
        level: 'warning',
        category: 'browser.http',
        message: response.url(),
        details: { status: String(response.status()) },
      });
    }
  };
  page.on('console', onConsole);
  page.on('pageerror', onPageError);
  page.on('requestfailed', onRequestFailed);
  page.on('response', onResponse);
  return () => {
    page.off('console', onConsole);
    page.off('pageerror', onPageError);
    page.off('requestfailed', onRequestFailed);
    page.off('response', onResponse);
  };
}

function consoleLevel(type) {
  if (type === 'error') {
    return 'error';
  }
  if (type === 'warning') {
    return 'warning';
  }
  return 'info';
}
