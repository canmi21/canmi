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

## The payload inside an envelope is not standardised

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
[architecture/artifacts.md](../repos/lattice/spec/architecture/artifacts.md) in lattice for the
worked example, where a stale writer cost nine published objects and no consumer could have seen
it.

## Keys are stable; values are cheap

Renaming a key costs every reader. Changing what a value means costs more and is invisible, so a
value whose meaning shifts gets a new key rather than a quiet reinterpretation.

Dates are ISO 8601 with an offset, durations are seconds as a number, and sizes are bytes as a
number. Those three are where a unit gets assumed and never written down.
