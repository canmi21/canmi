/** Where what is not done is kept, docs/planning.md, as Open, Deferred or not done at all. */
let doc = "docs/planning.md"

/** The id space of the workspace's own RFCs, which a repository's `[rfcs] ids` may also name. */
let workspaceSpace = "workspace"

/** Repositories retired, a commit in one kept as written in an RFC and never checked. */
let retired = ["platform", "infra"]

/** Where a repository keeps its RFCs, one directory deep in areas. */
let rfcDirectory = "docs/rfcs"

/** Where an RFC stands, in the order it moves. Accepted and landed are history. RFC 8q1af. */
let statuses = ["draft", "decided", "accepted", "landed", "declined"]

/** The place, `yyyy-mmdd-nn`, from which an RFC is of the new form. RFC 8q1af. */
let newFormFrom = "2026-1101-02"

/** RFCs placed on that day in other repositories before the form was set, history as they stand. */
let oldForm = ["stc9g", "jq7tx", "42a5w", "fds59", "okz12"]

/** The only statuses an RFC of the new form may have. */
let newStatuses = ["draft", "decided", "declined"]

/** Frontmatter keys an RFC of the new form does not have, as the model's plan holds them. */
let newFormKeysRefused = ["blocked-by", "underway", "commits"]

/** Headings, at any level, an RFC of the new form does not have, matched by their first word. */
let newFormHeadingsRefused = ["Steps", "Plan", "Order", "Next", "Roadmap", "Phase"]

/** The repositories whose docs `docs-in-force` reads beside the workspace's, by path prefix. */
let docsReadIn = ["monoflake/"]

/** The repositories keeping a checklist of their own, whose todo may name a row of it. */
let rowsKept = ["monoflake/platform"]

/** A date in force a doc may state, such as an expiry, each as a file and the date. */
let datesInForce: array<(string, string)> = []

/** An RFC's sections, in the only order they may stand. RFC 2ut6h. */
let sections = ["Question", "Options", "Evidence", "Decision", "State"]

let rules: array<Rule.t> = [
  {
    name: "reference-generated",
    says: "model/reference/rules.md is the rules as the model gives them, written by `mise run docs` and never by hand",
    doc: "docs/model.md",
    held: Check("generated"),
  },
  {
    name: "deferred-named",
    says: "A deferred item waits on an RFC that exists and waives only rules a part can",
    doc,
    held: Check("deferred"),
  },
  {
    name: "plan-named",
    says: "An item of the plan has a unique id, names registered repositories, items and RFCs that exist, an acyclic order, and a check part, commit or dated observation that holds it",
    doc,
    held: Check("plan"),
  },
  {
    name: "todo-cites-open",
    says: "A %todo or a todo! names an open row or a draft RFC, and none names one closed",
    doc,
    held: Check("todos"),
  },
  {
    name: "docs-in-force",
    says: "A doc under docs/ and an AGENTS.md hold only the rules in force, no rule's date, decider or history",
    doc: "docs/rfcs.md",
    held: Check("docs"),
  },
  {
    name: "rfc-form",
    says: "An RFC is named, placed and written as RFC 2ut6h has it, its id and place unique in its id space",
    doc: "docs/rfcs.md",
    held: Check("rfcs"),
  },
]
