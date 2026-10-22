/** Where what is not done is kept, docs/planning.md, as Open, Deferred or not done at all. */
let doc = "docs/planning.md"

/** The id space of the workspace's own RFCs, which a repository's `[rfcs] ids` may also name. */
let workspaceSpace = "workspace"

/** Repositories retired, a commit in one kept as written in an RFC and never checked. */
let retired = ["platform", "infra"]

/** Where a repository keeps its RFCs, one directory deep in areas. */
let rfcDirectory = "docs/rfcs"

/** Where an RFC stands, in the order it moves, the first two still open. RFC p992n. */
let statuses = ["draft", "accepted", "landed", "declined"]

/** An RFC's sections, in the only order they may stand. RFC 2ut6h. */
let sections = ["Question", "Options", "Evidence", "Decision"]

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
    held: Pending(
      "monoflake/platform holds its own, model/checks/layout/code.res; the workspace reading every repository's",
    ),
  },
  {
    name: "rfc-form",
    says: "An RFC is named, placed and written as RFC 2ut6h has it, its id and place unique in its id space",
    doc: "docs/rfcs.md",
    held: Check("rfcs"),
  },
]
