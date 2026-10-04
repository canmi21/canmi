# READMEs, descriptions and license years

What a stranger reads first about a repository or a package: the line beside its name, the page
it opens on, and the year on its license. All three are the author's voice, not a spec's.

## A description is one short, plain line

**A repository's description is one sentence of four to eight words, ending in a full stop, that
says what the thing is.** Either a noun with an adjective or two -- `A compact programmable proxy
engine.`, `A refined download manager.`, `A tiny self-hosted cloud.` -- or a line with a stance --
`Rendering is a protocol, not a render-time computation.`, `Still your Mac. Clean it safely.`

- **Concrete, not grand.** A word that could describe anything -- "everything", "end to end", "in
  one place", "every site" -- reads as written by a machine, and a first draft built on them was
  turned down for exactly that.
- **No feature list, no stack, no third person.** "The author's" is a spec's phrase; a description
  is the author's own.
- **A package's registry description** -- `description` in a `package.json` or a `Cargo.toml` --
  follows the same rule, and is the same line its repository's README gives it.

The four repositories the system split into say `The canmi.net & canmi.app monorepo.`, `A small
library of packages and crates.`, `A tiny self-hosted cloud.` and `A tiny self-hosted PaaS.`

## A README is short, and in the first person

**A repository's README is a title, a few lines, and the license**, as lattice's was:

```md
# Everything Behind

The canmi.net & canmi.app monorepo.
Built from scratch. See `mise.toml` for project tasks.

Mostly built for myself, but feel free to browse the code for reference.

## License

MIT License © 2026 [Canmi](https://canmi.net)
```

- **The title is a name, in Title Case**, never the lowercase slug as it stands: a name of its own,
  `Everything Behind`, or the repository's made into one by what it means, `Library`, `Platform`,
  `Infra`.
- **The first line is the description**; the next say, in the first person, what the repository is
  for. Lines that belong together are joined by a hard break, two spaces at the end of the first.
- **Nothing a spec would say**: no layout, no links into `spec/`, no "the author's". A library's
  README may add a table of its packages, each with its one line.

**A package's README follows who it is for.**

- **One published for others** follows `axum-governor`'s: a line saying what it is, with links;
  `## Quick start`, the install and a short example; `## Features`, a bold lead and a sentence
  each; a table of its Cargo features or options; `## License`.
- **One built for the author's own projects** says what it is in a line or two, and ends with its
  license.
- **The title is made from the name, by what it means**, in Title Case: `Me` for `@canmi/me`, `UI`
  for `@canmi/ui`, `Axum Governor` for `axum-governor`. Not a mechanical conversion.
- **Every fact in it is checked against the code** -- an API's name, a dependency, a feature --
  and nothing in it tells a history that is not so: a new major is the same thing's next version,
  not something unrelated under its name.

## A license year is when the idea began

**The year on a README's license line is the year the package was first thought of**, which is
the author's to say: `response` and `whereabouts` were 2024, `axum-governor` 2025. It is the
idea's year, not the code's: an idea tried before and given up, then built now, keeps the year it
was first had, with no line of code connecting the two -- infra's panel and meter were 2024 and
keeper 2025, though all three were written in 2026, and host is 2026. A package whose
year nobody has said takes the year it was started in, and the question is asked rather than the
year guessed.

**An old year is not out of date.** It records when the work began, and a later year would claim
the work is newer than it is. Nothing bumps a license year because it looks old -- not a release,
not a new year, not a tidy-up.

**A repository keeps one `LICENSE`, at its root**, and its year stays as it is, whatever the
packages' READMEs say. A package that needs the file beside it links it -- `ln -s ../../LICENSE
LICENSE` -- rather than keeping a copy; `cargo package` and `pnpm pack` both follow the link and
publish the text, so no two copies can differ.
