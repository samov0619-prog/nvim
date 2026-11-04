import { rm } from 'node:fs/promises';

// Own cancellation in one place. Never exit before launch/render and cleanup settle.
export async function withBrowser({ launch, options, profile, temporary }, render) {
  const controller = new AbortController();
  let browser;
  let closing;
  const close = () => {
    if (!browser) return Promise.resolve();
    return closing ??= Promise.resolve().then(() => browser.close());
  };
  const handlers = new Map();
  for (const [signal, code] of [['SIGINT', 130], ['SIGTERM', 143], ['SIGHUP', 129]]) {
    const handler = () => {
      const error = new Error(`Rendering cancelled by ${signal}`);
      error.signalCode = code;
      controller.abort(error);
      void close().catch(() => {}); // The awaited cleanup below reports failures.
    };
    handlers.set(signal, handler);
    process.on(signal, handler);
  }
  try {
    browser = await launch({
      ...options, userDataDir: profile, signal: controller.signal,
      handleSIGINT: false, handleSIGTERM: false, handleSIGHUP: false,
    });
    controller.signal.throwIfAborted();
    const result = await render(browser, controller.signal);
    controller.signal.throwIfAborted();
    return result;
  } catch (error) {
    throw controller.signal.aborted ? controller.signal.reason : error;
  } finally {
    try {
      await close();
    } finally {
      try {
        await rm(profile, { recursive: true, force: true });
      } finally {
        try {
          await rm(temporary, { force: true });
        } finally {
          for (const [signal, handler] of handlers) process.off(signal, handler);
        }
      }
    }
  }
}
