# Lanes

How the implementers of a wave are kept apart, and how their work is merged. How the work is split
is [delegation.md](delegation.md); how a wave is checked and committed is
[checking.md](checking.md).

## File ownership is the whole of the concurrency control

**Two implementers never share a working copy**: each works in a lane of its own, one jj workspace,
and file ownership is what lets the lanes be merged with no conflict. Being the one partition the
merge rests on, it has to be exact.

- **The file set is declared before dispatch**, not discovered during it.
- **Disjoint sets run together; overlapping sets run in sequence.** There is no third answer, and no
  locking cleverness worth inventing for a handful of implementers. Sets run together under
  `implementer-commands`, [delegation.md](delegation.md).
- **The model's interfaces and its registries belong to the integrator** and to nobody else: a
  module list, a route table, a workspace's member list. **Shared code the model does not hold is
  written by one implementer in the wave before**, and the next wave's implementers use it.
- **One refactor is one agent.** A signature and its call sites are a single task however many files
  they span. Splitting them gives two implementers one interface to guess at independently.
  Parallelism is across independent concerns, never across one change.

The structural repair is worth more than the discipline. Two hand-written spellings of one
interface, in two programs that never compile together, disagree silently by construction; moving
the shape into a package both import makes a disagreement a compile error. A rule that asks people
to be careful is what gets written when the rule that makes carelessness fail loudly is not yet
available.

### Within a repository and across them, a lane is the unit

RFC 54q45. A file set alone is not enough where implementers share a working copy: a crate half
written breaks the workspace another implementer builds, so **two implementers never share a working
copy**, each in a lane of its own, one jj workspace, whether they work in one repository or in two.
**Neither runs `mise run check`**, since two repositories' checks may build one ReScript package at
once, and the integrator runs every check once both have returned. What one implementer needs of the
other's side is said to the integrator, which passes it on: neither edits the other's files, nor
asks the other directly.

### Some files have one writer, the integrator

**Only the integrator changes these**: the model's rules and declarations, every RFC, `docs/`,
`AGENTS.md`, and a root manifest, which is a Cargo workspace's member list, `pnpm-workspace.yaml`,
`workspace.toml` and `model/plan/work.res`. **The model's rules and declarations** are the
workspace's `model/rules/`, `model/plan/` and `model/rules.res`, and a repository's declaring files,
as monoflake/platform's `model/graph/` and `model/contracts/`. **A check program is code, an
implementer's**: `checks/check.res` and `checks/`, of the workspace and of a repository alike.
The one exception is a rule's `held` moved from `Pending` to `Check`, a registration the integrator
writes at the merge. `Delegation.singleWriter` in
[model/rules/delegation.res](../../model/rules/delegation.res) lists them. **A lockfile is
derived**: never merged by hand, it is written again by the integrator when a wave is merged. **An
implementer's diff that touches a file outside its own directory is refused by `accept`.**

**Once `accept-in-lane` lands, in a lane `accept` runs as `accept <name> --from <base>`**, and
passes over no file of another block in work; until then it runs as it does now. `accept-in-lane` in
the model.

### A wave opens on one base and closes in one merge

**Every lane of a wave opens on the same base commit**, and that base holds the model and the
contracts, frozen for the wave. An implementer does not commit. **When the wave ends, the integrator
joins the lanes in one merge with a parent for each**, writes the lockfiles again and runs the logic
layer's check, the full check waiting for the push gate, in the order [checking.md](checking.md), "A
wave runs in one order", gives. The file sets are disjoint, so the order the lanes are merged in
does not matter.

### A lane is a directory beside `repos/`

