# Voice & communication

## Language

- **Chat / spoken reply**: simplified Chinese mixed with English technical nouns. Don't translate established English terminology (e.g., "fetchpriority", "viewBox", "Hono", "OKLCH", "preset") — keep them as proper nouns inside Chinese sentences.
- **The reply that ends a turn is in the chat language, and a hook holds it.** The rule above was
  loaded at every start and still broken twice in one session: after a stretch of reading English
  specs and English tool output, the one-line updates between tool calls turned English, and then
  the reply did, and nothing from inside the drift notices it. So
  [hooks/language.py](../hooks/language.py) reads the turn when it ends and holds it open while the
  reply it ends with -- the prose after its last tool call -- is English with no Chinese in it --
  code, paths and short lines excepted, and a user who wrote English themselves answered in English.
  Only the person counts as the user: another session's message arrives in the user's place in
  English, and until 2026-10-09 every turn one started went unchecked, a whole afternoon of reports
  to workers' messages written to the user in English. The lines between tool calls are the work's
  own and are not checked: the author reads the reply a turn ends with, decided on 2026-10-09. The
  hold asks for the reply restated in Chinese; the check is a backstop, and the rule is still to
  write it in Chinese from the start.
- **File content, including code comments**: English only. No Chinese.
- **Commit messages**: English only.
- **The English is American.** `color`, `behavior`, `license`, `honor`, `traveled`, `labeled` --
  not the British spelling of any of them. This is not a preference between two correct forms:
  the platform is already American and half of it is identifiers. `color` is a CSS property, a
  StyleX key and a token name; `license` is a route, a file and a record type. An author writing
  `color` in the prose beside `color:` has put two spellings of one word in one file, and the
  one that is a reader's search term is the one that loses. The rule removes the choice so the
  file does not have to keep making it.
- **A name is quoted, not written, and English-only does not reach it.** The rule above governs
  what an author composes: prose, comments, identifiers, commit messages, documentation. A field
  whose value _is_ somebody else's name is not composed -- it is recorded, and it is recorded as
  its owner spells it, in the language that owner publishes in first, verbatim. A publisher
  leading in two languages is taken at the one it leads with, never at the one the reader happens
  to speak. So the show a clip in `web` is cut from is credited `爱情公寓`: `iPartment` is a
  distributor's rendering, and rendering a proper noun does not make the file more English, it
  makes the record less true -- and the record is the whole reason the field exists. This covers a
  publisher credit, a person, a product, a place: anything a reader could go and check.
  It licenses nothing around the name. The sentence containing it is still English, an identifier
  derived from it is still ASCII, and a _description_ of the thing is still written in English and
  translated like any other description.
- **No emoji by default** anywhere, and an assistant never adds one on its own initiative. An
  explicit user request may add one or two visible emoji to the requested interface, including the
  source literal needed to render them. That permission is local: it does not extend to unrelated
  UI, prose, comments, commit messages or chat.
- **The default governs writing, not auditing. An emoji already in the tree stays.** It is there
  because somebody put it there, and nothing in the file records whether that was asked for --
  a permission is granted in conversation and leaves no trace beside the glyph. So an assistant
  reading one cannot tell an approved emoji from an unapproved one, and must not guess.
  Removing on the guess destroys an intent that was expressed; leaving it costs a glyph nobody
  minds. Ask if it matters, and take silence as leave it alone. This rule exists because the
  opposite was done: `index.html` lost a 🎉 to a question that was asked and then answered by
  the assistant on the user's behalf.
- **Never in a name.** The permission above covers displayed content and nothing else. Identifiers
  -- variables, functions, types, CSS classes, file and directory names -- are never emoji and are
  never named after one, so `overview-ready-emoji` is wrong even though the class name is ASCII.
  A name says what a thing is for; which glyph happens to sit inside it today is content, and
  putting content in the name means the name is wrong the moment the content changes.

## "App" is ambiguous on purpose -- read the context

When the user says **app**, it can mean any of three things, and the word is not going to be
narrowed:

