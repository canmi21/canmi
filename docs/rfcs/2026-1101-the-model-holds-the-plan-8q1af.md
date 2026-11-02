---
name: 'The Model Holds the Plan'
title: The model is the standard in force and the work to come, and an RFC records only why
status: decided
supersedes: [p992n]
references: []
---

## Question

What is not done lived in four places: a rule's `Pending`, `model/plan/deferred.res`, an RFC's
`accepted` status, and an advisor's memory of the order of the steps. None could say whether a thing
was done. Asked what was left, an agent could only answer with a count of accepted RFCs, and an RFC
read as fact had misled agents more than once.

## Options

- A rewrite of the model in Rust: no gain for facts the scripts read, and a generation step between.
- `accepted` RFCs kept as the plan: what this decision ends, as they forecast and drift.

## Decision

The author's, on 2026-11-01.

- **The model is the standard**: what holds now, what is to come, and the steps between them. Code
  is the fact of what is built, and nothing is defined twice: the model names a check or reads a
  value from the code rather than repeating it.
- **An RFC records only why a decision was made**, frozen once decided, and is no reference for what
  holds. A question not yet decided stays a `draft` RFC, since an open question is not a standard.
  This supersedes p992n's "everything not done is an RFC".
- **Docs say how to use the code and the model, and little more.**
- **Whether an item is done is derived, never written**, as a state someone writes drifts:

  | An item                  | Reads as                                                       |
  | ------------------------ | -------------------------------------------------------------- |
  | owes something           | waiting while something in `after` is not done, or else ready  |
  | names a check to land    | under way; the check warns, and refuses once it passes unmoved |
  | names a check that holds | done; breaking it refuses                                      |
  | names a commit           | done, while that commit is on its repository's main            |
  | names an observation     | done by evidence, dated, for what no program can decide        |

- **`after` names what must be done first**, by id, held acyclic, so the order of the work is data.

#

- **Each fact has one home, and every other place generates it or cites it by id**, the citations
  running one way:

  | What                                     | Its home                             |
  | ---------------------------------------- | ------------------------------------ |
  | what order and which states are safe     | a TLA+ specification, RFC w0w82      |
  | what the standard and the interfaces are | the ReScript model                   |
  | what comes next, on what, and if done    | the ReScript model's plan            |
  | what a machine is                        | Nix, as far as the container runtime |
  | what runs                                | the code                             |
  | why it was decided                       | an RFC, frozen                       |
  | how to use it                            | docs, short                          |

- **An RFC records only what happened**: the question, the options, the decision and why, frozen once
  decided, a later one superseding it. It holds no steps, order or forecast, as what a forecast says
  stops being true when the work moves. A draft is a question and its options, deleted if dropped.
- **The model stays ReScript**, used directly by the scripts and hooks; protocols alone leave it.
- **Each repository holds its own plan**, merged by `mise run plan`, so a private repository's work
  stays out of a public one.
- **Docs of rules and plan are generated from the model**, and only how-to is written by hand.

What this leaves open: A rule's plain sentence and its invariant say one thing twice, held only by review. Generated tests tie a specification to the code's decisions, not to all of it. What a machine runs can differ from its configuration, held by reading it and by dated evidence.