**A lane lives under `lanes/` in the base workspace**, beside `repos/` and ignored by git, laid out
as `lanes/<name>/monoflake/<repository>`; **a sibling repository is a jj workspace of that sibling's
own, on the same base commit**, never a symbolic link to its main checkout: ReScript writes what it
builds of a dependency into the dependency's own directory, so through a link the lanes and the main
checkout would meet on one lock. The integrator opens one with `mise run lane open
<repository|workspace> <name> [--with <repository> ...]` and closes it with `mise run lane close
<name>`, each taking
`--dry-run`; `lane-task` in [model/rules/delegation.res](../../model/rules/delegation.res). **Lanes
are opened one at a time**, as several `lane open` run at once fail together. **Open**
adds a jj workspace on `main` at `lanes/<name>/<repository path>`, or `lanes/<name>/canmi` for the
workspace, one for each repository its `workspace.toml` `[boundary]` depends on, transitively, and
for each `--with` sibling the boundary does not name, and starts `pnpm install` in the background
where a `package.json` is, a platform sibling also building and generating. **A lane is closed once its change is in the main line**: close runs `jj st` in
each of the lane's workspaces, so an edit is snapshotted, and refuses, leaving the lane as it is,
where any working copy holds a change `main` lacks; otherwise the jj workspaces are forgotten,
`cargo clean` runs, `node_modules` is removed, and then the directory. **A lane's workspace is
forgotten only after a jj command run in the lane**: jj snapshots a working copy only when a command
runs in it, so an edit never snapshotted would go with the lane's directory. Open and close run from
the base workspace, never from inside a lane. **A lane is judged by its diff before it is handed
back**, and `handed` runs from inside the lane too: `mise run lane handed <name> [--own
<directory> ...]` reads the files each of the lane's workspaces changed from where it forked from
`main`, and refuses one past `hardLines`, one in `singleWriter`, a lockfile, and, where `--own`
names the block's directories, a file outside them; a file past `splitBeforeLines` is listed. It
also reports what the form layer would refuse at landing, a file its formatter would change, a
directory past `Layout.widest`, a comment past its columns, so a seat runs it before it reports.
`split-before-work` in [model/rules/code.res](../../model/rules/code.res) and `single-writer`, `own-directory` and
`lockfile-derived` in [model/rules/delegation.res](../../model/rules/delegation.res) are held there;
close refuses the same lengths. The `lanes` part of the check holds the task declared and
named here, and `lane-state` warns of a lane that is no workspace of a registered path and of a
`target` past the limit below, `lane-target`.

**Before a lane opens, the base workspace's working copy is frozen with `jj new`, and while a lane
is open that working copy is not edited**: an edit to the commit a lane stands on rebases the lane's
commit, the lane's working copy goes stale, and `jj workspace update-stale` then overwrites the
edits on the lane's disk.

**A lane's `target` holds no more than `Delegation.laneTarget`**, and is cleared with `cargo clean`
past that. **A cache that can be written again is cleared by its own tool's clean**, never with
`trash`, which frees no space; one with no clean, as `node_modules`, and a lane's directory being
closed are removed with `rm` inside the workspace, as `AGENTS.md` has it. **The pnpm global store is
never touched.**

## File ownership partitions files, and that is all it partitions

The section above is the whole of the concurrency control for editing. Five things sit outside
editing.

**Measurement intersects writing even where the file sets are disjoint.** An implementer measuring a
build while other implementers edit its sources measures a tree that never existed. A measurement is
scheduled between waves, never beside one.

**jj snapshots the whole tree, so every jj write waits for the writing to stop.** A `jj commit`
taken during writing produces `Concurrent checkout` and a divergent change id; the recovery is to
confirm the orphan's content is live in the working copy, then `jj abandon` it. **An implementer
types no jj command**; a task it runs, as `accept --from`, may read its own lane's history, and that
lane is the one working copy it reaches.

**A constraint adopted for concurrency is re-evaluated when the concurrency ends.** A rule that
exists because two implementers were in flight outlives its reason unless somebody says so out loud.

**The integrator's own checking method is proven to fail before it is trusted.** `mise run verify
2>&1 | tail` returns `tail`'s status, not verify's. `jj file show -r @` returns the working copy
because jj auto-snapshots it, so it cannot serve as the old copy in a comparison. This is
[code.md](../code.md), "A rule is maintainable only when breaking it fails loudly", pointed at the
checker instead of at the code.

**A project's task and the workspace's can share a name, and the wrong one passes.** `mise run refs`
from the workspace runs the workspace's gate, which never reads `repos/web/spec`. **The path goes in
the brief**: `mise run //repos/web:refs`.
