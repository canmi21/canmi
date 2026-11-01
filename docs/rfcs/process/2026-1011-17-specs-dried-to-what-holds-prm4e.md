---
name: Specs Dried to What Holds
title: "Each spec keeps a rule's current value, and why it is so, what was tried and when, move into an RFC"
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

A spec carries its rules and the history of each. Where does the history go?

## Decision

- **Each rule keeps its current value**, and why it is so, what was tried and when it was settled
  move into an RFC, one at a time, never ahead of an RFC to take them -- since a reason taken out with
  nowhere to go is a reason lost.
- **It reaches every doc, not only a spec, and a later RFC outranks an earlier one**, decided by the
  author on 2026-11-01, when the platform's RFCs had fallen behind weeks of fleet work: `docs/` and
  an `AGENTS.md` keep only the rules in force, with no date, decider or story; history stays in the
  RFCs, where the later date has the highest priority and an earlier one may be stale; whatever a
  program can hold goes to the model with its check, leaving the doc a short entry.
- **The drain runs over the workspace and monoflake**, the rest being paused, one repository at a
  time, cloud first. A dated origin with no RFC to take it gets one before it leaves the doc. The
  check `docs-in-force` lands with the last of them.
