# Naming conventions

This document covers filesystem names only: files and directories. Identifiers inside source
code are governed by the language, not by this document -- see [Inside code](#inside-code).

## A workspace member is named in one word

A directory under `apps/` or `libs/` gets one word, or an abbreviation that can be read aloud.
Roughly 4 to 8 characters, lowercase, no hyphen unless the name is genuinely two words. What
goes inside follows the rules below.

Name for responsibility, never for deployment shape or product. `cdn` describes what it is;
`res` described a slot it happened to occupy. Product and domain names are the worst
candidates of all -- they change. A domain that was a content site can become a redirect
without a single line of its code changing.

**A database is a database, never a `DB`**, in prose, names and identifiers alike; the word is short
enough already, and an abbreviation is one more spelling to search for.

**A name chosen in design is chosen for how exactly it fits.** While an architecture is worked
out, whether a package registry or a domain has the name free is not asked; the most technically
fitting word wins. Availability is a question for publishing, met when something is published.

**One word may carry two meanings, so long as the two are never needed where one reader reads.**
Decided by the author on 2026-10-24, in place of a name having to be unique in the project. In
code, a module or a contract that uses both meanings writes each by its qualified name, never
opening both sides and using the bare word, `qualified-meanings` in
[model/rules/naming.res](../model/rules/naming.res). In a document it is judgment: one that
discusses both meanings qualifies the word each time.

**A global name is the model's.** A contract's, a component's and a role's name is given by the
model alone, written by the integrator as the author decided it,
[agents/integrator.md](agents/integrator.md). An implementer names only what is local to its own
block, choosing the most exact and most technically neutral word, `global-names-modeled`.

**One concept is one word, and where it varies is a dimension of it, never a second word.** Agreed
with the author on 2026-10-18: a control of the platform and a control of an organization are both
a control, of one half or the other, never `platform` beside `control`; a word coined only to tell
two places of one thing apart makes a reader learn two names for one meaning and ask how they
differ, when they do not.

## Default

Lowercase English, hyphen-separated:

```
user-profile.ts
api-client/
2026-07-release-notes.md
```

No uppercase, no spaces, no underscores by default.

### The workspace checks its own names, and the failure falls on the other machine

`Naming.shape` in [model/rules/naming.res](../model/rules/naming.res) is the rule as data, and the
names part of `check workspace` holds every name this repository tracks to it. A project below is
checked by nobody yet. The reference check is no help there: it resolves a cited path with an
existence test, and the file system here is case-insensitive, so a citation of `docs/VENDOR.md`
finds `docs/vendor.md` and passes.

The failure therefore runs the unusual way round. A miscased name does not fail here and pass
elsewhere; it passes here and stops resolving on a case-sensitive file system. The only person
who will ever notice is the one writing the name.

## Language exceptions

When a language has an established convention of its own, that convention wins for source
files in that language. The default above applies to everything else in the repo.

| Language | Source file naming                      | Example           |
| -------- | --------------------------------------- | ----------------- |
| Rust     | Underscores, matching the module name   | `user_profile.rs` |
| Python   | Underscores, matching the module name   | `user_profile.py` |
| Go       | Underscores where a separator is needed | `user_profile.go` |
| ReScript | Underscores, as the module name reads   | `graph_test.res`  |

`Naming.underscored` lists them.

Rust file naming is independent of crate naming. A crate is still `my-crate` with a hyphen in
`Cargo.toml`; only its source files use underscores, because a module name is a Rust
identifier and cannot contain a hyphen.

## Framework exceptions

Some frameworks assign meaning to a filename. Follow the framework -- a renamed file simply
stops working. `Naming.assigned` lists the ones this repository holds; Next.js's
`[slug]/page.tsx` is another.

### Docker's files take Docker's plain names

`Dockerfile`, `.dockerignore` and `docker-compose.yaml`, and no variant of any of them: not
`Dockerfile.dockerignore`, not a suffix naming a target. Docker finds all three by those names
without being told, and a reader finds them the same way; a variant is a name somebody has to
already know. The Compose file is `docker-compose.yaml` rather than the shorter `compose.yaml` the
Compose specification now prefers, or the `.yml` it still reads: its name says whose file it is,
and its extension is written whole, as a name is, decided by the author on 2026-10-22. Where an image needs a context larger than its own directory, the `.dockerignore` sits
at that context's root and serves every image built from it.

### A release asset names its system before its machine

A file a release publishes is named `<name>-<version>-<system>-<machine>.<extension>`, the version
slot holding a channel such as `nightly` where the release moves: `wasmtime-49.0.4-linux-x86_64.tar`,
`rdm-nightly-macos-aarch64.dmg`. The machine is the kernel's name for it, as `uname -m` on Linux,
Rust's targets and Nix's systems write it, `x86_64` and `aarch64`, rather than OCI's `amd64` and
`arm64` or Node's `x64`; a manifest beside the files writes each target the same way,
`linux-x86_64`. Where a format inside the file has its own name for the machine, as an OCI image's
platform does, the file keeps that name inside and only its own name changes. Decided by the author
on 2026-10-22.

## Asset directories are singular; infrastructure is plural

Under `data/`, a directory holding addressable resources is named in the singular:
`image/`, `opengraph/`, `favicon/`, `meta/`, and `video/` or `audio/` when they arrive. Each
entry is a thing a reader asks for by name, and the directory reads as the type of that one
thing -- `image/{cid}.avif` is _an_ image.

`fonts/` is plural, and the exception is the rule working rather than breaking. Fonts are not
resources anyone requests individually; they are one self-hosted set the site loads as a
whole, closer to a dependency than to content. The plural marks that difference at a glance,
so a directory name says which kind of thing is inside before anything is opened.

## Vendor names stay at the edge

Name things for what they do, not for who supplies them. A vendor name belongs only in the
thin layer that binds to that vendor. Everywhere else -- the module names, the directories,
the types, the functions -- use the objective description of the technology or the function
being performed.

`apps/delivery/cdn` is a CDN whether Cloudflare, Fastly, or a box in a closet serves it. Naming it
`apps/r2` or `apps/cloudflare` would describe the current bill, not the job.

**Why.** A vendor name scattered through a codebase is a bet that the vendor is permanent,
and that bet has no upside. When it loses you get the worst of both: either a rename that
touches every layer, or a name that now lies -- an `r2.ts` that talks to S3. And even while
the bet is still good, the name carries less information than the alternative, because at
the point of use you want to know what a module _does_, not who invoices for it.

**Where a vendor name is correct.** Five places, all of them the boundary:

- Files the vendor defines. `wrangler.jsonc` is wrangler's file; renaming it breaks it.
- Dependency identifiers. `@cloudflare/workers-types` names a real package.
- The single adapter module that speaks the vendor's protocol and exposes your interface.
- Where a model declares its ground and its drivers.
- The lists of words a rule holds.

**A vendor's name is held by the same means as the project's own**, `vendor-name` in
[model/rules/naming.res](../model/rules/naming.res), with a set of names of its own, decided by
the author on 2026-10-24. The set takes only words that are unmistakably a vendor's,
`Naming.vendors`, never a plain English word. They may appear in a file the vendor defines, as a
package's name in a declaration of a dependency, in an adapter module each repository declares in
its `workspace.toml`, where a model declares its ground and its drivers, and in the lists of words a
rule holds, as `voice.res` and `Naming.vendors`. Documents and RFCs are not read.

**The test.** If the vendor were replaced tomorrow, how many names would have to change?
One. If the answer is more, the vendor has leaked past the boundary.

### The project's own name is a vendor's name too

Inside its own code, a project's name -- `monoflake` -- names nothing the code does, so it stays at
the same boundary as anyone else's, decided by the author on 2026-10-20 and sharpened on
2026-10-23. **The name appears only where a piece of data leaves the system and is mixed with
other people's, where it must still be told as the project's.** Everything inside the system --
a table, a unit, a directory, a bridge, a label, an option, a namespace, a module, a type, a
function, an import -- is only one of the system's own tables, and is named for its subject alone.
The places the name belongs:

- **A domain bound to the platform**, among every other name in DNS.
- **Its published identity**, among everyone else's in a registry: a package's name or scope,
  `@monoflake/codec`; an organization's name; an image repository's.
- **A format the project defines, as data**: a magic, `MOFL`; a signed record's `typ`. A file or a
  record carried away is told by these bytes, and they outlive any rename, so each is written once,
  in the module that owns the format.
- **A key derivation's context**, `monoflake:parcel:key:1`, among every other use of the same key;
  changing it changes every key derived.
- **Where a machine's operating system is joined to the platform**, as a value its configuration
  sets: the platform a machine belongs to is written there once, as configuration, and code that
  needs it reads that value rather than spelling the name. A machine's own options, units and
  paths stay neutral, `machine.driver`, `driver-machine`.
- **The surface a user meets beside other vendors'**: a command on their path, a header on a
  request, an SDK's entry point in their code.

ReScript is the trap: a package with `"namespace": true` takes its namespace from the package's
name, so `@monoflake/codec` is imported as `MonoflakeCodec.Cbor`, and every caller says whose it
is; a package names its namespace for its subject instead, `"namespace": "Codec"`.

**The test, for one's own name.** Renamed tomorrow, the formats and contexts keep the old name,
being data and versioned; the manifests, the domain and the one configured value change; no
identifier in the code changes. A new case is judged by the principle: does this datum leave the
system and meet other people's.

`own-name` in [model/rules/naming.res](../model/rules/naming.res) is the rule, and the names part
of `check <repository>` holds a repository's code to it, its documents unread; where the name is
data, the repository's `workspace.toml` names each file and its spelling under `[[names.data]]`.
It holds every owner the registry lists but the author's own account, whose name is a person's,
so a project under that account is held by judgment alone.

### A rebrand does not oblige a rename, and a one-letter name is refused outright

**Twitter is Twitter here**, in identifiers, module names, spec files, commands and URLs, and it
stays that way whatever the service calls itself. See web's `twitter.md` for that case in
full; the rule it stands for is general.

A name has one job: to say which thing this is, at the point somebody reads it. `X` cannot do
that job in a codebase, where a single letter already means an axis, an unknown, a placeholder
and a coordinate -- `crate::x` and `cms x` read as something nobody got round to naming. A
rebrand is the owner's decision about their product; what a name has to accomplish in source is
unaffected by it, so following one is a cost with no matching benefit.

Two things are still the vendor's, exactly as the rule above says. Their **identifiers** --
Grok's `x_user_search` is the name of a real tool and renaming it breaks the call. And their
**hosts**, where nothing else resolves: `twitter.com` is used because it is still live and
permanently redirects, not because the old name is willed into being. Were it switched off, the
address would follow and the name in the source would not.

This rule and the "name for responsibility" rule in
web's `architecture/workspace.md` are the same instinct at two scales: the volatile fact --
product, domain, deployment shape, supplier -- never gets carved into the part that is
expensive to change.

**The inverse also holds: a vendor's thing must not squat on a generic name.** `libs/svg-canvas`
styles SVG diagrams written in Claude's authoring convention. It was briefly `libs/canvas`,
which was wrong in the opposite direction from the usual mistake -- a vendor-specific
boundary had taken the name a real, general canvas library will want. A precise convention
name such as `svg-canvas` is fine; the generic `canvas` name stays free for the thing that
earns it.

Inside that library the convention's own selectors (`.svg-canvas`, `.c-purple`) are left
untouched, because they are the contract with the markup. The library name was the only part
we owned.

Worked example from this repo: the commit hook is `hooks/commit.res`, not `jj-commit.res` and not
a copy under either agent's vendor directory. Validating a commit message is not a jj-specific
job; it would survive a move to another VCS untouched. The `jj-` prefix named the current
supplier of the commits, which is exactly the information the filename did not need.

## Inside code

Identifiers follow the language's own convention with no interference from this document:

- TypeScript / JavaScript: `camelCase` variables and functions, `PascalCase` types.
- Rust: `snake_case` items, `PascalCase` types, `SCREAMING_SNAKE_CASE` constants.
- Python: `snake_case` items, `PascalCase` classes.

A `camelCase` variable inside a `user-profile.ts` file is correct. The two rules do not
interact.

### A name is not reused inside its own scope

A local does not take the name of something already in scope: not the function or import it is
about to call, and not the variable an enclosing block already holds. `const held = ...` beside an
imported `held()`, or a `held` two blocks inside another `held`, reads correctly only after counting
scopes, and in a codebase whose verbs double as nouns -- `held`, `written`, `kept` -- that count is
wrong often enough. The linter's `no-shadow` is the check.

**The inner side is what gets renamed, and for what it holds rather than for being inner.** The
function or the outer variable keeps its name, since it is the one every other reader already
knows. The inner name says what this particular value is: the set of names an expression mentions is
`referenced`, the edit that closes a block is `closing`, the text a rune answers to is `answer`.
Never `held2`, `innerHeld` or `h`. Where the inner turns out to compute the same thing the outer
already holds, it is deleted instead, which is the case a shadow most often hides.

## Inside data

**A key in a serialized format is lowercase, and words in it are joined by an underscore.** JSON,
YAML, TOML, a column name, a query parameter: `focal_length`, `color_space`, `country_code`,
`cancel_token`. Never `focalLength`, never `FocalLength`.

**This does not interact with the rule above either, and that is the whole point.** A record is
read by more than one language -- web's image manifest is written by Rust and read by
TypeScript -- so a key that follows the writer's convention makes the reader spell it the other
way round, and a key that follows the reader's does the same to the writer. Lowercase with
underscores belongs to neither and is legible in both. Rust is free to call the field
`focal_length` and TypeScript is free to call a local `focalLength`; what travels is the key.

The corollary is that a type describing a serialized record is not an ordinary type. Its property
names are the wire format, so they take the data rule rather than the language's, and a
`serde(rename)` or a mapping layer is the thing to notice: either the record disagrees with the
rule, or two spellings of one field now exist. Press's manifest carries exactly one, `frameRate`,
which predates this.

A value is not a key and keeps whatever it is. Locale tags stay `en-US`, a content hash stays the
hash, and a name somebody else spells is spelled their way -- see [voice.md](voice.md).
