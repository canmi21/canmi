# Lessons

What an agent working here learned the hard way, each the habit it left and what happened. They were
kept in agent memory once; the author asked on 2026-10-20 that they stand here, where every agent
reads them. Agent memory keeps only what is private and the state of work in progress --
[agent-protocol.md](agents/agent-protocol.md), "Selfcheck". A lesson a program can come to decide
moves into `model/rules/` with its check and leaves this file.

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
- **An implementer sent a message is working again until it says it is idle.** Its report done, a
  question answered still sets it editing, so its repository is committed only after its last
  idle: on 2026-10-23 a test it added after answering was swept into a docs commit beside it.
- **No check runs while an implementer builds.** A check builds every block, and two builds of one
  ReScript package at once collide on its lock, failing whichever started second, so the
  integrator's checks and commits wait until the wave has returned.
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
- **A check's warnings are read before a commit meant for a push.** `check` only warns of a
  comment past its width, and the push's form layer refuses it: on 2026-10-27 two pushes stopped so,
  one in a moved test, one in a lane's script, and each took a commit more.
- **A formatter runs before an exact-match edit, never between two.** A reflow moved the text a
  replacement was looking for, and the replacement silently did nothing.

- **An RFC's place in the day is drawn before its file moves into a lane.** `rfc new` draws the
  day's number from what the default checkouts hold, so an RFC moved into a lane is invisible to the
  next draw, and each lane's check sees only its own: on 2026-10-24 platform's b75yr and driver's
  5n9cy both took 2026-1024-08 in the monoflake space and broke check on both mains once pushed.
  Draw every number an RFC for a lane needs before its file moves, or keep the file in the default
  checkout until it lands. **At push, the rfcs check holds the commits being pushed against the other
  repositories' mains on origin**, provisional, chosen by the advisor on 2026-10-24, the published
  truth, and refuses a day's number already taken there, the one moment a collision becomes
  everyone's problem; drawing over lanes is left out, since it would spend numbers on drafts a lane
  may drop. Pending until built.

## Other sessions and formatters

- **`fmt` names its repository, and a formatter run by hand names its files.** On 2026-09-26 a bare
  `mise run fmt` reformatted rdm's spec under another session's uncommitted files; on 2026-10-04 a
  bare `oxfmt` rewrote 54 unrelated files, markdown tables among them.
- **A write across repositories first looks for another session**: `jj op log` for operations
  that are not this session's, and `pgrep -fl claude`. A repository in use is skipped and named.
  On 2026-09-25 `jj fix` in seam, beside another session's scratch file, left its working copy
  divergent.
- **A commit rewritten is followed by `jj st` in every lane standing on it.** Rewording a pushed
  commit rebases each lane's change onto the new one and leaves that lane's working copy stale,
  as an edit to the base does, [lanes.md](agents/lanes.md); on 2026-10-27 a reworded commit of
  monoflake/machine did so to the lane on it, and `jj workspace update-stale` left the lane's
  edits in a divergent copy, recovered by `jj edit`. Each lane is read before the next step there.
- **A lane's sibling runs its own `generate` before anything builds against it.** A new jj
  workspace holds what is committed, never what a task generates and git ignores, so on 2026-10-27
  a lane's driver failed to build against its platform sibling, which lacked
  `code/libs/envelope/generated` until `mise run generate` ran there.

## Shell

- **A wait on a oneshot reads its ActiveState, never `systemctl is-active`.** A oneshot running
  is `activating`, which `is-active` reports as not active, so a loop waiting while it is active
  ends at once. On 2026-10-26 such a wait ended a machine's upgrade watch after twenty seconds,
  and its memory sampler was stopped while the upgrade still ran; `systemctl show -p ActiveState`
  read until it is neither `activating` nor `active` is the wait.
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
- **A running script is never edited.** bash reads a script as it runs it, so a script rewritten
  under a background run executed half a line; on 2026-10-25 a machine's install stopped with 127,
  command not found. A copy is edited and started fresh.
- **A wait for a rebuild waits on an edit its watcher sees.** On 2026-09-05 a loop waited for rdm's
  binary to change after an edit to `spec/` alone, and nothing was ever going to rebuild.
- **A task that may ask is read whole, never sent to `/dev/null`.** `mise run secret` asks before it
  replaces a value already set, and stdin from `/dev/null` answers no; on 2026-10-27 a new token was
  kept out so, its "kept" line discarded with the rest, and only an API call still refused showed it.
- **A long command is run with the tool's `run_in_background` and is not polled.** The harness says
  when it exits; a loop polling for a condition waits on one the step may already have passed, and
  waits for nothing, as the author found on 2026-10-26. Steps are taken one at a time, each read
  before the next.
- **A jump host goes in `~/.ssh/config` for its one machine, never as `-J` in `NIX_SSHOPTS`.** Nix
  hands those options to every ssh it opens, the builder's own on localhost among them, so all of
  them went through the jump on 2026-10-26.
- **A unit `systemd-run` starts has no PATH beyond systemd's own.** It carries none of the login
  shell's, so a script started that way on 2026-10-26 found none of its tools; the script sets its
  own PATH or names each tool by its store path.

- **An address is redacted by a pattern BSD `sed` reads.** macOS's `sed -E` has no `\b`, so a
  pattern built on it matches nothing and prints every address it was meant to hide; on 2026-10-23
  tailnet addresses reached a transcript so. Replace digits outright, `tr '0-9' '#'`, or use Python.
