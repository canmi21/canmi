# Planning: roadmap, todo and issues

Every `spec/` -- this workspace's and each project's -- answers three questions about what is not
done yet, each in a place of its own, beside the files that hold the rules. Together they and the
rules are the spec.

| Place        | Holds                                                     | Never holds              |
| ------------ | --------------------------------------------------------- | ------------------------ |
| `roadmap.md` | the long-term direction: decisions about where to go      | detail, steps, or a date |
| `todo.md`    | work that has been discussed and decided, and is not done | a question still open    |
| `issues.md`  | every open question: something found and not yet decided  | a decision already taken |

**A reader who reads those three knows where the project stands.** The roadmap says where it is
going, the todo what has been agreed and is waiting to be built, and the issues what nobody has
decided. None of them carries the argument: an entry is a sentence or two and a link to the
ordinary spec file where the detail is written once. The same file may be cited by an issue and by
a todo entry -- that is the point of keeping the detail out of both. What is defined twice is
pulled out into one file and cited from both places.

**An entry moves as the thing it names moves.** An issue that is decided leaves `issues.md`: as a
todo entry if it is work, or as a rule in an ordinary file if deciding it was the whole of it. A
todo entry that is done leaves `todo.md`, and what it built is described by the rules it changed.
A roadmap direction leaves when it is reached or dropped. Nothing is struck through and kept.

**A place outgrows a file the way any file does**, and then becomes a directory of the same name
with an index named after it -- `issues/issues.md` -- and one file per area. The index lists every
entry by its heading; an entry's argument stays in the area's file.

**A question that is open is an issue even when it lives in a rules file.** An "Open" or
"Undecided" section in an ordinary file is an issue written in the wrong place, and moves to
`issues.md`, leaving a link where the rule it concerns is stated. Comments link to an issue the same
way -- see [code.md](code.md), "`spec/` holds what is settled; an issue holds what is not".

**The workspace's three hold what is true of every project**; a project's hold its own. A
direction or a question that every project shares -- a coverage target, a layer every deployed page
should sit behind -- is the workspace's, and a project's own planning names it rather than copying
it.
