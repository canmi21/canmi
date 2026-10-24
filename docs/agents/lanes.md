# Lanes

How the implementers of a wave are kept apart, and how their work is merged. How the work is split
is [delegation.md](delegation.md); how a wave is checked and committed is
[checking.md](checking.md).

## File ownership is the whole of the concurrency control

**Two implementers never share a working copy**: each works in a lane of its own, one jj
workspace, and file ownership is what lets the lanes be merged with no conflict. Decided by the
author on 2026-10-24, replacing one working copy shared by every implementer. Being the one
partition the merge rests on, it has to be exact.

- **The file set is declared before dispatch**, not discovered during it.
- **Disjoint sets run together; overlapping sets run in sequence.** There is no third answer, and
  no locking cleverness worth inventing for a handful of implementers. Sets run together once
  `implementer-commands` lands; until then one implementer runs at a time,
  [delegation.md](delegation.md).
- **The model's interfaces and its registries belong to the integrator** and to nobody else: a
  module list, a route table, a workspace's member list. **Shared code the model does not hold is
  written by one implementer in the wave before**, and the next wave's implementers use it.
- **One refactor is one agent.** A signature and its call sites are a single task however many
  files they span. Splitting them gives two implementers one interface to guess at
  independently, which is the failure this repository has already paid for once: one interface
  rewritten seven times in an afternoon, every disagreement silent, each found by a person
  happening to describe it out loud. Parallelism is across independent concerns, never across
  one change.

The structural repair is worth more than the discipline. Two hand-written spellings of one
interface, in two programs that never compile together, disagree silently by construction -- and
that afternoon ended by moving the shape into a package both import, so the eighth disagreement
would have been a compile error. A rule that asks people to be careful is what gets written when
the rule that makes carelessness fail loudly is not yet available.

### Within a repository and across them, a lane is the unit

Found on 2026-10-23 running two implementers on one thread, RFC 54q45, the author having turned
parallel work on. A file set alone is not enough where implementers share a working copy: a crate
half written breaks the workspace another implementer builds, so **two implementers never share a
working copy**, each in a lane of its own, one jj workspace, whether they work in one repository
or in two. **Neither runs `mise run check`**, since two
repositories' checks may build one ReScript package at once, and the integrator runs every check
once both have returned. What one implementer needs of the other's side is said to the
integrator, which passes it on: neither edits the other's files, nor asks the other directly.

### Some files have one writer, the integrator

**Only the integrator changes these**, decided by the author on 2026-10-24: `model/`, every RFC,
`docs/`, `AGENTS.md`, and a root manifest, which is a Cargo workspace's member list,
`pnpm-workspace.yaml`, `workspace.toml` and `model/plan/work.res`. `Delegation.singleWriter` in
[model/rules/delegation.res](../../model/rules/delegation.res) lists them. **A lockfile is
derived**: never merged by hand, it is written again by the integrator when a wave is merged.
**An implementer's diff that touches a file outside its own directory is refused by `accept`.**

**Once `accept-in-lane` lands, in a lane `accept` runs as `accept <name> --from <base>`**, and
passes over no file of another block in work; until then it runs as it does now. Each lane has a
working copy of its own, so the reason `accept` once let another block's files stand, one tree
shared by every implementer, no longer holds. `accept-in-lane` in the model, decided by the author
on 2026-10-24.

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
checkout would meet on one lock. The integrator opens one with `mise run lane open <repository>
<name>` and closes it with `mise run lane close <name>`, a task not written yet. **A lane is closed
once its change is in the main line**: its jj workspaces are forgotten, `cargo clean` runs,
`node_modules` is removed, and then the directory.

**A lane's `target` holds no more than `Delegation.laneTarget`**, and is cleared with `cargo clean`
past that. **A cache that can be written again is cleared by its own tool's clean**, never
with `trash`, which frees no space; one with no clean, as `node_modules`, and a lane's directory
being closed are removed with `rm` inside the workspace, as `AGENTS.md` has it. **The pnpm global
store is never touched.**

## File ownership partitions files, and that is all it partitions

The section above is the whole of the concurrency control for editing. Five things sit outside
editing, and each of them was found by being broken.

**Measurement intersects writing even where the file sets are disjoint.** An implementer
measuring a build while other implementers edit its sources measures a tree that never existed.
The first CSS budget figures of that session were already stale by the time they were read. A
measurement is scheduled between waves, never beside one.

**jj snapshots the whole tree, so every jj write waits for the writing to stop.** A `jj commit`
taken while an implementer was mid-write produced `Concurrent checkout` and a divergent change id.
The recovery is to confirm the orphan's content is live in the working copy, then `jj abandon` it.
**An implementer types no jj command**; a task it runs, as `accept --from`, may read its own lane's
history, and that lane is the one working copy it reaches.

**A constraint adopted for concurrency is re-evaluated when the concurrency ends.** A rule that
exists because two implementers were in flight outlives its reason unless somebody says so out
loud.

**The integrator's own checking method is proven to fail before it is trusted.**
`mise run verify 2>&1 | tail` returns `tail`'s status, so every "exit 0" read that way meant
nothing. An implementer comparing comment block counts read `jj file show -r @`, which returns the
working copy because jj auto-snapshots it, compared new against new, and reported a perfect green
from a comparison that had not happened. This is [code.md](../code.md), "A rule is maintainable
only when breaking it fails loudly", pointed at the checker instead of at the code.

**A project's task and the workspace's can share a name, and the wrong one passes.** `mise run
refs` from the workspace runs the workspace's gate, which never reads `repos/web/spec`. An
implementer verified a web edit against it twice and reported a green count line that had not
looked at the file it changed. **The path goes in the brief**: `mise run //repos/web:refs`.
