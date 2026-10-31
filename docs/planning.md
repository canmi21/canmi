# Planning: a short roadmap, everything not done an RFC

Every repository's rules -- this workspace's `docs/` and `model/`, each project's `docs/` -- hold
what holds now, and one file may hold what does not: `roadmap.md`, the long-term direction. The
workspace keeps none now; its last direction was the platform's, which the author will set out
afresh. Everything not done yet is an RFC, in the repository nearest it -- RFC p992n, and
[rfcs.md](rfcs.md) for the rest.

| What                                  | Where                                                    |
| ------------------------------------- | -------------------------------------------------------- |
| The long-term direction               | `roadmap.md`: a few lines, never detail, steps or a date |
| An open question, a finding           | a `draft` RFC                                            |
| Work decided and waiting, a milestone | an `accepted` RFC                                        |
| Chores decided, waiting on a moment   | a deferred item, `model/plan/deferred.res`               |
| What waits on what                    | `blocked-by` on the RFC that waits, by id                |
| What to take up next                  | `mise run plan [space]`, from the rest                   |

**What is not done is one of three, and each has one home.** Agreed with the author on 2026-10-20.

- **Open** -- what is not decided: not yet discussed, or discussed without an end. It is a draft
  RFC, or a row of a project's own checklist where it keeps one, as the platform does. Code that
  waits on it is a `%todo("<id>")` or a `todo!("<id>")` naming it, and on nothing else.
- **Deferred** -- what is decided and waits on a moment, with nothing left to argue: a repository
  to split, a directory to rename, commits held back. Each is an item of `model/plan/deferred.res`,
  waiting until an RFC lands or until the author says, and listed in red at the end of every
  `check`, never failing it. One that needs an argument is an `accepted` RFC instead, and nothing
  decided is stubbed in code.
- **Not done at all** -- a rule, or a `declined` RFC; never a list of things to do.

**A deferred item may waive a rule of the workspace's over the repositories it names**, so a
violation already known and already scheduled is listed rather than refusing every commit there;
the waiver ends with the item. Only a part whose findings name the rule they break can waive one,
`Waiting.waivable`.

**A deferred item may pause the repositories it names**, `pauses: true`, so that every verb run with
`--all` but `pull` and `push` passes over them and says so, `update`, `fmt` and `clean` as much as
`check` and `audit`, as the author restated on 2026-10-31 after an `update --all` reached the frozen
apps/rdm, and the workspace's scans across repositories, lines,
names, settings and drift, read only the rest, `Waiting.active`. A repository nobody is working on is not checked, because
its findings ask for work nobody is doing; naming it alone, `mise run check canmi/web`, still runs
its check. The `paused` item holds every repository but the workspace and monoflake's two.

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

**The loop closes first, then it is timed, and only its slowest stage is worked**, decided by the
author on 2026-10-30. Work that builds a way of trying changes, a pipeline, a test machine or a fast
loop, is carried end to end once in its roughest form before any stage of it is improved. Once it
closes, each stage is timed from the logs of a real run, never estimated, and the next work is the
stage that costs most per iteration, its time weighed by how often the loop runs. An improvement to
any other stage, or a refinement thought of on the way, is parked as a draft or a deferred item. A
stage that will be deleted gets no polish. A tool is improved before the work it serves only when it
lies on the loop and what it saves over the runs left outweighs what it costs. The loops differ in
their targets: an inner loop run many times a day aims at a minute or two, an outer one run a few
times a day at minutes.

**A design is worked out top down, one layer at a time, every area together.** It starts from what
its users need, numbered layer 0 at the face, and goes down a layer only once every area of the layer
above has come down to it: no area is followed to the bottom while another is still open higher up.
Where a layer finds an area unsettled above, the discussion goes back up to it first. Each layer is
written into its draft before the next is begun.

**An RFC is filed by what it is about, never by repository**, so a question or a piece of work
every project shares is filed once, in its area, and a project's own planning does not copy it.

**cue and still file no RFCs for now**: cue is private, and still has no spec. Their open questions
and decided work stay in their own `spec/`, as an `issues.md` and a `todo.md`, until either changes.
