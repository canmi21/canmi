---
name: 'The Model Holds the Plan'
title: The model is the standard in force and the work to come, and an RFC records only why
status: accepted
supersedes: [p992n]
blocked-by: []
commits: []
references: []
---

## Question

What is not done lived in four places: a rule's `Pending`, `model/plan/deferred.res`, an RFC's
`accepted` status, and an advisor's memory of the order of the steps. None could say whether a thing
was done. Asked what was left, an agent could only answer with a count of accepted RFCs, and an RFC
read as fact had misled agents more than once.

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
  | owes something           | waiting while something in `after` is not done, or else ready   |
  | names a check to land    | under way; the check warns, and refuses once it passes unmoved  |
  | names a check that holds | done; breaking it refuses                                       |
  | names a commit           | done, while that commit is on its repository's main             |
  | names an observation     | done by evidence, dated, for what no program can decide         |

- **`after` names what must be done first**, by id, held acyclic, so the order of the work is data.

### Steps

1. The schema, its check and `mise run plan` reading it, with deferred items and the order in hand
   moved in.
2. Each `accepted` RFC read against the code, by repository, and what it left moved in.
3. `accepted` removed from an RFC's statuses, and `docs/rfcs.md` and `docs/planning.md` reworded.