- **A socket unit's address changed is not taken by a switch.** NixOS left
  `driver-machine-entry.socket` holding its old address, so the entry bound the new one itself and
  refused connections while it restarted, found by `replace` on 2026-10-23; the socket is restarted
  once by hand after such a switch, and `replace` run after it.

## Code

- **A Worker's RPC binding is never held in a ReScript option of an abstract type.** Every name
  read on a Fetcher is present, so the option's unwrapping took a VPC binding for a nested option
  and handed on an object with no `fetch`; on 2026-10-23 the control reached no host so, while the
  local control, reaching its host by address, passed. The abstract type is marked `@notUndefined`.

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
- **A push across repositories that depend on each other stops at its first failure.** Each is
  pushed in its own call, its result read before the next, and those after a refused one wait,
  never in a loop and never by `--all`, [commits.md](commits.md). On
  2026-10-24 one shell loop pushed monoflake/platform, then had driver refused by its line limit
  and went on to push cloud, so cloud landed before driver against the cleared order, and driver's
  public main did not build against platform's new contracts until driver followed.
- **A NixOS switch starts a timer held by hand again.** A switch restarts every unit its
  configuration enables, timers among them, so a timer stopped for a step is stopped again after
  each switch. On 2026-10-25 both of monoflake's test machines had their daily upgrade timer
  stopped for a switch, and each switch started it again, caught from its output. **A timer
  started again fires a slot it missed at once**: systemd counts a calendar timer's next slot from
  its last trigger, or failing that its previous start, so a slot passed while it was stopped is due
  the moment it starts, `Persistent` or not. On 2026-10-26 a builder's timer for another machine,
  restored by a switch, ran at once. `systemctl list-timers` is read before a timer is restored.
- **A unit a socket-activated daemon requires is not run by the switch.** A switch starts what is
  enabled, and nix-daemon waits for its socket, so on 2026-10-27 each builder's preparation of its
  build subvolume, required by the daemon, ran only when started by hand after the switch.
- **A workflow never run before is run once in a clean copy first.** On 2026-10-27 the driver's
  first release failed at its install, its platform pin five days behind what the driver's own model
  needs; a copy made by `git archive` of the three repositories, built with nothing generated,
  proved the fix before the second push.
- **A push past the private-identifier scan is said to the advisor first**, the hit and why it is
  none, the advisor said on 2026-10-27, after one went out on a bare word the author then dropped.
- **A machine's secrets file is part of its system.** sops-nix copies a `sopsFile` whole into the
  store, so a key added to a machine's `secrets.json` for one program changes that machine's
  system, and a file several machines read changes each of theirs. On 2026-10-27 a new reader of
  the cache's keys changed eleven systems by their secrets alone. The drvPaths of every machine are
  compared before a secret is pushed.
- **A pinned installer is read for what it fetches itself.** On 2026-10-26 a reinstall script
  pinned by its hash downloaded a second script, `trans.sh`, from its upstream's main branch
  during the install, on two machines; pinning one pinned nothing it fetched.
- **`tailscale up --reset` clears every preference set before it.** On 2026-10-26 it cleared a
  relay port that a unit had set at boot, so the port stopped listening after a machine joined;
  the unit setting it is run again after a join, until the join stops resetting.
- **A binary cache answering 409 fails the fetch, and Nix does not retry it.** On 2026-10-26 R2
  answered one narinfo request with 409 and a machine's daily fetch failed; the same request was
  answered 200 an hour later. A failed fetch is retried before it is reported as a fault.
- **An agent is forwarded to a machine only when the author or the advisor says so.** For as long
  as `ssh -A` runs, root on the far machine can use the author's key against any host it reaches;
  on 2026-10-26 one measurement was run so unasked. A measurement uses a key made for it, or runs
  from the Mac across both hops.
- **A machine outside monoflake/cloud's fleet is not logged into unless the author or the advisor
  names it**, read-only or not. A question of who configures it is answered from the repositories.
  On 2026-10-26 the integrator ran one read-only command as root on such a machine to answer which
  repository kept it, which the repositories already answered.
- **After a push, the next task starts.** Watching a deploy or polling a registry's propagation
  stalls the session for nothing asked; the author says when a publish is out.

## Reading and reporting

- **A contradiction is quoted before it is filed**: both clauses whole, side by side. On 2026-10-19
  a conflict was filed between two drafts from a summary of one, which on reading said the opposite.
- **The author's shorthand is understood, never offered back as a name.** Cloudflare's two letters
  typed in chat are Cloudflare in every file and every proposal, as [naming.md](naming.md) asks, and
  the words part of the check refuses them. 2026-10-20.
- **A record holding a secret is read by naming the fields wanted, never by masking the rest**, as
  `jq '{organization, relayed, address, origin: (.origin != null)}'`. A mask by key name passes a
  field it does not know: on 2026-10-25 one hiding `secret` and `token` printed a binding's
  `tunnel` whole, a Cloudflare tunnel token, into a session's output.
- **A check's exit 0 is read with its red list**: a block in work fails nothing, its failures
  listed in red after the check, so a failing test passes the exit code. On 2026-10-26 a merge
  checked exit 0 with a test of the control failing; `task failed` and `✖` in the log showed it.
- **A command handed to the author is first run in a form that changes nothing**, from the directory
  they will type it in: no arguments, `--dry-run`, or a value refused before any prompt. On
  2026-10-26 `mise run secret` was handed with a `cd` into a repository, where mise resolves that
  repository's tasks and found none; `secret` is the workspace's, run from its root.
