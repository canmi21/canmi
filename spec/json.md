# Designing a JSON contract

What a record or an answer is shaped like, once more than one program reads it. The names inside
it are [naming.md](naming.md), "Inside data"; this is everything else.

## A contract has a version, and it is the first thing read

Any record two separately deployed programs share carries a `version` at its top level, and a
reader checks it before it reads anything else. Bump it when an old reader can no longer make
sense of a new record -- not when a field is added that it can ignore.

The version exists because the two ends stop moving together. While one build produced and
consumed a record, disagreement was a compile error; once a publisher writes bytes that a worker
deployed last month will read, nothing catches it but the reader. A version is what turns "this
looks wrong" into "this is not mine".

## Envelope or record, and never both at once

Two shapes, and a file or an answer is one of them.

**A record** is data at rest. It holds a version and its content, and nothing about how it was
transported. `data/metadata.json` is one.

**An envelope** wraps an answer in transit. It says whether the call worked and carries the
payload or the reason, and it is uniform across every route so a consumer can read it without
knowing which route replied.

The rule that keeps them apart: **an envelope is opened in exactly one place**, and what it
carries is checked somewhere else. The opener knows the envelope and nothing about payloads; the
caller knows its own payload and nothing about transport. A reader that reaches through an
envelope to a field is a reader that has to be changed when the envelope does.

## The payload inside an envelope is not standardized

Only the envelope is uniform. What a route answers with is that route's business, and forcing
every answer into one shape produces a lowest common denominator that fits nothing -- a `data`
that is sometimes a list, sometimes an object, always documented in prose because the type gave up.

The same applies downward: a record's contents are its own. Two records sharing a `version` key
does not mean their bodies should rhyme.

## A fact appears in exactly one place

If a value can be derived from another in the same document, it is derived rather than stored. Two
copies of one fact is two things that can disagree, and the second reader is the one that finds
out. The same holds across documents that travel together: an answer that repeats what the object
it names already carries has created a second source.

Where a copy is genuinely worth it -- a listing that would otherwise cost one request per row --
the duplication is the point and is written down as such, next to the field.

## Absent, not null

A field with nothing to say is left out. `null` is a third state to handle at every reader, and in
practice it arrives meaning both "unset" and "known to be empty" in the same document.

Something that is genuinely a value gets one: an explicit `false` is a boolean, not an absence.

## An optional key is not a schema change

Adding a key an old reader ignores is compatible and needs no version bump. Removing one,
renaming one, or changing a type is a break: state it as a version and give the reader a way to
refuse rather than misread.

This is why a reader validates the shape it needs instead of the shape it was handed. A parser
that rejects unknown keys turns every future addition into an outage; one that strips them lets a
producer drift silently. Neither catches a producer writing a field the type dropped -- see
[architecture/artifacts.md](../repos/platform/spec/architecture/artifacts.md) in the platform for the
worked example, where a stale writer cost nine published objects and no consumer could have seen
it.

## Keys are stable; values are cheap

Renaming a key costs every reader. Changing what a value means costs more and is invisible, so a
value whose meaning shifts gets a new key rather than a quiet reinterpretation.

Dates are ISO 8601 with an offset, durations are seconds as a number, and sizes are bytes as a
number. Those three are where a unit gets assumed and never written down.

## A contract across languages is the producer's type, and every other reader is derived from it

**Within one language a shared contract is a library; across languages it is a JSON Schema the
producer generates from its own type**, committed beside it. The producer's type is the one source:
a Rust service's answer is its `serde` type, and `schemars` writes the schema from it. A check
generates the schema again and fails on any difference, so a type changed without its schema is
caught where it changed. Every reader in another language is derived from the schema and never
copied by hand, since a copy agrees with the producer only until the producer's next change. Where a
reader's tests need an example of what the producer answers, the producer commits that answer too,
generated and checked the same way, and the tests read it: a schema holds the shape, and only the
producer's own answer holds the values, a choice's choices among them. Decided with the author on
2026-10-13, first for the registry's catalog, then for what the relay sends the console, which was
copied by hand into the console's `wire.ts`.

**A TypeScript reader is generated twice from the schema: its types, and its valibot validator**,
both committed and checked for drift as the schema is. valibot is what the TypeScript code already
validates with, so a contract read across languages is checked the way every other input there is.
The generator is the workspace's own and covers the part of JSON Schema the producers write --
objects, enumerations, arrays, optional keys and references -- refusing anything else rather than
guessing at it. It lives in web, `apps/console/scripts/contracts.ts`, and is never copied: another
repository runs it from there with `--schema`, `--reader` and `--again`, the command its own task
regenerates with, as the platform's `mise run catalog` does, and commits what it writes.

**Both languages run one set of examples.** Beside each schema sit `valid/` examples, the producer's
committed answers among them, and `invalid/` ones -- a key missing, a choice outside its list, a key
unknown where the type forbids one. The producer's tests and every reader's tests run all of them
and must agree on each, so a reader that accepts what the producer would refuse, or the reverse, is
caught as surely as a type that changed.
