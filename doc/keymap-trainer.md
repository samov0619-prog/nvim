# Keymap learning panel

The panel starts hidden. `Space ?` in Normal/Visual shows or hides it. This
session-wide preference survives buffer/mode/context changes until explicitly
toggled again. Plugin windows are excluded; when enabled, the panel returns in
eligible source buffers after leaving a plugin window.

## Controls

- The single top switch alternates **Учить** (`unknown` + `learning`) and
  **Помню** (`known`). The top bar contains only this switch and close.
- All matching categories are shown together in a single column with section
  headings. There are no category tabs or pages. Headings scroll with the list;
  the progress switch and close control stay fixed.
- Scroll over the list with the mouse wheel, without changing editor focus.
- **×** hides the panel.
- Releasing a click anywhere in the list returns to the editor too, including
  double/triple clicks. All help windows are excluded from keyboard window traversal.
- Local `q` remains a fallback when the help window is entered programmatically.
- Active controls use neutral bold/underlined text, not a coloured background.
- No hover tracking or global mouse mappings are installed.

The list wraps long descriptions. Motion-based commands follow simpler actions
within each section. Height follows the actual wrapped screen rows, measured
with `nvim_win_text_height()`, up to the available screen height. Overflow uses
native scrolling, not pagination. The one-line controls and list share a border.
Only this panel uses a thin-block Unicode outline (`🭽▔🭾▕🭿▁🭼▏`) with square
corners at the outer cell edges. Rendering depends on font/terminal support for
Symbols for Legacy Computing. The border uses the neutral `Comment` foreground
but the same `NormalFloat` background as the content/title, also after theme changes.
Other float windows now use the same border through `config.float-style`;
see `doc/float-style.md` for coverage, exceptions and manual checks.
The panel stays inset from the upper-right edges and hides on very small screens.
Active diff windows, including readonly virtual revisions, show only diff actions
under one `Diff` heading. Empty mode/progress selections show an empty-state message.
Help windows explicitly disable `diff`, `scrollbind` and `cursorbind` so they do
not join comparisons or move the source view.
Closing one of the panel's component windows hides the whole panel; `Space ?`
restores it. A manually hidden panel stays hidden across context changes.

## Progress

Data comes from `~/scratch/mappings-tbl/mapping-progress.json`, in the version-1
`nvim-keymap-progress` format exported by `mono.html`. The initial file is a copy
of the user's existing browser export; Neovim never writes progress.

After updating progress in the browser:

1. Save the exported JSON as `~/scratch/mappings-tbl/mapping-progress.json`.
2. Run `:KeymapTrainer reload`. Returning focus to Neovim also reloads the file
   when the terminal/GUI reports focus events.

Invalid reloads retain the previous valid catalogue and report a warning.
Context filters use modes, filetypes, repository discovery, LSP/Gitsigns attachment
and loaded DAP configurations; they do not probe external tools or launch servers.
The browser's “Согласованные назначения” group is redistributed into actual topics.

## Visibility and sections

```text
Current editor window
  |
  +-- Floating window? --------------------------------------> Hide
  +-- Special buffer other than terminal, without diff? -----> Hide
  +-- Not explicitly enabled with Space ? / show? -----------> Hide
  +-- Screen below 48 columns or 18 lines / insufficient room? -> Hide
  |
  v
Filter catalogue by current mode and progress view
  |
  +-- Active native window diff?
  |     Yes: keep only [c, ]c, Space dc/dg/dp/do; group as Diff
  |     No: apply the ordinary context rules below
  |
  v
Show all surviving categories as sections, in fixed order
  |
  +-- Enough room? Fit height to wrapped content
  +-- Too many rows? Cap height above the bottom inset; scroll
  +-- No entries? Keep the panel with an empty message
```

Trainer-window interactions reuse the source context rather than treating the
trainer itself as a new editor window. Other plugin interfaces are excluded by
window/buffer type, not by a plugin-name blacklist. Thus Diffview's file diff
windows qualify, but its special file-list buffer does not. A Gitsigns revision
qualifies while its window has `diff`; after the last comparison closes and
Neovim removes `diff`, a remaining special revision buffer no longer qualifies.

Outside diff, category order and rules are:

