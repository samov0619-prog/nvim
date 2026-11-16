# Read-only PR/MR review

`Space gr` opens the current repository's open GitHub pull requests or GitLab
merge requests in FzfLua. Search by number, title, author or branch; the preview
shows the description. Enter fetches the selected request and opens its diff in
a new Diffview tab. Escape cancels without fetching. All list pages are loaded.

You can also use `:GitReview` or `:GitReview upstream`. If multiple remotes exist,
choose one first (for example, the upstream project rather than your fork).
Repository discovery follows the current ordinary file, otherwise Neovim's cwd.

## Requirements

- GitHub: `gh`, authenticated for the remote host (`gh auth login`).
- GitLab: `glab`, authenticated for the remote host
  (`glab auth login --hostname gitlab.com`, or your own hostname).
- Git fetch uses the selected remote's existing Git authentication, separately
  from the provider CLI's API authentication. Credentials are not managed here.
- Self-hosted GitLab: set the existing `GLBPATT` environment variable to a Lua
  pattern matching the Git remote URL. SSH aliases use OpenSSH's local `ssh -G`
  HostName resolution, just like copied Git links. Unknown hosts are rejected.

Neither CLI is installed or authenticated automatically. GitHub Enterprise is
not currently detected. API calls and fetch run asynchronously with a one-minute
timeout per command; authentication errors are reported, not retried silently.

## What changes, and what does not

- No checkout, stash, branch creation, index changes, worktree writes or buffer
  saves. Reviewing is safe with staged, unstaged and unsaved edits.
- The list and description use read-only API calls. Selecting a request fetches
  its target branch and head into `refs/nvim-review/<remote-hash>/<id>/{base,head}`.
  These private cached refs and downloaded objects persist in `.git` for reuse;
  this is not a zero-write operation. FETCH_HEAD, tags, normal remote-tracking
  refs and submodules are untouched. No automatic cache deletion is performed.
- Diffview receives immutable merge-base and head commit IDs. Both sides are
  historical, nonmodifiable buffers, even when one commit equals local HEAD.
  The base is calculated from the freshly fetched target branch; a missing
  common ancestor (for example, a shallow clone) reports an error, not a diff
  against local files. Existing review tabs do not move when another fetch runs.
- Bulk stage/unstage (`S`/`U`) is blocked in these tabs; ordinary Diffview keeps
  its existing behavior. This is a read-only review UI, not a Neovim sandbox:
  explicitly jumping to a working file with `gf`, issuing shell commands or
  calling plugin actions manually is outside this guarantee.
- If you change tabs while fetch is running, it does not steal focus to open
  the diff; select the request again. No code from the request is checked out or
  executed. Review comments and approval remain on GitHub/GitLab.

## Manual acceptance

1. Restart Neovim with this configuration. In a repository with existing local
   edits (including one staged change and an unsaved buffer), press `Space gr`.
2. Choose the intended remote if prompted. Confirm titles/authors/branches are
   searchable and the description is visible. Escape: no fetch or new diff tab.
3. Reopen and select an open PR/MR, including one from a fork. Expect a Diffview
   tab showing only changes since its merge base with the target branch.
4. Confirm both diff buffers are nonmodifiable (`:setlocal modifiable?`), and
   `S`/`U` in the file panel reports read-only. Close with `:DiffviewClose`.
5. Confirm your branch, `git status --short`, staged diff and unsaved buffer are
   unchanged. Repeat on GitLab after installing/authenticating `glab`.

Local regression tests (no network, provider responses/fetch mocked):

```fish
nvim -n --headless -u NONE -i NONE -l /home/samov/.config/nvim/tests/git-review.lua
```
