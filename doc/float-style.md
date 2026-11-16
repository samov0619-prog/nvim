# Floating window style

`config.float-style` sets the public `winborder` option to
`🭽▔🭾▕🭿▁🭼▏`: thin Unicode block edges with square corners. It runs before
plugin setup. No plugin files or Neovim APIs are patched/intercepted.

Borders keep a neutral Comment foreground and match the content background.
FzfLua alone uses Normal's foreground on light surfaces for a stronger outline;
the actual RGB background is checked because the custom light Sonokai palette
can still report `background=dark`. Its dark outline remains Comment-coloured.
Regular floats use NormalFloat; FzfLua and UFO retain their Normal background;
Blink's menu retains Pmenu. Colours refresh on ColorScheme, including the
modified-buffer warning colour in MiniFiles. Trainer controls and list retain
their joined border. Font/terminal glyph support is required.

## Coverage

- Inherited: native LSP/diagnostic floats, Gitsigns popups, MiniFiles columns,
  Mason, DAP View hover/help, Blink menu/documentation.
- Explicit supported settings: FzfLua picker/preview/help, Lazy, UFO preview,
  Rust macro expansion, Mermaid's rendering float, merge-preview help,
  NvimTree's configurable float/file popup.
- Unchanged: native splits, diff styling, merge-preview column separators,
  borderless implementation/helper windows and the Mermaid image itself.
- Known exceptions: blame.nvim's commit-info/stack popups hardcode `rounded`;
  NvimTree's help hardcodes `single`. Their installed versions expose no border
  settings for those windows. Changing them would require an upstream fix or a
  workaround, deliberately not added here. Custom border arrays for native fzf
  previewers are avoided by using its supported `border-thinblock` name.

## Manual visual check

1. Restart Neovim. Press `Space ?`: check the trainer's corners and the join
   under its controls. Its appearance should match the already accepted style.
2. `Space ff`: check picker and file preview. `Space fc`: check the command
   palette and its terminal-rendered preview. `Esc` cancels without running a command.
3. `Space e`: check MiniFiles, including neighbouring columns and focused titles.
   Close with the same shortcut; no file edits are needed.
4. In a file with LSP, use `Ctrl-a` over a symbol (hover) and `Ctrl-s` at a call
   (signature). On an existing diagnostic, run `:lua vim.diagnostic.open_float()`.
   Check that neither borders nor titles have a different background strip.
5. In Insert mode type a known prefix, then `Tab` for Blink completion. Check the
   menu frame; `Ctrl-Space` can show documentation. `Esc` cancels the preview.
6. Open `:Lazy` and `:Mason`, then close each with `q`. No update/install action
   is needed. Inspect all four corners and title backgrounds.
7. In a Git file, `Space gb` checks Gitsigns line blame. `Space hp` remains an
   inline hunk preview, not a newly framed float. In an existing DAP View, `g?`
   checks its help. In an existing merge preview, `g?` checks that help as well.
8. If used, `:lua require('ufo').peekFoldedLinesUnderCursor()` over a closed fold,
   `:lua require('config.code-rust').expand_macro(0)` over a Rust macro with its
   LSP attached, and `Space rd` on a Mermaid block check the remaining previews.
   Repeat a representative picker after the usual theme change; text, selected
   rows and syntax colours should remain readable. Report any gaps or mismatched
   strips with the opening command and a screenshot.

## Automated checks

```fish
nvim -n --headless -u NONE -i NONE -l tests/float-style.lua
nvim -n --headless -u NONE -i NONE -l tests/command-palette-ui.lua
nvim -n --headless -u NONE -i NONE -l tests/completion.lua
```

These exercise real native/LSP floats, MiniFiles, Blink completion, FzfLua's
picker and builtin preview, plus theme/surface background contracts. They do not
verify terminal glyph rendering or run language servers, debug adapters, Mason
installations or a full plugin-managed startup.
