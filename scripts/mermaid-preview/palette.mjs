import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

export const pipeline = JSON.parse(readFileSync(new URL('./pipeline.json', import.meta.url), 'utf8'));

// Both Lua and Node fingerprint these exact bytes, including the dependency lock.
export function pipelineKey() {
  const files = ['pipeline.json', 'package-lock.json', 'render.mjs', 'palette.mjs', 'browser.mjs'];
  const hashes = files.map(file => createHash('sha256')
    .update(readFileSync(new URL(file, import.meta.url))).digest('hex'));
  return createHash('sha256').update(hashes.join('\n')).digest('hex');
}

export function themeOptions(palette) {
  if (!Array.isArray(palette) || palette.length !== 9 || !['dark', 'light'].includes(palette[0])
    || !palette.slice(1).every(color => /^#[0-9a-f]{6}$/i.test(color))) {
    throw new Error('Invalid Neovim palette');
  }
  // Wire order matches the documented palette returned by viewer.lua.
  const [mode, background, text, primary, border, line, secondary, tertiary, accent] = palette;
  return {
    backgroundColor: background,
    mermaidConfig: {
      theme: 'base', securityLevel: 'strict',
      themeVariables: {
        darkMode: mode === 'dark', background, textColor: text,
        primaryColor: primary, primaryTextColor: text, primaryBorderColor: border,
        secondaryColor: secondary, secondaryTextColor: text, secondaryBorderColor: border,
        tertiaryColor: tertiary, tertiaryTextColor: text, tertiaryBorderColor: border,
        lineColor: line, edgeLabelBackground: background, titleColor: text,
        clusterBkg: secondary, clusterBorder: border,
        noteBkgColor: tertiary, noteTextColor: text, noteBorderColor: border,
        actorBkg: primary, actorTextColor: text, actorBorder: border,
        signalColor: line, signalTextColor: text, labelBoxBkgColor: primary,
        labelBoxBorderColor: border, labelTextColor: text, activationBkgColor: secondary,
        activationBorderColor: accent,
      },
    },
  };
}

export function paletteKey(palette) {
  themeOptions(palette); // Validate before using this as a cache identity.
  return createHash('sha256').update(palette.join('\n')).digest('hex');
}

export function lookupKey(source, palette, revision = pipelineKey()) {
  return createHash('sha256').update(revision + '\n' + paletteKey(palette) + '\n' + source).digest('hex');
}
