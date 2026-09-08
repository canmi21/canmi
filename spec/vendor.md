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
  it is consumed, what checks run over it and what they report at the pinned version, and how it
  is upgraded.

## How it is taken

Files, not a submodule: the version control here is jj, which has none, and a submodule would put
the code one indirection away from the checks that read it. The upstream is cloned at its tag into
a temporary directory, its `.git` is dropped, and the files are copied in. Build output the
upstream commits as a fixture is not taken; build output is ignored by name wherever it sits.

## How it is treated

**The source is not edited.** What a project needs from a vendor it reaches through one package
of its own, named for what it does, and what it changes about the vendor's behaviour it changes
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
kept and run under a config of their own from the vendor directory, and `VENDOR.md` says what they
report at the pinned version and which are excluded, and why.

## Upgrading

Take the new tag the way the first one was taken, replace the entry's files, update `VENDOR.md`'s
version, commit and counts, and read the upstream diff for the files the binding package names.
An upgrade is one commit saying which tag it moved to.
