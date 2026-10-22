---
name: 'RFCs Beside What They Decide'
title: 'An RFC lives in the repository nearest what it decides, its id unique in an id space a repository declares'
status: accepted
supersedes: [7f4xx]
blocked-by: []
commits: []
references: []
---

## Question

Every RFC was one file in one repository, `canmi/rfcs`, beside none of what it decided, and its
tools were web's. Monoflake already kept its own, and a private repository's reasons cannot sit
in a public one. Where does an RFC live, how is its id kept its own, and whose tools hold it.

## Decision

Decided by the author on 2026-10-22.

- **An RFC lives in the repository nearest what it decides**, in that repository's
  `docs/rfcs/<area>/`, so a public question is written in the public repository and a private one
  in the private: the workspace's own in the workspace, the platform's in `monoflake/platform`,
  the hosted platform's in `monoflake/cloud`.
- **An id is unique within an id space**, which a repository declares in its `workspace.toml` as
  `[rfcs] ids`: `monoflake` for the organization's repositories, `workspace` for this one, `canmi`
  for the author's other projects in `canmi/rfcs`, which keeps them until it is taken up again.
- **A citation may cross spaces and repositories**, a public RFC or rule citing a private one's id
  among them: the reader without the private repository learns the id and nothing of how it was
  decided.
- **The tools are the workspace's**, `scripts/rfcs/`: `mise run new-rfc`, `mise run plan`, and the
  `rfcs` part of every check, each reading every cloned repository of a space.
- **The workspace's own RFCs come home** from `canmi/rfcs` into its `docs/rfcs/`.
