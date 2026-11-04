// One-shot official renderer. No browser is retained after rendering.
import { readFile, mkdir, access, rename, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { lookupKey, pipeline, pipelineKey, themeOptions } from './palette.mjs';
import { withBrowser } from './browser.mjs';

async function main() {
  const input = process.argv[2];
  if (!input) throw new Error('Usage: node render.mjs source.mmd [--theme-file palette.json] [--force]');
  const storage = process.env.MERMAID_DATA_DIR;
  if (!storage) throw new Error('MERMAID_DATA_DIR is missing; launch through :MermaidPreview');
  const runtime = path.join(storage, 'runtime');
  const started = performance.now();
  const source = await readFile(input, 'utf8');
  const themeArg = process.argv.indexOf('--theme-file');
  const palette = themeArg === -1 ? null : JSON.parse(await readFile(process.argv[themeArg + 1], 'utf8'));
  const options = {
    size: pipeline.size, viewport: pipeline.viewport,
    backgroundColor: '#1e1e2e',
    mermaidConfig: { theme: 'dark', securityLevel: 'strict' },
    ...(palette ? themeOptions(palette) : {}),
  };
  const revision = pipelineKey();
  const key = createHash('sha256').update(JSON.stringify({ source, options, revision })).digest('hex');
  const output = path.join(storage, 'cache', key + '.png');
  await mkdir(path.dirname(output), { recursive: true });
  let hit = false;
  try { await access(output); hit = !process.argv.includes('--force'); } catch {}
  if (!hit) {
    const { default: puppeteer } = await import(pathToFileURL(path.join(runtime, 'node_modules/puppeteer/lib/puppeteer/puppeteer.js')));
    const { renderMermaid } = await import(pathToFileURL(path.join(runtime, 'node_modules/@mermaid-js/mermaid-cli/src/index.js')));
    const temporary = output + `.${process.pid}.tmp`;
    await withBrowser({
      launch: options => puppeteer.launch(options),
      options: { executablePath: process.env.MERMAID_CHROMIUM || path.join(storage, 'chromium/bin/chromium'),
        headless: true, timeout: 30000 },
      profile: path.join(storage, `profile-${process.pid}`), temporary,
    }, async (browser, signal) => {
      const { data } = await renderMermaid(browser, source, 'png', options);
      signal.throwIfAborted();
      await writeFile(temporary, data, { mode: 0o600 });
      signal.throwIfAborted();
      await rename(temporary, output);
    });
  }
  // The Lua viewer checks this small sidecar without launching Node on a hit.
  const lookup = palette ? lookupKey(source, palette, revision)
    : createHash('sha256').update(revision + '\n' + source).digest('hex');
  await mkdir(path.join(storage, 'lookup'), { recursive: true });
  await writeFile(path.join(storage, 'lookup', lookup + '.json'), JSON.stringify({ output }));
  console.log(JSON.stringify({ output, cached: hit, ms: performance.now() - started }));
}

try {
  await main();
} catch (error) {
  if (!error.signalCode) throw error;
  process.exitCode = error.signalCode;
}
