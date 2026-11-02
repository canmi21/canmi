# Lessons

The practices learned the hard way that are in force, with their history in the RFCs.
For private notes and work in progress, see [agent-protocol.md](agents/agent-protocol.md),
"Selfcheck".

## Commits

- **A commit names its paths literally, never by a command substitution.**
- **The co-author trailer names the model running now.** Read it from the current system prompt,
  never from a handover, memory, or earlier commit; write the trailer literally, without a shell
  variable.
- **A check and a commit are two calls.** Read the check's own exit status before a commit or push;
  never infer it from a later command after `;` or a pipe. Keep edits out of the commit's call. A
  push may follow a check through `&&` only when the check's own status gates it.
- **Recheck whenever a commit or check changes the verified tree.** Check again after a commit by
  path reformats files. Run the check twice after changing Cargo workspace members, since Cargo may
  update `Cargo.lock`.
- **An implementer sent a message is working again until it says it is idle.** Wait for its latest
  idle report before committing its repository.
- **A turn never ends with a passed check not yet committed.** The check's end is followed in the
  same turn by the commit, the push and the one-line report, or by a report of why not; on
  2026-11-02 a passed check sat uncommitted for 29 minutes until the advisor asked.
- **A seat never ends its turn to wait for a background job's notice.** No notice wakes it, so it
  watches the job's output itself under Monitor with `mise run //:watch` until the job ends; its
  dispatcher reads the seat's last transcript entry at each follow-up, never ListAgents' idle.
- **Each commit is its own call, alone in its message, opened by `jj root &&`.** Stop if the root
  names the wrong repository.
- **`jj st` is read after every commit by path.** Include both sides of a rename, quote fileset
  metacharacters with `'file:"..."'`, and name files rather than directories to exclude other
  sessions' edits.
- **An edit is seen before it is committed.** Use Python with an asserted replacement count or the
  Edit tool, then inspect the result with a status read or search. Do not use GNU `sed` syntax with
  BSD `sed`.
- **A check's warnings are read before a commit meant for a push.** Resolve warnings that the push's
  form layer would refuse.
- **A formatter runs before an exact-match edit, never between two.**
- **An RFC's place in the day is drawn before its file moves into a lane.** Draw every number needed
  before moving the files, or keep them in the default checkout until they land. At push, check the
  outgoing RFC numbers against the other repositories' mains on origin.

## Other sessions and formatters

- **`fmt` names its repository, and a formatter run by hand names its files.**
- **A write across repositories first looks for another session.** Inspect `jj op log` for other
  sessions' operations and `pgrep -fl claude`; skip and name any repository in use.
- **Two processes never build one ReScript tree at once.** Include sibling trees a task builds. Wait
  for implementers to finish before checking or committing; rerun lock or corrupted-interface
  failures alone before treating them as defects.
- **A commit rewritten is followed by `jj st` in every lane standing on it.** Read each lane before
  continuing there; see [lanes.md](agents/lanes.md).
- **A lane a seat will use is never rebased from outside; open a fresh one.** A lane rebased from
  outside goes stale, and its seat then works on the old tree without knowing.
- **A lane's sibling runs its own `generate` before anything builds against it.**
- **A seat stops every process it started before it reports, and says so.** Load made to test a
  flake, `sh -c 'while :; do :; done'` among it, outlives the seat under launchd and slows every
  check on the Mac; a brief that asks for load says to stop it.
- **Read Codex's quota before each dispatch, and read each seat's exit.** A seat started with none left
  ends at once, [delegation.md](agents/delegation.md); saying it runs needs its exit read.
- **An implementer cannot run ssh or git, and a brief asking it to stops it.** Run those yourself and
  hand it the result, or leave them out of the brief.
- **`jj restore --from <lane>@` with no paths replaces the whole working copy**, dropping what was
  uncommitted there; with work in the checkout, name the lane's paths, or commit first.

## Shell

- **A hook that cannot run fails a pre-tool call closed.** Use the main checkout's built hooks from
  a lane, and exit 2 for a pre-tool call when no build is available.
- **A wait on a oneshot reads its ActiveState, never `systemctl is-active`.** Read `systemctl show
  -p ActiveState` until the state is neither `activating` nor `active`.
- **A computed list of paths is built in Python**, asserted nonempty, and passed by
  `subprocess.run`.
