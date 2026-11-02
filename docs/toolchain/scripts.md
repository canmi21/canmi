# Scripts and CLIs

### A script is ReScript, compiled before it runs

**A task, a tool or a hook of the workspace's is ReScript**, under `scripts/`, `hooks/` and
`model/`, compiled to `.res.mjs` beside its source by `mise run build`, which every task running one
depends on, and never committed -- RFC 17b3o. A mise task is the entry, and the script behind it
decides the order: **a task runs `Toolchain.taskLines` lines at most**, and past that it is a script
with the task its one line. `each` runs from `scripts/workspace/each.res`.
**No script is written in Python**, and the settings part holds the tree to it: `Toolchain.kept`
names the exceptions, `hooks/bin/rm` and its guard among them, which is a
command an agent types rather than a script, and stays as it is.

**A task is named by one word, and nested by spaces**: an action is the task's first argument, as
`mise run lane open`, `mise run repos list` and `mise run check workspace words`, never a name
joined by a hyphen. A command so read is declarative, a tree of nouns and the actions on them, and
one task holds every action of its noun. `task-nested` in `model/rules/toolchain.res`; canmi/web's
and seam's tasks wait for their repositories, the deferred `task-names-nested-rest`.

**A Cloudflare resource made with a place asks the author where**: an R2 bucket's location hint or
jurisdiction, a D1 database's location, a Durable Object's location hint, a Worker's placement, and
whatever else Cloudflare places by region. Where the author cannot be asked, Western North America
(R2's `wnam`, or its equal) or Asia-Pacific (`apac`) alone is chosen, by where the resource's
readers and writers are at the time. A place is never left unset: Cloudflare then places the
resource near the caller, and R2 never moves a bucket after, monoflake/platform's
docs/lessons/cloudflare.md, "Where R2 places a bucket". `cloudflare-placed` in
`model/rules/toolchain.res` holds the D1 databases and R2 buckets a script or task makes;
`cloudflare-placed-rest` waits for the rest, a create by the API, a jurisdiction, a Durable Object's
hint and a Worker's placement.

### A Rust CLI parses with clap, and wears cargo's colors

Arguments are declared as types with clap's derive API rather than read out of `std::env::args` by
hand. Unknown flags and invalid values are refused. Dependency count is not a constraint for a local
binary, [code.md](../code.md).

Help is clap's own, styled with `anstyle` to cargo's palette -- green headings, cyan literals. Not
clap's defaults: this stands next to `cargo` in the same terminal, and one constant saves its reader
a second color language.
