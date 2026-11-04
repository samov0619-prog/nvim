import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { lookupKey, paletteKey, pipelineKey, themeOptions } from '../../scripts/mermaid-preview/palette.mjs';

const dark = ['dark', '#222222', '#eeeeee', '#333333', '#888888', '#eeeeee', '#444444', '#555555', '#abcdef'];
const light = ['light', '#ffffff', '#111111', '#eeeeee', '#777777', '#111111', '#dddddd', '#cccccc', '#123456'];
const source = 'flowchart LR\nA[Привет] --> B\n';
for (const palette of [dark, light]) {
  const options = themeOptions(palette);
  assert.equal(options.backgroundColor, palette[1]);
  assert.equal(options.mermaidConfig.theme, 'base');
  assert.equal(options.mermaidConfig.themeVariables.darkMode, palette[0] === 'dark');
  assert.equal(options.mermaidConfig.themeVariables.primaryTextColor, palette[2]);
  const result = spawnSync('nvim', ['-n', '--headless', '-u', 'NONE', '-i', 'NONE', '-l',
    fileURLToPath(new URL('./palette-key.lua', import.meta.url))], {
    encoding: 'utf8', env: { ...process.env, MERMAID_TEST_PALETTE: JSON.stringify(palette), MERMAID_TEST_SOURCE: source },
  });
  assert.equal(result.status, 0, result.stderr);
  const lua = JSON.parse(result.stdout);
  assert.equal(lua.pipeline, pipelineKey());
  assert.equal(lua.palette, paletteKey(palette));
  assert.equal(lua.lookup, lookupKey(source, palette));
}
assert.notEqual(lookupKey(source, dark), lookupKey(source, light));
assert.notEqual(lookupKey(source, dark, 'before upgrade'), lookupKey(source, dark, 'after upgrade'));
assert.throws(() => themeOptions(['dark']), /Invalid/);
console.log('PASS: official theme options and identical Lua/Node palette-aware cache keys');
