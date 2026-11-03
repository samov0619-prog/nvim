# Rust in CodeTools

Start Neovim inside the project's Nix/dev-shell or toolchain environment. It must
provide `cargo`, `rustc`, `rust-analyzer`, `clippy-driver` and `rustfmt`, with
`rust-src` available in that toolchain. No Rust tools are installed through Mason;
Mason directories are excluded from Rust subprocess PATHs. Rustup shims are not
resolved to their target, so the project's toolchain selection remains effective.
Restart Neovim after switching project environments.

- `<leader>cf`: rustfmt through the existing Conform/CodeTools executor.
- Formatting diagnostics: the same rustfmt executable, edition, config and cwd,
  applied to a snapshot, never to files on disk.
- Rust/Clippy diagnostics: rust-analyzer only; Clippy runs on save.
- `<leader>lca`: ordinary LSP code actions, including individual diagnostic fixes.
- The existing fix command requests `source.fixAll`; when rust-analyzer offers
  none, it reports that fact and continues with the usual formatting step. It
  never runs `cargo clippy --fix` or applies unrelated quick fixes automatically.
- `:LspExpandMacro`: preview expansion of the macro at the cursor.
- Navigation, completion and rename use the existing shared LSP integration.

Cargo metadata is asynchronous, cached, bounded to five seconds and offline. It
does not build the project or run Clippy. It supplies the workspace root and the
crate's resolved edition, including workspace inheritance and `package.workspace`.
Manifest, lockfile, Cargo-config and toolchain-file changes invalidate the cache.
If metadata is unavailable, formatting reports the error instead of guessing an
edition or using LSP formatting. Load dependencies using your normal external
Cargo workflow if offline metadata cannot resolve the project. A standalone file
without Cargo.toml uses edition 2021.

The nearest rustfmt.toml or .rustfmt.toml inside the crate/workspace context is
passed explicitly. All formatting reads stdin and returns stdout. There is no
format-on-save hook, build/run command, task runner, Rust DAP or rustaceanvim.
Build scripts and procedural macros remain enabled in rust-analyzer.

## Verification

Deterministic integration checks (no Rust toolchain required):

```fish
nvim -n --headless -u NONE -i NONE -l tests/code-rust.lua
nvim -n --headless -u NONE -i NONE -l tests/code-async.lua
```

A manual sandbox with deliberate Clippy/formatting/type errors and a
step-by-step checklist lives at `~/test-nvim-rust` (see its `README.md`).

Real-tool acceptance inside the chosen project environment:

1. Check `command -v cargo rustc rust-analyzer clippy-driver rustfmt` and
   `rustc --print sysroot`; confirm rust-src belongs to that toolchain.
2. Open a workspace member and a nested independent crate. Inspect
   `:lua vim.print(vim.lsp.get_clients({bufnr=0}))`: exactly one rust_analyzer
   should attach, rooted at the appropriate Cargo workspace.
3. Check definition, completion, rename, `<leader>lca`, and `:LspExpandMacro`,
   including a procedural macro and navigation into the standard library.
4. Save a Clippy violation. Confirm its diagnostic has a single rust-analyzer
   owner, with no Clippy invocation from nvim-lint/CodeTools.
5. Use `<leader>cf` with workspace edition inheritance and workspace/member
   rustfmt configurations; compare the result with the project's rustfmt.
6. Check the fix command with an individual diagnostic but no source.fixAll:
   it must explain the limitation, not run cargo clippy --fix.
7. Run the existing Python test with Ruff/basedpyright available, and the other
   applicable language tests. No existing language's provider policy changes.