- **A tool is run through mise, never as the Bash tool's PATH finds it.** Use `mise exec -- <tool>
  ...` or a mise task.
- **Evaluate a flake from a temporary copy of its own files using `path:`.** Do not rely on git's
  index to include files added in a jj working copy.
- **A running script is never edited.** Edit a copy and start it fresh.
- For rebuild wait triggers, see [agent-protocol.md](agents/agent-protocol.md).
- **A task that may ask is read whole, never sent to `/dev/null`.** Keep its stdin interactive and
  read all its output.
- **Run long commands with the tool's background facility and read their output.** Follow
  [agent-protocol.md](agents/agent-protocol.md) for timing; take steps one at a time, reading each
  result before the next, rather than polling for a condition a step may have passed.
- **A jump host goes in `~/.ssh/config` for its one machine, never as `-J` in `NIX_SSHOPTS`.**
- **A secret reaches a remote script only on the stdin of a script already copied there.** Copy the
  script with `scp` first, then pipe the secret to `ssh host 'sh /root/script'`. Stop BusyBox
  processes by pid, as every process is, [agents/agent-protocol.md](agents/agent-protocol.md).
- **Set PATH in a script started by `systemd-run`, or name tools by their store paths.**
- **A remote step carries a keepalive and a timeout.** Every scripted `ssh` sets `-o
  ServerAliveInterval=15 -o ServerAliveCountMax=4`, under a timeout longer than the step's own.
- **An address is redacted by a pattern BSD `sed` reads.** Avoid `\b` in macOS `sed -E`; replace
  digits with `tr '0-9' '#'` or use Python.
- **Restart a socket unit by hand after switching its address.** Run `replace` after the restart.
- **A background job's exit notice never comes from a hung job.** Each job gets a timeout, a remote
  command in one uses ServerAliveInterval, and a look by Monitor or timer starts in the same call.
- **Never send a probe's stderr to /dev/null.** A missing tool then reads as an empty result: an absent
  `strings` once reported a full flash chip as empty.
- **In the Bash tool's zsh, `$var` holding a command does not split**, so use a function; `==` at a line
  start in an unquoted `echo` breaks; `cd` carries to the next call, so use absolute paths and a subshell.
- **`mise run //:watch` on a log holding file contents gives false ended and failure lines**, and reads
  `failed=0` as a failure. Watch a status file, or print no such word.
- **`perl -e 'alarm N; exec @ARGV' mise run ...` kills mise alone.** The task's children live on and hold
  what they hold, so a timed-out conform kept running and its lock refused the rerun; list them by
  `ps` before reading the alarm as the job's end.
- **A bounded `for ... sleep` loop is still a foreground wait.** Wait on a job's completion notice,
  or watch its log under Monitor with `mise run //:watch <log>`; never type the wait in the foreground.

## Code

- **Mark a Worker's abstract RPC binding type `@notUndefined` before holding it in a ReScript
  option.**
- **A query's cost is measured, never assumed from its tests passing.** Measure rows read against a
  budget for each statement; follow [agents/seats/reviewer.md](agents/seats/reviewer.md) for reporting rows and
  their growth.
- **A shell script's test on the host's PATH never proves its package's inputs.** Review every
  command against the package's runtime inputs, and include a second run in live tests of stateful
  behavior.

## Remotes, and what cannot be taken back

- **An outward step asked is done alone.** Perform only the requested external action; leave
  separate settings changes or archiving to the requester.
- **A push that publishes the author's own code to a registry is asked for first.** Pushes that
  publish no code, and images or GitHub releases that repackage upstream code, need no additional
  permission.
- **A write naming a Worker first finds the Worker by that name.** Verify the deployed name before a
  noninteractive write that could create a Worker.
- **Before a push, the workflows that run on it are read, not the doc that describes them.** Treat a
  version bump as a release when a workflow publishes an unreleased version.
- **A delete through Cloudflare's `cf` passes `--force` and is read back afterward.**
- **A push and what depends on it are two calls.** Read the push's own exit code before continuing;
  a pipe requires `pipefail` to preserve a failed push's status.
- **A push across repositories that depend on each other stops at its first failure.** Push each in
  its own call and read its result before the next; use neither a loop nor `--all`. See
  [commits.md](commits.md).
- **A repository is pushed only once what it compiles against from a sibling is pushed too.**
- **A path another repository calls moves with every caller changed in the same hour.** A caller
  whose CI pins the moved repository also moves its pin by its update's actions step, or its next
  run fails on the old tree while the Mac passes on the new one; cloud's whole model and driver's
  tasks both broke after platform moved its check entry on 2026-11-02.
- **Stop a timer held for a step again after every NixOS switch.** Read `systemctl list-timers`
  before restoring it; a missed calendar slot can fire immediately, with or without `Persistent`.
- **Start required preparation units explicitly after a switch when their socket-activated daemon
  has not run.**
- **Run a new workflow, or one with a setup step removed, in a clean copy first.** Install and build
  only the repositories the workflow receives, with no generated files or parent dependencies
  supplied by the development checkout; YAML tests alone do not prove jobs run.