- a standalone application living in its own repository under `repos/`,
- one of the deployed services in `apps/` -- the API, the CDN, the site itself,
- the desktop CMS, or any other application built around the website.

They are all applications, which is why one word covers them. Infer which from what is being
discussed and act on that reading; ask only when the sentence would lead somewhere different
under two of them. Guessing wrong is cheap to correct in conversation and expensive once it
reaches a file, so the reading matters most right before writing something down.

What this rules out is renaming a directory to disambiguate the user's speech. `apps/` holds
deployables and `repos/` holds separate repositories -- see [repos.md](architecture/repos.md)
-- and neither name is the place to record which sense a sentence used.

## "Base" means this workspace

Unqualified, **base** is the workspace root -- this repository, the one holding `repos/`. It is
the opposite case from _app_ above: one meaning, assumed, and only a sentence that says otherwise
overrides it. "Run it from base", "add it at base", "base config" all mean here, not in whichever
project the conversation happens to be about.

This is worth stating because the word is otherwise the most contextual one available -- a
codebase, a database, a base branch, a base directory -- so an agent reading it fresh has every
reason to hesitate, and hesitating is the wrong answer. The setting supplies the meaning: work
happens in a project, instructions come from the level above it, and the level above is what
needs a short name.

## "Kit" is two things -- read the context; "shared lib" is the repository

When the user says **kit**, it is one of two, and both are everywhere:

- SvelteKit, the framework the web projects are built on;
- `@canmi/kit`, the author's design foundation -- theme, tokens, motion, behavior -- one of the
  packages of their shared library.

As with _app_, infer which from what is being discussed: a route, a `load`, an adapter or `$app/*`
is SvelteKit; a theme, a token, a gesture or an import from `@canmi/kit` is the package. Ask only
when the sentence leads somewhere different under the two.

**"Shared lib", "shared library" and "lib" mean the library as a whole**: the author's own code
that depends on nothing else of theirs, kept in one repository, `lib`, and published as
`@canmi/me`, `@canmi/kit`, `@canmi/ui`, `@canmi/web` and `@canmi/response`, and as the crates
`canmi`, `response` and the rest. It was briefly called the kit, which is why the word needed this
section.

Written into a file, the bare word is never left to be read the same way: it is "SvelteKit", or
`@canmi/kit`. A reader of a file has no conversation to infer from.

## A figure in `spec/` is dated, or it is checked

Numbers appear throughout these documents and two kinds of them are kept true by opposite means.

**A figure describing a state that changes on its own is dated.** How large the corpus is, how far
a migration has got, how many components still do something -- nothing holds these still, and
writing one in the present tense promises that every change to the thing comes back and updates
the sentence. That does not happen and will not. Dated, the figure stops being a claim that rots
and becomes what it always was: a mark of how far something had got when somebody last counted.
The spelling is "measured ... at the time", as web's `spec/architecture/media.md` uses for its 39
records and its `spec/architecture/local.md` for its largest sidecar.

**A figure that is a value the code uses is not dated.** A constant, a threshold, a declared width
-- these have to match the code exactly, and the answer to one drifting is a check, not a hedge.
Dating such a number would excuse the disagreement it exists to catch.

The test is what keeps the number true. If the only thing that would is somebody noticing, date
it.

## Tone

- Terse and action-oriented. Skip pleasantries and pep talk.
- State results and decisions directly.
- One-sentence status updates at key moments (start of task, decision points, blockers).
- Don't narrate internal deliberation in chat.
- End-of-turn summary is one or two sentences. What changed, what's next.

Match response weight to question weight: a simple question gets a direct answer, not headers and sections.

## When to ask vs. act

- **Act** when the decision is reversible, the path is clear, or existing conventions cover it.
- **Ask** when the decision is structural (architecture, naming scope, library choice), would cause user-visible changes hard to revert, or involves a real trade-off the user should weigh.
- Avoid stacking multiple `AskUserQuestion` calls in succession. Pick the highest-impact question, ask it, act on the answer.
