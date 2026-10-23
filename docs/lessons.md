# Lessons

What an agent working here learned the hard way, each the habit it left and what happened. They
were kept in agent memory once; the author asked on 2026-10-20 that they stand here, where every
agent reads them. Agent memory keeps only what is private and the state of work in progress --
[agent-protocol.md](agent-protocol.md), "Selfcheck". A lesson a program can come to decide moves
into `model/rules/` with its check and leaves this file.

## Commits

- **The co-author trailer names the model running now**: `Claude <Model>-<Version>`, read from
  the session's own system prompt, never copied from a handover, a memory or an earlier commit,
  and never passed through a shell variable, which the commit hook reads unexpanded. On
  2026-09-04 a seam commit named the model a handover had named; on 2026-10-07 a day of commits
  carried `(1M context)` through `$T`.
- **A check and a commit are two calls.** The verify gate judges a command before any of it runs,
  so `mise run check && jj commit` is refused however the check ends. A check's status is read
  before anything outward, never through a pipe -- `check | tail && commit` takes `tail`'s -- and
  never past a `;`: on 2026-10-05 and 2026-10-07 failing trees were pushed that way. An edit sent
  in the commit's own call is judged by the stamp from before it, so the gate lets it through: on
  2026-10-22 a platform commit passed so, its check having failed past a `;`.
- **A commit by path can void the stamp.** `jj commit <paths>` runs the hook's `jj fix`, which may
  reformat what it commits, so the tree left is no longer the one that passed: check again before
  the next commit. Seen on 2026-10-20.
- **A check can void its own stamp.** A crate added to a workspace's members is written into
  `Cargo.lock` by the cargo the check runs, so the tree it leaves is not the one it passed: on
  2026-10-20 a commit after it was refused. A check after a change of members runs twice.
- **A worker sent a message is working again until it says it is idle.** Its report done, a
  question answered still sets it editing, so its repository is committed only after its last
  idle: on 2026-10-23 a test it added after answering was swept into a docs commit beside it.
- **No check runs while a worker builds.** A check builds every block, and two builds of one
  ReScript package at once collide on its lock, failing whichever started second, so the
  conversation's checks and commits wait until the wave has returned.
- **Each commit is its own call, alone in its message, opened by `jj root &&`.** Calls sent in one
  message run in one shell, so one's `cd` lands in the other's: on 2026-10-13 a commit sent in a
  parallel batch landed empty in the workspace and a chained push sent it, and on 2026-10-20 a
  commit sent beside a check did the same, `main` moved onto it, caught before the push. A
  `jj root` printing the wrong repository is the signal to stop, not to read past.
- **`jj st` is read after every commit by path.** A rename is a delete and an add, so naming the
  new path leaves the delete behind; a path holding `[`, `]`, `~`, `&` or `|` is fileset syntax and
  is dropped unless written `'file:"..."'`. Name files, never a directory, which sweeps in another
  session's edits.
- **An edit is seen before it is committed.** BSD `sed` matches nothing with GNU's `\|` and says
  nothing; on 2026-10-07 an empty commit went out after one. Edit with Python, asserting the count,
  or the Edit tool, and see the change in `jj st` or a grep first.
- **A formatter runs before an exact-match edit, never between two.** A reflow moved the text a
  replacement was looking for, and the replacement silently did nothing.

## Other sessions and formatters

- **`fmt` names its repository, and a formatter run by hand names its files.** On 2026-09-26 a bare
  `mise run fmt` reformatted rdm's spec under another session's uncommitted files; on 2026-10-04 a
  bare `oxfmt` rewrote 54 unrelated files, markdown tables among them.
- **A write across repositories first looks for another session**: `jj op log` for operations
  that are not this session's, and `pgrep -fl claude`. A repository in use is skipped and named.
  On 2026-09-25 `jj fix` in seam, beside another session's scratch file, left its working copy
  divergent.

## Shell

- **A computed list of paths is built in Python**, asserted non-empty and passed by
  `subprocess.run`. The Bash tool's zsh does not split `$list`, and macOS's bash 3.2 has no
  `mapfile`; on 2026-10-04 an empty list made `jj restore` restore the whole working copy.
- **A tool is run through mise, never as the Bash tool's PATH finds it.** That PATH puts a global
  pnpm 11 ahead of mise's pinned 12, so a bare `pnpm install` in a repository below rewrites its
  lockfile with the wrong one; `mise exec -- pnpm ...` or a mise task runs the pinned one. Seen
  on 2026-10-20.
- **Nix reads a flake from git's index, which jj does not fill.** In a colocated repository a
  file the working copy adds is in no commit git's index stands on, so a flake evaluated in place
  misses it, silently unless it is `flake.nix` itself; `git add -N` would show it, and is git. A task
  that runs Nix copies the flake's own files to a temporary directory and reads it as `path:`, as
  `monoflake/platform`'s `nixfmt` and `nixed` do. Seen on 2026-10-20.
- **A wait for a rebuild waits on an edit its watcher sees.** On 2026-09-05 a loop waited for rdm's
  binary to change after an edit to `spec/` alone, and nothing was ever going to rebuild.

- **An address is redacted by a pattern BSD `sed` reads.** macOS's `sed -E` has no `\b`, so a
  pattern built on it matches nothing and prints every address it was meant to hide; on 2026-10-23
  tailnet addresses reached a transcript so. Replace digits outright, `tr '0-9' '#'`, or use Python.
- **A socket unit's address changed is not taken by a switch.** NixOS left
  `driver-machine-entry.socket` holding its old address, so the entry bound the new one itself and
  refused connections while it restarted, found by `replace` on 2026-10-23; the socket is restarted
  once by hand after such a switch, and `replace` run after it.

## Remotes, and what cannot be taken back

- **An outward step asked is done alone.** "Push it, and then it is archived" asked for a push; the
  archiving, and the settings the author changed first, were theirs. 2026-10-20.
- **A push that publishes the author's own code to a registry is asked for first.** A repository
  whose CI publishes a crate or an npm package on a push to main is pushed only once the author says
  so -- `canmi/lib`'s releases its packages. On 2026-10-15 two pushes published npm versions nobody
  asked for. An image or a GitHub release that repackages upstream's code, as `monoflake/runtime`
  and `monoflake/machine` do, is pushed without asking, the author said on 2026-10-23, and so is the
  author's own code whose CI publishes nothing.
- **A write naming a Worker first finds the Worker by that name.** A non-interactive `wrangler
  secret put` answers its own "create a new Worker?" with yes: on 2026-10-06 it made an empty Worker
  named as the config said, while the real one was deployed under the dashboard's name.
- **After a push, the next task starts.** Watching a deploy or polling a registry's propagation
  stalls the session for nothing asked; the author says when a publish is out.

## Reading and reporting

- **A contradiction is quoted before it is filed**: both clauses whole, side by side. On 2026-10-19
  a conflict was filed between two drafts from a summary of one, which on reading said the opposite.
- **The author's shorthand is understood, never offered back as a name.** Cloudflare's two letters
  typed in chat are Cloudflare in every file and every proposal, as [naming.md](naming.md) asks, and
  the words part of the check refuses them. 2026-10-20.
