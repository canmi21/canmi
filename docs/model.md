# The model holds what a program can decide

**Every rule of the workspace's that a program can decide is written once, in `model/`, with the
check that holds it**; its doc is a short entry naming the model file instead of repeating a value,
and its why is an RFC, [rfcs.md](rfcs.md). A sentence nothing enforces decays without a sound,
[code.md](code.md), "A rule is maintainable only when breaking it fails loudly".

## The shape

| Path              | Holds                                                                  |
| ----------------- | ---------------------------------------------------------------------- |
| `model/rule.res`  | what a rule is: a name, what it says, the doc naming it, what holds it |
| `model/rules/`    | one file per topic: the values, and the rules over them                |
| `model/checks/`   | the checks that read those values and answer with violations           |
| `model/check.res` | `check workspace [part ...]`, every part or those named                |
| `model/plan/`     | `work.res`, the plan: what is to be done and what each item waits on   |

It is ReScript, as every script here is, compiled by `mise run build` and never committed. A hook or
a script that needs a value imports it from the model rather than writing it again: the commit hook
and the history check read one `Commits.subjectWidth`, the comment gate and the docs one
`Code.columns`.

**The plan is `model/plan/work.res`**, a list of items, each with an id, what it says, the
repositories it touches and the ids it comes `after`. What it `holds` is one of five: it owes
something, a check part is being brought in, a check part holds it, a commit on a repository's main
did it, or a dated observation shows it. Whether it is done is read from that and never written, and
the `plan` part of the check holds the list to what it names. `mise run plan` prints what is under
way, ready and waiting, `--done` what is done, and a pending rule appears there by name while it
stays in `model/rules/`. See [planning.md](planning.md).

## What holds a rule

- **`Check(part)`** -- a part of `check workspace`, which the workspace's own check runs.
- **`Hook(path)`** -- a hook under `hooks/`, refusing at the moment an agent acts.
- **`Gate(name)`** -- a gate a change passes outside the check, named in `Rule.gates`, as `push`;
  or, by its path, a script under `scripts/` that each repository runs from its own verify.
- **`Pending(owed)`** -- decidable, and nothing holds it yet; `owed` says what the check would need.

**A soft rule is held by a part whose findings are warnings**, which fail only under `audit`: drift
is the one, as [repos.md](repos.md) gives in "A repository's own rules extend the workspace's".
**What the workspace holds over every repository runs on each of them**: `mise run check <path>`
runs the repository's own verify, then `Check.over` -- the shape, tasks, placed, names, commits
and drift parts -- over it.

**A decidable rule enters with its check, or as `Pending`, and never as a sentence alone.** What is
left is a count rather than a memory: every run of
`check workspace` ends with how many rules are pending, and `check workspace --pending` lists them.
The rules part holds each `Check` to a part that exists, each `Hook` to a file, and each `Gate` to a
file or a name in `Rule.gates`.

**A rule marked `Pending` describes the goal, and until its check lands the behavior of now is
what holds**. A document citing a pending rule says so: what
it describes holds "once `<rule>` lands", and until then the present behavior does.

**A check is proven before it is trusted**: a violation is planted, the check is seen to name it,
and the plant is removed. A check never seen to fail is a name, not a check.

**What only judgment can keep is not modeled.** How to work with the user, when to ask, how to
delegate, what a commit body should say -- those are `docs/` alone, read rather than enforced.
Forcing one into a record would turn it into a string a program cannot read either.