- **A push past the private-identifier scan is said to the advisor first.** State the hit and why it
  is not a leak before bypassing the scan.
- For the required push command, see [agents/pushing.md](agents/pushing.md).
- **Compare every machine's drvPath before pushing a secret change.** A shared `sopsFile` changes
  every system that reads it.
- **A pinned installer is read for what it fetches itself.** Inspect the sources and pins of its
  downloaded scripts too.
- **Reapply preferences cleared by `tailscale up --reset` after joining.** Rerun the unit that sets
  them until joining no longer resets them.
- **Retry a failed binary-cache fetch before reporting a fault.** Include HTTP 409 failures, which
  Nix does not retry.
- **An agent is forwarded to a machine only when the author or the advisor says so.** Otherwise use
  a key made for the measurement or run from the Mac across both hops.
- **A machine outside monoflake/cloud's fleet is not logged into unless the author or the advisor
  names it.** This includes read-only access; answer repository ownership questions from the
  repositories.
- **After a push, the next task starts.** Leave deploy watching and registry propagation polling to
  an explicit request.
- **Check a place, name, or credential against `model/rules` before proposing or approving it.** A
  provisional choice never overrides a written rule.
- For retired resource names, see [`drawn-ids-once`](../model/rules/naming.res).
- **A cloud commit reaches canmi and A through the `systems` cron while they remain in its matrix**, so
  "not deployed" needs them out of it first.
- **A driver import failed once with `import the archive: NotFound: not found`**, in a conform on snow at
  driver 0.1.4 on 2026-11-01, not reproduced in 9 conforms on mint and okra nor in 24 imports under
  forced collection on oak, cause unknown; reopen if it recurs. A lease is drafted in
  `~/.local/share/monoflake/driver-import-lease-2026-11-01.diff`: before taking it up, weigh a lease
  with no expiry leaking on a crash, a failed delete failing a good import, and a shared id across
  concurrent imports of one hosted image.

## Reading and reporting

- **A finding is fixed, or passed by a named escape, and never hidden.** Do not split a string, rename a
  word or move a line so a check cannot see it; fix what it asks, or use `SKIP=<gate>` or a rule's
  `exempts`, or take the rule to the integrator or the author.
- **A contradiction is quoted before it is filed.** Put both clauses in full side by side.
- **The author's shorthand is understood, never offered back as a name.** Expand vendor names in
  every file and proposal.
- **A record holding a secret is read by naming the fields wanted, never by masking the rest.**
  Select only needed fields, as `jq '{organization, relayed, address, origin: (.origin != null)}'`.
- **A directory holding secrets is listed by names and sizes alone.** Never select files to read by
  excluding secret-looking names.
- **A lane is taken by `mise run //:lane take`.** `jj restore --from <lane>@` reads the lane's last
  snapshot, so a hand edit there is lost unless a jj command ran after it; the take runs one first,
  and a duplicate by hand needs `jj st` in the lane.
- **A check's exit 0 is read with its red list.** Read failures listed after the check, including
  `task failed`; blocks in progress can report failures without failing the exit code.
- **A command handed to the author is first run in a form that changes nothing.** Rehearse from the
  directory they will use, with no arguments, `--dry-run`, or a value refused before a prompt.
- **A readback asserts its expected value, never prints it.** Fail unless the applied system matches
  the round's build, the record was written after the round began, and the setting has its expected
  value.
- **A tool streaming a fetch's output masks the bucket's endpoint before it reaches a terminal or a
  log an agent reads.** Replace the endpoint with `<endpoint>`.
- **Judge an R2 token used through S3 by its bucket's writes or by asking.** Never infer nonuse from
  an empty `last_used`.
- **A device is proposed for a role only after its cores, memory and disk are read.** Read the
  figures from fleet documentation, the host, or the author, and include them in the proposal.
- **Where the author is waiting on an event, the watch runs under Monitor printing a line at each
  change, and a job's exit notice is not the watch.** An agent says it is watching only while such a
  Monitor runs.
- **An estimate comes from a measurement, or says "unmeasured".** A figure is checked before it is passed
  on.
- **Read the record before speaking to it.** Advice on a machine starts from its deferred item and logs,
  not from memory of them.

## Planning

- For closing, timing, and improving loops, see [planning.md](planning.md).
- **A protocol spec, the code it guards and the harness tying them are three seats, each verifiable
  alone.** The spec and its switches answer to TLC's counts, the code fix to its unit tests, and the
  harness and parity test to an agreed fixture shape; the three start together once the fixture's
  keys are fixed. One seat for all three was too coarse, and a split finer than three costs more in
  learning the project than it saves.
