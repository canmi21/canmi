/** What is not done and where it is kept, docs/planning.md: Open, Deferred, or not done at all. */
let doc = "docs/planning.md"

let rules: array<Rule.t> = [
  {
    name: "deferred-named",
    says: "A deferred item names repositories the registry lists, an RFC that exists, and only rules a part can waive",
    doc,
    held: Check("deferred"),
  },
  {
    name: "todo-cites-open",
    says: "A %todo or a todo! names an open row or a draft RFC, and none names one closed",
    doc,
    held: Pending("each repository's %todo and todo! read against its own open rows and RFCs"),
  },
]
