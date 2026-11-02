# Deletion

### An agent removes what it made with rm, and trashes what it did not

**What an agent made itself it removes with `rm`**: its files in the scratchpad and temp, a test's
leftovers, a lane it opened, build output and caches, **a cache with a clean of its own by that
clean**, as `cargo clean`. **What it did not make goes to `/usr/bin/trash`**, files and directories
alike: the author's files and untracked files that were already in a repository, since those may be
wanted back. The line is who made it, not where it lies: an agent detouring to `trash` for its own
scratch costs turns and fills `~/.Trash`, and one using `rm` on the author's file loses what cannot
be put back. `rm` meets a guard that allows it only inside the workspace, temp and caches -- see "rm
is guarded, not banned" below.

**Key material a program generated is the one deletion that must not be recoverable**, and is
removed with `rm` once it has been entered as a secret: `trash` keeps a copy in `~/.Trash`, and a
private key that can be put back is a private key that is still there. It is made under the
scratchpad, inside the temp directories the guard allows, so the `rm` is never one the guard
refuses.

**An `rm` never takes a bare variable path**: each variable is written `"${S:?}"/name`, or the path
is written out, so an empty variable stops the command rather than removing from the root,
`rm-variable-guarded` in [model/rules/toolchain.res](../../model/rules/toolchain.res).

Where the point is only to get something out of the way, moving it to a temporary directory answers
just as well and reads more honestly than a deletion.

The rule covers commands an agent types. What a tool does inside itself is the tool's -- `mise run
clean` removing what a build wrote is that task's business, and nothing here reaches into it. **A
program removes the temporary files it made itself, with `Node.rmSync`**, never by calling `trash`,
which a runner does not have.

The cost is small and worth stating so nobody is surprised by it: the bytes go to the Finder's trash
instead of being unlinked, so the space is not returned until the trash is emptied, and what was
deleted is recoverable until then.

### rm is guarded, not banned

An agent's `rm` is `hooks/bin/rm`, put first on PATH by `mise.toml` and judging every operand after
the shell has expanded it. That is the whole reason it is a shim rather than a pattern over the
command text: `rm -rf "$DIR/"` with an empty `DIR` reaches it as `/`, which no reading of the text
could have seen.

- **Inside the whitelist it is the real `/bin/rm`, with no question asked**: the workspace and every
  repository under it, `/tmp` (where the harness scratchpad lives) and `$TMPDIR`, and the caches --
  `~/Library/Caches`, `~/.cache`, `~/.npm`, `~/.bun/install/cache`, `~/.cargo/registry`,
  `~/.cargo/git`, `~/Library/pnpm/store`, Xcode's `DerivedData`; and
  `~/.local/share/monoflake/reset`, where monoflake/cloud's reset keeps the key copies it makes for
  a machine and removes with `rm` once the machine holds them, its docs/upgrades.md.
- **Refused outright**, with a hint that a variable is probably empty: an empty operand, `/`,
  `/Users`, the home directory, another user's, a whitelisted root itself, `repos/` and each
  repository root under it, and anything inside a `.jj` or `.git` store.
- **Refused with a pointer to `trash`**: the user's own files -- `Desktop`, `Documents`,
  `Downloads`, `Movies`, `Music`, `Pictures`, `Public`, iCloud's `Mobile Documents` -- and
  everywhere else outside the whitelist.
- **One refused operand deletes nothing**, including the operands that would have passed. Paths
  compare case-insensitively, because APFS does.

Outside an agent the shim execs `/bin/rm` untouched, so the user's own shell never meets it; an
agent is recognized by `CLAUDECODE`, `AI_AGENT` or a `CODEX_` variable. Only `/bin/rm` by its
absolute path skips the shim, which is why that alone is on the harness's ask list. The policy is
`hooks/rm_guard.py` and its tests run under `check workspace hooks`.

The shim reaches an agent only through the environment mise gave the shell that launched it -- a
harness started outside mise runs the plain `rm`.
