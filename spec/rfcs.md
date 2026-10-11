# RFCs: why, kept apart from what

**A rule in any `spec/` says what is done now; the reasons it was decided that way are an RFC**,
one file in the `rfcs` repository, cloned at `repos/rfcs`. Its format, and why there is one, is the
first of them, RFC 2ut6h; why they have a repository of their own is RFC 7f4xx. They are read in
development alone until their pages are drawn by the settled design system -- RFC 43im3.

**A rule cites the RFC behind it by its id alone**, `RFC 2ut6h`, and the RFC is found by it,
`repos/rfcs/*/*-2ut6h.md`, whatever its area and slug became. An RFC names no page and no spec, so
which rules it settled is read off the citations.

**The repository is documents and a few settings, nothing else.** The code that holds the files
to the format and draws their pages is web's `apps/space/rfcs`, run on the sibling checkout, so
web is cloned beside it. In `repos/rfcs`, `mise run new-rfc <name> <scope>` starts one, making its
slug of its name and picking its id and its place in the day; `mise run check rfcs` holds every
file to the format.

**An open question's argument is a draft RFC, and its issue a line citing it** -- RFC qp9l1. A
draft is what `new-rfc` starts unless told otherwise, edited while the question moves, and in the end decided in
place or `declined`, either way frozen from then. An issue a line long, or one not for publishing,
stays an issue. The issues are dried into drafts one at a time, as the specs are dried into RFCs.

**Its license is CC BY-NC-SA 4.0**, the one repository that is not MIT -- [readme.md](readme.md),
"A license year is when the idea began".
