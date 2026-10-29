# TypeScript / Vue LSP

`ts_ls` remains the TypeScript server wrapper. Vue support uses the official
`@vue/typescript-plugin`, `vue_ls`, and nvim-lspconfig's built-in request bridge.
There are no language-service patches and no project dependency/config rewrites.

## Mason packages and updates

| Mason package | Purpose | Update policy |
| --- | --- | --- |
| `typescript-language-server` | Current stable `ts_ls` wrapper | Standard Mason registry |
| `vue-language-server` | Current stable Vue 3 tools | Standard Mason registry |
| `vue-language-server-vue2` | Official legacy Vue tools | Local registry, pinned to 3.0.11 |

The legacy recipe is `lua/config/mason-registry/vue-language-server-vue2.lua`.
It installs server and plugin at the same exact version, plus technical
TypeScript 6.0.3. Its binary is named `vue-language-server-vue2`, so it cannot
overwrite the current server's binary. Mason installs missing packages at startup;
the resolver never installs or updates language-server packages on file open.

Use `:MasonUpdate` to refresh registry metadata, then `U` in `:Mason` to update
outdated packages. The legacy package stays at the version in its local recipe,
not npm's `latest`. Restart affected LSP clients after updates (`<leader>lrs`).

The upstream [Vue 2 policy](https://github.com/vuejs/language-tools/discussions/5455)
allows critical fixes to be backported to 3.0.x; it is not a general LTS guarantee.
Monitor the npm `v3.0` tag. When a new patch is tested, change the single `version`
in the local recipe and restart Neovim: Mason's `U` will then offer that version.
Do not change the recipe to 3.1+ (Vue 2/class-component support was removed).

Mason receipts record installed versions, but this is not an npm lockfile-based
reproducible environment. `lazy-lock.json` only pins Neovim plugins. The resolver
uses the Vue server's own matching plugin dependency preferentially and rejects
server/plugin version mismatches rather than silently using a different plugin.

## Selection

`lua/config/ts-toolchain.lua` resolves tools before starting/reusing a client:

1. Use a matching local profile override, if present (longest path wins).
2. Otherwise use the actual installed Vue version: Vue 2 → `vue2`, Vue 3 → `vue3`.
   Do not guess the installed version from a dependency range.
3. Prefer the project's installed TypeScript SDK, including hoisted/pnpm symlinks.
4. If no project TypeScript dependency/installation exists, use Mason's technical
   TypeScript (currently 6.0.3). This also supports JavaScript-only projects.

Discovery stops at the Git/worktree boundary. Without Git, a package-manager
lockfile identifies the workspace; otherwise discovery stops at the nearest
package. Each package uses its own client root. Different Vue profiles or SDKs
cannot reuse one another's clients; multiple files in the same package can.
Ordinary JS/TS packages without Vue run `ts_ls` without the Vue plugin. Deno
projects and non-file/UI buffers are excluded.

Declared-but-missing dependencies, mismatched Vue tools, and TypeScript 7 do not
silently fall back to an unrelated installation. A warning explains what to fix.
`ts_ls` needs a usable `lib/tsserver.js` and TypeScript below 7. For Vue integration,
this configuration requires TS 5/6: a real Vue 2 + TS 4.9.5 test loaded the plugin
but lost template types to `any` (Volar's current module resolver expects TS 5's
arbitrary extension resolution). Older build TypeScript is left unchanged; an
editor-only SDK must be selected explicitly with `tsdk`. Vue 2 + editor TS 5.9.3
and Vue 3 + project TS 5.9.3 are covered by integration tests. These bounds are
not a promise of compatibility with every release. Node must satisfy the installed
wrapper's requirements (6.0.2 requires Node >=22.22.2).

There is no need to check project versions manually: an incompatible SDK produces
one warning per project with an editor-only TS 5.9.3 installation command, the
absolute override-file path, and a ready-to-merge JSON entry for that project.
The suggested SDK lives under Neovim's data directory, outside project dependencies;
the configuration never installs it or switches to it without that explicit entry.

## Optional overrides

Create `ts-toolchains.local.json` in the Neovim configuration directory. It is
ignored by Git and is never loaded from or executed inside a project:

```json
{
  "/absolute/path/to/legacy-app": {
    "profile": "vue2",
    "tsdk": "/absolute/path/to/tested/typescript-5.9/lib"
  },
  "/absolute/path/to/workspace/packages/current-app": {
    "profile": "vue3"
  },
  "/absolute/path/to/special-project": {
    "tsdk": "/absolute/path/to/tested/typescript/lib"
  },
  "/absolute/path/to/plain-package": {
    "profile": "none"
  }
}
```

`profile` and `tsdk` are independently optional. `tsdk` also accepts the absolute
path to `lib/tsserver.js` (not `node_modules/.bin/tsserver`). An explicit SDK is
useful for Yarn PnP's generated SDK or for a deliberately different editor SDK;
it does not change the build's TypeScript. More-specific entries replace broader
entries rather than inheriting their fields. Vue 3 class-component projects may
also need the legacy toolchain explicitly; verify their compatibility separately.

Restart clients after changing profiles, SDKs or dependency installations. The
selected project SDK is passed to `ts_ls` via `tsserver.path`. The separate
`vue_ls` process uses its own Mason installation's technical TypeScript via
`--tsdk`: Vue tools 3.0.11 need APIs absent from TS 4.9's `typescript.js`. This
does not replace the project's `tsserver` or its build TypeScript. Both SDKs are
visible in `:TsToolchainInfo`. Existing `tsconfig` / `jsconfig` / `vueCompilerOptions` remain
authoritative; editor profile selection does not rewrite them.

## Verification

1. Restart Neovim and check the three packages in `:Mason` (if necessary run
   `:MasonInstall typescript-language-server vue-language-server vue-language-server-vue2`).
2. Open a Vue 2 and a Vue 3 project. Run `:TsToolchainInfo` in each: check profile,
   tool versions, SDK path/version and `actual_typescript` reported by `ts_ls`.
   `source = user-setting` is expected because the resolver explicitly supplies
   the selected project SDK; `ts_source` explains where it was found.
3. Check template/script completion, hover, definitions, rename and unsaved type
   errors. In one Neovim instance, each project must have its own pair of clients,
   with `matches = true`; a plain JS/TS project should have only `ts_ls`.

Automated tests:

```fish
nvim -n --headless -u NONE -i NONE -l tests/ts-toolchain.lua
```

`tests/ts-vue-lsp.lua` additionally checks real Vue 2/3 servers together. Its header
documents fixture dependency installation under `/tmp/opencode` and the Fish
environment variable needed to run it. These tests do not use working projects.
They do not promise WebStorm feature parity or solve the separate cyclic `chat`
TypeScript inference case.
