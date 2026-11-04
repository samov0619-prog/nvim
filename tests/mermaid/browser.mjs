import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, access, rm } from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import test from 'node:test';
import { withBrowser } from '../../scripts/mermaid-preview/browser.mjs';

for (const scenario of ['success', 'render failure', 'launch failure', 'close failure',
  'SIGTERM during launch', 'SIGINT during launch', 'SIGHUP during launch',
  'SIGTERM aborts launch', 'SIGTERM during render', 'SIGTERM during output']) {
  test(scenario, async t => {
    const dir = await mkdtemp(path.join(tmpdir(), 'nvim-mermaid-browser-test-'));
    t.after(() => rm(dir, { recursive: true, force: true }));
    const profile = path.join(dir, 'profile');
    const temporary = path.join(dir, 'image.tmp');
    await mkdir(profile);
    await writeFile(temporary, 'partial PNG');
    const signals = ['SIGINT', 'SIGTERM', 'SIGHUP'];
    const listeners = signals.map(signal => process.listenerCount(signal));
    let closed = 0;
    let rejectRender;
    let rendered = false;
    const browser = { close: async () => {
      closed++;
      rejectRender?.(new Error('Browser closed'));
      if (scenario === 'close failure') throw new Error('Close failed');
    } };
    const result = withBrowser({
      profile, temporary, options: {},
      launch: async options => {
        assert.equal(options.userDataDir, profile);
        assert.equal(options.handleSIGTERM, false);
        if (scenario === 'launch failure') throw new Error('Launch failed');
        if (scenario === 'SIGTERM aborts launch') {
          return new Promise((_, reject) => {
            options.signal.addEventListener('abort', () => reject(options.signal.reason), { once: true });
            process.emit('SIGTERM');
          });
        }
        // Even a launcher that returns a browser after cancellation must be closed.
        if (scenario.endsWith('during launch')) process.emit(scenario.split(' ')[0]);
        return browser;
      },
    }, async () => {
      rendered = true;
      if (scenario === 'render failure') throw new Error('Render failed');
      if (scenario === 'SIGTERM during render') {
        return new Promise((_, reject) => { rejectRender = reject; process.emit('SIGTERM'); });
      }
      if (scenario === 'SIGTERM during output') process.emit('SIGTERM');
      return 'PNG';
    });
    if (scenario === 'success') assert.equal(await result, 'PNG');
    else if (scenario.startsWith('SIG')) {
      const expected = scenario.startsWith('SIGINT') ? 130 : scenario.startsWith('SIGHUP') ? 129 : 143;
      await assert.rejects(result, error => error.signalCode === expected);
      if (scenario.includes('launch')) assert.equal(rendered, false);
    } else await assert.rejects(result, /failed/i);
    assert.equal(closed, ['launch failure', 'SIGTERM aborts launch'].includes(scenario) ? 0 : 1);
    await assert.rejects(access(profile));
    await assert.rejects(access(temporary));
    assert.deepEqual(signals.map(signal => process.listenerCount(signal)), listeners);
  });
}
