# RFCs: why, kept apart from what

**A rule in any `spec/` says what is done now; the reasons it was decided that way are an RFC**,
one file in the `rfcs` repository, cloned at `repos/rfcs`. Its format, and why there is one, is the
first of them, RFC 2ut6h; why they have a repository of their own is RFC 7f4xx. They are read in
development alone until their pages are drawn by the settled design system -- RFC 43im3.

**A rule cites the RFC behind it by its id alone**, `RFC 2ut6h`, and the RFC is found by it,
`repos/rfcs/*/*-2ut6h.md`, whatever its area and slug became. An RFC names no page and no spec, so
which rules it settled is read off the citations.

**An RFC is plain Markdown**, CommonMark with GFM, and calls no component of the design system it
decides, so a frozen record never changes when the system does -- RFC ejy85.

**The repository is documents and a few settings, nothing else.** The code that holds the files
to the format and draws their pages is web's `apps/space/rfcs`, run on the sibling checkout, so
web is cloned beside it. In `repos/rfcs`, `mise run new-rfc <name> <scope>` starts one, making its
slug of its name and picking its id and its place in the day; `mise run check rfcs` holds every
file to the format.

**Everything not done is an RFC too, by its status** -- RFC p992n and [planning.md](planning.md):
`draft` for an open question or a finding, `accepted` for decided work or a milestone, `landed`
once built and pushed, naming its commits, or `declined`. A draft or an accepted RFC is edited as
the work moves; a landed or declined one is frozen. **`blocked-by` names the RFCs that must land
first, by id**, the graph held acyclic by `check rfcs`; `mise run plan` in `repos/rfcs` lists what
nothing open blocks, then each of the rest behind the chain it waits on. `new-rfc` starts a draft
unless given `--status`, and takes `--day` for a question older than its RFC.

**Its license is CC BY-NC-SA 4.0**, the one repository that is not MIT -- [readme.md](readme.md),
"A license year is when the idea began".