| Category | Conditions after mode/progress filtering |
| --- | --- |
| Общее | No additional category-wide condition. Mermaid preview (`Space rd`) is omitted because it already provides its own hints; the actual mapping and browser catalogue are unchanged. |
| Поиск | No additional context condition. |
| Git | A `.git` root must be discoverable from the file/cwd, except for `[c`/`]c`. Hunk actions (`Space h…`) and line blame (`Space gb`) also require the buffer's Gitsigns attachment marker. `[c`/`]c` require only that marker (or diff, where they instead appear under `Diff`). |
| Diff | Outside diff, only `Space do` remains as the entry point. |
| Правки | Buffer must be modifiable. |
| LSP | At least one LSP client must be attached to the buffer. |
| Ввод | No extra context condition; entries are separated by their Insert/command-line modes. |
| Логи | Modifiable buffer with filetype `javascript`, `javascriptreact`, `typescript`, `typescriptreact`, `vue`, `astro`, or `lua`. |
| Отладка | Modifiable buffer; DAP already loaded. While DAP View is visible in the current tab, show debugger controls. Otherwise only `F5`, and only with a nonempty configuration list for this filetype or an existing session. Breakpoint hints also require DAP View. |

In a terminal, outside command-line mode, only catalogue entries for `Alt-…`
window navigation and `Space tc` are eligible, still subject to mode/progress.
Command-line mode uses the ordinary rules. In diff, the diff-only rule takes
precedence: unrelated categories never return merely because the current mode
has no diff entries. The current six diff entries are all Normal-mode entries.

**Учить** combines `unknown` and `learning`; **Помню** uses only `known`.
Switching views can therefore change which sections exist. The category order is
fixed; it is not sorted by frequency or progress. Within a section, catalogue
order is preserved except that motion-based actions go last.

Manual hiding (`Space ?`, close control, or closing a component window) disables
the panel for the session until `Space ?` / `:KeymapTrainer show` is used again.
New buffers, modes, tabs, DAP View opening, progress reloads and resizing do not enable it.
Automatic exclusion in a plugin window or on a small screen does not itself
disable an enabled panel; it can return when the context qualifies.
An enabled panel follows the current tab: its two windows close on tab departure
and are recreated in the next eligible context without taking focus. Switching
or closing tabs does not count as manually closing a component.

DAP View detection uses its documented `dap-view` filetype in the current tab.
Its integrated `dap-repl` is recognized by the documented window-local
`dapview_win` marker (see `:help dap-view-dynamic-layout`), not private plugin state.
A standalone DAP REPL, a loaded module, or DAP View in another tab is insufficient.
The trainer does not cover the DAP View pane itself; its debugger hints appear
in eligible source windows while that pane is open. No adapter is launched by
context detection, and no DAP mappings are changed.

Refreshes follow buffer/window/tab entry, window closing, mode/filetype changes, LSP attachment,
diff option changes, GitSigns updates, cwd changes, resizing, and explicit panel
commands. A modifiability change is recognized at the next refresh, not by a
dedicated option-change handler. Focus events can reload progress as described
above. These rules filter hints only: they do not add/remove actual mappings or
guarantee a command will succeed (e.g. `diffget` still needs a writable target).

## Commands

`:KeymapTrainer` toggles the panel. Optional arguments:
`toggle`, `show`, `hide`, `reload`, `learn`, `known`, `up`, `down`.

The module is configured at the end of `init.lua`:

```lua
require('config.keymap-trainer').setup()
```

Optional setup fields are `path` (another exported JSON file) and `keymap = false`
(commands and mouse only). The default shortcut does not replace an existing map.

## Tests

```fish
nvim -n --headless -u NONE -i NONE -l tests/keymap-trainer.lua
nvim -n --headless -u NONE -i NONE -l tests/keymap-trainer-dap.lua
```

Tests exercise real Neovim floats, mouse input, scrolling, selection preservation,
mode changes, visibility, reload validation and screen resizing. LSP/Gitsigns
attachment checks use fixtures, not real language servers or plugin attachment.
Diff tests check the actual rendered sections for writable/readonly windows, both
progress views, empty modes and restoration outside diff; native diff fixtures
do not launch Diffview itself.
DAP tests open/close the installed DAP View, distinguish integrated/standalone
REPLs, and check current-tab rendering, launch-only fallback and explicit visibility.
Layout tests also cover tab switching/closing and hidden preference across tabs.
No debug adapter/session is started by these tests. Layout tests cover fit-to-content, wrapped reflow,
screen-height overflow and native mouse scrolling.
