# Version control

jj (Jujutsu), colocated with git -- `.jj` and `.git` sit side by side in the repo root. Use `jj` for
everyday work; reach for `git` only where jj has no equivalent.

The remote is `origin` and the default branch is `main`; the URL lives in git's own config, not
here, because a URL written into a spec document is a second place for it to go stale.

jj has no branches, only bookmarks, and **bookmarks do not advance on their own**. `jj commit`
leaves `main` where it was, so moving it is a separate, deliberate step (`jj bookmark move`).
Auto-advance is available as an opt-in jj config, `experimental-advance-branches`, and is
deliberately not enabled. A bookmark that only moves when told to is a bookmark whose position means
something.

Commit and move the bookmark; when to push is [commits.md](../commits.md), "When a change is done, and
when it is pushed".

### Parallel workspaces, superseded by lanes

**A lane is a working copy of its own, one jj workspace for each implementer**.

- The file sets are disjoint, a shared file is written by the integrator alone, and a lockfile is
  derived; the diff `accept --from <base>` reads holds all three by machine.
- A lane starts no dev server and does no deploy or rehearsal; those are done by the integrator in
  the main checkout alone, and a test binds port 0.
- What every lane abides by is the model and the contracts, frozen in the base commit; they exist
  already, and are no structure made for the concurrency.

How a lane is opened, merged and closed is [lanes.md](../agents/lanes.md).

**The cost is real and is accepted rather than hidden: a commit here is not guaranteed to build on
its own.** Several pieces of work land in one sequence, so checking out a commit in the middle may
find a change half of whose tree arrived in the next one. That is the price, and against it is a
mental overhead that is lower by a wide margin -- one tree, one set of servers, one place the
current state of anything is read. This is not a library with strangers bisecting its history. See
[commits.md](../commits.md), "Completion", for what a commit is therefore for.

Projects are separate repositories, so this is a question about concurrency inside one project and
never about two. Two projects are two directories. See [repos.md](../repos.md).
