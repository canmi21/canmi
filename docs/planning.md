# Planning: a roadmap here, everything not done an RFC

Every repository's rules -- this workspace's `docs/` and `model/`, each project's `spec/` -- holds what holds now, and one file about
what does not: `roadmap.md`, the long-term direction. Everything not done yet is an RFC in the
`rfcs` repository, cloned at `repos/rfcs` -- RFC p992n, and [rfcs.md](rfcs.md) for the rest.

| What                                  | Where                                                     |
| ------------------------------------- | --------------------------------------------------------- |
| The long-term direction               | `roadmap.md`: a few lines, never detail, steps or a date  |
| An open question, a finding           | a `draft` RFC                                             |
| Work decided and waiting, a milestone | an `accepted` RFC                                         |
| What waits on what                    | `blocked-by` on the RFC that waits, by id                 |
| What to take up next                  | `mise run plan` in `repos/rfcs`, worked out from the rest |

**A reader who reads the roadmap and runs the plan knows where the work stands.** The roadmap says
where it is going; the plan lists what nothing open blocks, then each of the rest behind the chain
it waits on. Neither carries an argument, which lives in the RFC.

**An RFC moves as the thing it names moves.** A draft is `accepted` once decided, `landed` once
built and pushed, or `declined`; the rules the work changed are written in the commit
that lands it, and cite it by id. A roadmap direction leaves when it is reached or dropped. Nothing
is struck through and kept.

**A question that is open is a draft even when it was found in a rules file.** An "Open" or
"Undecided" section in an ordinary file is a draft written in the wrong place: it moves into an
RFC, leaving the rule it concerns citing it. Comments cite one the same way -- [code.md](code.md),
"The rules hold what is settled; an RFC holds what is not".

**A design is worked out top down, one layer at a time, every area together.** It starts from what
its users need, numbered layer 0 at the face, and goes down a layer only once every area of the layer
above has come down to it: no area is followed to the bottom while another is still open higher up.
Where a layer finds an area unsettled above, the discussion goes back up to it first. Each layer is
written into its draft before the next is begun.

**An RFC is filed by what it is about, never by repository**, so a question or a piece of work
every project shares is filed once, in its area, and a project's own planning does not copy it.

**cue and still file no RFCs for now**: cue is private, and still has no spec. Their open questions
and decided work stay in their own `spec/`, as an `issues.md` and a `todo.md`, until either changes.
