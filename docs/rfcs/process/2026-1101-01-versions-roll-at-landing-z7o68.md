---
name: 'Versions Roll At Landing'
title: Every package holds a major, a minor and a patch that the landing rolls, the minor following its interface and the patch what counts
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

Packages of the workspace and of monoflake sat at `0.0.0`, driver-machine alone raising a version,
by a bump of its own under RFC 8c0rg. A deployment reading what a machine, a driver or a Worker runs
had nothing to read but a hash. What version does each package hold, who raises it, and when?

## Options

| Who rolls                           | Against it                                                      |
| ----------------------------------- | --------------------------------------------------------------- |
| The author of a change, in its lane | Two lanes raise one number, and each merge conflicts over it    |
| The lander, at landing              | One step more at each landing, which a check can refuse to skip |
| CI, after the push                  | A commit nobody checked, on a main line agents work from        |

Keeping `0.0.0` until a package publishes, as platform's `docs/code.md` had it, leaves the question
open for everything never published, which is most of what runs.

## Evidence

Driver's guard on inputs already raised driver-machine by path, through its
releases, which is the model the general task takes. A version change leaves a pnpm workspace's
`pnpm-lock.yaml` byte-identical with `--frozen-lockfile` passing, so only `Cargo.lock` follows a roll.

## Decision

- **Every package holds a major, a minor and a patch**, paused repositories aside; registries and
  `publish = false` stay as they are, and a raise publishes nothing.
- **Only the author moves a major.** The check refuses any other raise, `SKIP=major` naming the
  move.
- **A package serving one interface has its minor equal to that interface's version, and starts
  there.** One serving several or none has its own integer from `0.1.0`, raised by a breaking
  change with the patch back to zero. driver-machine continues at `0.1.4`.
- **A patch rises on a change to what counts**: a package's own files outside `docs/`, `tests/`,
  `*_test.*` and lint and format settings, what it declares, and its path dependencies. A root
  counts only files in no subpackage, and no path dependency raises it.
- **A lockfile move raises each binary or Worker built, and the root, and no library.** This gives
  way over RFC 8c0rg's "a lock alone is no change": a lock changes what a binary is.
- **Versions roll at landing on a main line, by `mise run bump`, and never in a lane.** A landing
  owing a raise is refused, and a push replays the check over its outgoing first-parent commits, a
  later raise paying an earlier one's debt.

This outranks RFC 8c0rg on what raises a version and platform's `0.0.0` while unpublished.

## State

Decided and landing. Held by `versions-rolled` and `versions-at-push`, `model/rules/commits.res`.
