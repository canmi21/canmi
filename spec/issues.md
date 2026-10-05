# Issues

Open questions every project shares. Each project's own are its `spec/issues.md`; how the three
planning files divide the work is [planning.md](planning.md).

## Every project is to reach 95% line coverage, and none is measured against it yet

The target is the whole workspace's, every repository below it included: 95% of lines covered by a
test that would fail if they broke. It is where lib's `axum-governor` already holds itself -- lib's
`spec/axum-governor/testing.md` -- and nowhere else. What is open is the way there: how coverage is
measured in each language here (Rust, TypeScript, Svelte), whether a gate holds a repository to it
once it gets there or only reports, and the order the repositories are brought up in. There is no
time for it yet, which is why it is a question and not a todo entry.

How `axum-governor` reads the number is the one reading written down so far: a function that
orchestrates tested functions is covered by testing its orchestration -- call order,
short-circuits, data threading -- not by re-testing every branch of what it calls; and an I/O-heavy
module may fall below where the uncovered branches are error paths with no observable behavior,
saying so in the module.

## robots.txt and security.txt are owed by every page, and declared in many places

Every independent page a project deploys answers both files -- [robots.md](robots.md) -- and today
each project declares its own hosts: web its page hosts in `libs/robots`, the platform its service
hosts through the gateway. The API side already has one layer in front of every service that answers
these files once, the gateway. Whether every deployed page gets a layer in front of it the same way,
so the files are declared once rather than per project and per host, is not decided, and neither is
what that layer would be. web's service domains' pages, `landing`, answer neither file yet, and are
waiting on this.
