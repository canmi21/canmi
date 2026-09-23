# Vendored source

Code taken from another project and kept in a repository here is vendored: copied in as files,
at one named version, and left as its authors wrote it. This is the arrangement for every such
copy, in every project.

## Where it sits

A project's vendored code lives under `vendor/<name>/`, one directory per upstream, and nowhere
else. The directory's `README.md` points here and says what each entry is. Inside each entry the
layout is the upstream's own, so that a diff between two upstream versions applies to it as a
patch, and each entry carries two files of its own:

- `LICENSE`, the upstream's, unchanged. What may be copied is decided by that file and not by
  anything written here.
- `VENDOR.md`, saying which upstream, which tag and commit, what was taken and what was not, how
  it is consumed, what checks run over it and which command prints what they report, and how it
  is upgraded. The report itself is the command's, not copied here -- see
  [agent-protocol.md](agent-protocol.md), "A number a command prints is cited, not copied".

## How it is taken

Files, not a submodule: the version control here is jj, which has none, and a submodule would put
the code one indirection away from the checks that read it. The upstream is cloned at its tag into
a temporary directory, its `.git` is dropped, and the files are copied in. Build output the
upstream commits as a fixture is not taken; build output is ignored by name wherever it sits.

## How it is treated

**The source is not edited.** What a project needs from a vendor it reaches through one package
of its own, named for what it does, and what it changes about the vendor's behavior it changes
there. This is the binding edge that [naming.md](naming.md) describes, applied to a copy: if the
upstream were replaced, one package changes. A vendor's own name appears in the vendor directory,
in its `package.json` where its own imports need it, and in that one package, and nowhere else.

**The language is the upstream's.** JavaScript with JSDoc stays JavaScript with JSDoc: TypeScript
reads the types off it as it reads a `.ts` file once `allowJs` is on, and a port would make every
upgrade a hand merge. The vendor's own compiler options, where it has them, are kept beside it and
run apart from the project's, to read rather than to gate.

**The linter and the formatter leave it alone.** `**/vendor/**` is excluded from both at the
workspace root, so that the files stay byte for byte the upstream's and a diff against the next
tag is the upstream's diff.

**So does the dependency resolver.** A vendored package is upgraded by taking a newer upstream and
by nothing else, so `mise run update` filters it out rather than resolving it. seam lists
`vendor/*` among its pnpm workspace packages, and without the filter `pnpm update` rewrote eleven
ranges in `vendor/kit/package.json` -- which is the hand merge this arrangement exists to avoid,
arrived at by a command nobody thought of as editing. It also stops the upstream's own pins being
reported as something this repository is behind on: SvelteKit holds cookie at 0.6 deliberately.

**The upstream's checks run over it.** Where the upstream ships tests beside its source, they are
kept and run under a config of their own from the vendor directory, and `VENDOR.md` says which
command runs them and which are excluded, and why.

**They are not a condition of `verify`.** Upstream's tests carry upstream's judgement, which of
them to skip included, and a count of them carries that judgement into ours unread: a count cannot
see a test move from passing into a skip, or out of the suite. Where a project's gate runs the
upstream's tests at all, it holds them to a list the project keeps outside `vendor/` -- every test
by name, the state it has to come out as, and for a skip whose reason it is -- and fails on any
test that disagrees, including one the list does not name. seam's `pkgs/suite/baseline.json` is the
worked case; its `spec/suite.md` has the states.

## Upgrading

Take the new tag the way the first one was taken, replace the entry's files, update `VENDOR.md`'s
version, commit and what was taken, and read the upstream diff for the files the binding package names.
Where the project keeps a list of the upstream's tests, the upgrade updates it, and its diff is the
account of which tests moved.
An upgrade is one commit saying which tag it moved to.
