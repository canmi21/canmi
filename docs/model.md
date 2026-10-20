# The model holds what a program can decide

**Every rule of the workspace's that a program can decide is written once, in `model/`, with the
check that holds it**; its doc keeps the question, what was decided and why, and names the model
file instead of repeating a value. Agreed with the author on 2026-10-20, following monoflake's "the
model is the spec; a draft keeps the why", and for the reason [code.md](code.md) gives in "A rule is
maintainable only when breaking it fails loudly": a sentence nothing enforces decays without a
sound.

## The shape

| Path              | Holds                                                                     |
| ----------------- | ------------------------------------------------------------------------- |
| `model/rule.res`  | what a rule is: a name, what it says, the doc with its why, what holds it |
| `model/rules/`    | one file per topic: the values, and the rules over them                   |
| `model/checks/`   | the checks that read those values and answer with violations              |
| `model/check.res` | `check workspace [part ...]`, every part or those named                   |

It is ReScript, as every script here is, compiled by `mise run build` and never committed. A hook or
a script that needs a value imports it from the model rather than writing it again: the commit hook
and the history check read one `Commits.subjectWidth`, the comment gate and the docs one
`Code.columns`.

## What holds a rule

- **`Check(part)`** -- a part of `check workspace`, which the workspace's own check runs.
- **`Hook(path)`** -- a hook under `hooks/`, refusing at the moment an agent acts.
- **`Gate(path)`** -- a script under `scripts/` that each repository runs from its own verify.
- **`Pending(owed)`** -- decidable, and nothing holds it yet; `owed` says what the check would need.

**A soft rule is held by a part whose findings are warnings**, which fail only under `audit`: drift
is the one, as [repos.md](repos.md) gives in "A repository's own rules extend the workspace's".
**What the workspace holds over every repository runs on each of them**: `mise run check <path>`
runs the repository's own verify, then `Check.over` -- the shape, tasks, names, commits and drift
parts -- over it.

**A decidable rule enters with its check, or as `Pending`, and never as a sentence alone.** Agreed
with the author on 2026-10-20, so what is left is a count rather than a memory: every run of
`check workspace` ends with how many rules are pending, and `check workspace --pending` lists them.
The rules part holds each `Check` to a part that exists and each `Hook` and `Gate` to a file.

**A check is proven before it is trusted**: a violation is planted, the check is seen to name it,
and the plant is removed. A check never seen to fail is a name, not a check.

**What only judgment can keep is not modeled.** How to work with the user, when to ask, how to
delegate, what a commit body should say -- those are `docs/` alone, read rather than enforced.
Forcing one into a record would turn it into a string a program cannot read either.
