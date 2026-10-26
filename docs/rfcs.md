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
and nothing more; `supersedes` and `blocked-by` stay within a space, where a bare id is one RFC.
A commit an RFC names is `<repo>@<hash>`, `<repo>` being `workspace` or a path from
`repos/registry.toml`. A commit in a retired repository, named in `Planning.retired`, is kept as
written and not checked.

**A rule cites the RFC behind it by its id alone**, `RFC 2ut6h`, and the RFC is found by it,
`docs/rfcs/*/*-2ut6h.md` in a repository of its space, whatever its area and slug became. An RFC names no page and no spec, so
which rules it settled is read off the citations.

**An RFC is plain Markdown**, CommonMark with GFM, and calls no component of the design system it
decides, so a frozen record never changes when the system does -- RFC ejy85.

**The tools are the workspace's, `scripts/rfcs/`.** `mise run rfc new <name> <area> [--in <path>]`
starts one in the workspace or in the repository named, making its slug of its name and picking its
id and its place in the day within its space; the `rfcs` part of every check holds each file of a
space to the format, reading every cloned repository of it. Web's `apps/space/rfcs` draws the
pages and still checks `canmi/rfcs`. The task was `new-rfc` until 2026-10-26, when tasks came to
be named by one word, docs/toolchain.md, so an RFC landed before then names it so.

**Everything not done is an RFC too, by its status** -- RFC p992n and [planning.md](planning.md):
`draft` for an open question or a finding, `accepted` for decided work or a milestone, `landed`
once built and pushed, naming its commits, or `declined`. A draft or an accepted RFC is edited as
the work moves; a landed or declined one is frozen. **`blocked-by` names the RFCs that must land
first, by id**, the graph held acyclic by the `rfcs` part of check; `mise run plan [space]` lists what
nothing open blocks, then each of the rest behind the chain it waits on. `rfc new` starts a draft
unless given `--status`, and takes `--day` for a question older than its RFC.

**Its license is CC BY-NC-SA 4.0**, the one repository that is not MIT -- [readme.md](readme.md),
"A license year is when the idea began".
