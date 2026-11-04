import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, writeFile, readFile, rm, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { pipeline, pipelineKey, lookupKey, themeOptions } from '../../scripts/mermaid-preview/palette.mjs';

test('worker resolves persistent cache paths without a browser or installed runtime', async t => {
  const dir = await mkdtemp(path.join(tmpdir(), 'nvim-mermaid-worker-test-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const source = 'flowchart LR\nA[Привет] --> B\n';
  const palette = ['light', '#ffffff', '#111111', '#eeeeee', '#777777', '#111111', '#dddddd', '#cccccc', '#123456'];
  const options = { size: pipeline.size, viewport: pipeline.viewport, ...themeOptions(palette) };
  const revision = pipelineKey();
  const key = createHash('sha256').update(JSON.stringify({ source, options, revision })).digest('hex');
  const output = path.join(dir, 'cache', key + '.png');
  const input = path.join(dir, 'source.mmd');
  const theme = path.join(dir, 'theme.json');
  await mkdir(path.dirname(output));
  await writeFile(output, 'cached image fixture');
  await writeFile(input, source);
  await writeFile(theme, JSON.stringify(palette));
  const worker = fileURLToPath(new URL('../../scripts/mermaid-preview/render.mjs', import.meta.url));
  const result = spawnSync(process.execPath, [worker, input, '--theme-file', theme], {
    encoding: 'utf8', timeout: 5000,
    env: { ...process.env, MERMAID_DATA_DIR: dir, MERMAID_CHROMIUM: '/nonexistent/chromium' },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  const data = JSON.parse(result.stdout);
  assert.equal(data.output, output);
  assert.equal(data.cached, true);
  const lookup = path.join(dir, 'lookup', lookupKey(source, palette) + '.json');
  assert.deepEqual(JSON.parse(await readFile(lookup, 'utf8')), { output });
  await assert.rejects(access(path.join(dir, 'runtime')));
});
