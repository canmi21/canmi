# RFCs: why, kept apart from what

**A rule in any repository's rules says what is done now; the reasons it was decided that way are an RFC**,
one file in the repository nearest what it decides, `docs/rfcs/<area>/` there -- RFC 1dj2c. Its
format, and why there is one, is RFC 2ut6h. They are read as files, found by id, until their pages
are drawn by the settled design system, which no address reaches before then -- RFC ggry5.

**An id is unique within an id space, which a repository declares**, `[rfcs] ids` in its
`workspace.toml`: `monoflake` for the organization's repositories, `workspace` for this one, its
name `Planning.workspaceSpace`, and `canmi` for the author's other projects, kept in
`repos/canmi/rfcs` with web's tools until that repository is taken up again. A citation may cross
spaces and repositories, a public one citing a private id among them, which tells its reader the id
and nothing more; `supersedes` stays within a space, where a bare id is one RFC.
A commit an RFC names is `<repo>@<hash>`, `<repo>` being `workspace` or a path from
`repos/registry.toml`. A commit in a retired repository, named in `Planning.retired`, is kept as
written and not checked.

**A rule cites the RFC behind it by its id alone**, `RFC 2ut6h`, and the RFC is found by it,
`docs/rfcs/*/*-2ut6h.md` in a repository of its space, whatever its area and slug became. An RFC names no page and no spec, so
which rules it settled is read off the citations.

**`docs/` and an `AGENTS.md` hold only the rules in force; how a rule came to be, its date, who
decided it and what went wrong before it, stays in the RFCs**, RFC prm4e, held by the `docs` part, `docs-in-force` in
[model/rules/planning.res](../model/rules/planning.res). **Among RFCs the later
date has the highest priority**: where two differ the earlier one is out of date on that point and
is left as written, so an old RFC is read as history and may hold stale information. The rules in
force outrank every RFC. **A doc is a short entry**: whatever a program can hold goes to the model
with its check, [model.md](model.md), and the doc names it.

**An RFC is plain Markdown**, CommonMark with GFM, and calls no component of the design system it
decides, so a frozen record never changes when the system does -- RFC ejy85.

**The tools are the workspace's, `scripts/rfcs/`.** `mise run rfc new <name> <area> [--in <path>]`
starts one in the workspace or in the repository named, making its slug of its name and picking its
id and its place in the day within its space; the `rfcs` part of every check holds each file of a
space to the format, reading every cloned repository of it. Web's `apps/space/rfcs` draws the
pages and still checks `canmi/rfcs`. The task is `rfc`, named by one word, docs/toolchain.md, so an
RFC landed earlier may call it `new-rfc`.

**An RFC records why, and what is not done is the model's plan** -- RFC 8q1af and
[planning.md](planning.md). From 2026-1101-02 on (`Planning.newFormFrom`) an RFC is a `draft`, a
question with its options and no decision, a `decided` one holding a Decision, or `declined`; it
has no `blocked-by`, `underway` or `commits`, and no Steps, Plan, Order, Next, Roadmap or Phase
heading, all held by the `rfcs` part of check. Older RFCs keep `accepted` and `landed` as history,
and neither a plan nor a fact about the code is read from them. `rfc new` starts a draft from a
Question and Options, adds a Decision under `--status decided`, and takes `--day` for a question
older than its RFC.

**Its license is CC BY-NC-SA 4.0**, the one repository that is not MIT -- [readme.md](readme.md),
"A license year is when the idea began".
