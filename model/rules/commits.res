/** What a commit message is; the commit hook and the commits part both read it. */
let types = ["feat", "fix", "docs", "refactor", "perf", "test", "build", "ci", "chore", "revert"]
let subjectWidth = 96
/** A body's ceiling in lines, trailers not counted; three is the aim. */
let bodyLines = 5

/** Each vendor's trailer, by the name it opens with and the one address it takes. */
let trailers = [
  ("Claude", "noreply@anthropic.com"),
  ("Codex", "codex@openai.com"),
  ("Grok", "noreply@x.ai"),
]

/** Every jj subcommand that takes -m, so every one that can write a description. */
let describing = ["commit", "ci", "describe", "desc", "split", "new", "squash", "metaedit"]

/** Per repository, the commit its history check starts after; what came before stays as written. */
let since = [
  ("workspace", "71c246fe"),
  ("canmi/web", "8f2d6769"),
  ("canmi/lib", "0e2abfcf"),
  ("canmi/rfcs", "76bab398"),
  ("seam", "ae2feb96"),
  ("monoflake/platform", "607b60cb"),
  ("monoflake/cloud", "root()"),
  ("apps/rdm", "ecaa6b03"),
  ("apps/cue", "5655f8a0"),
  ("apps/still", "18ed09a1"),
  ("console", "fb308466"),
]

/** The jj subcommands that make a commit, and so wait on a passing verify. */
let committing = ["commit", "ci"]

/** The escape a command names to pass a gate, `SKIP=verify jj commit ...`, as pre-commit has it. */
let skip = "SKIP"
let skippable = ["verify"]

let doc = "docs/commits.md"
let rules: array<Rule.t> = [
  {
    name: "commit-type",
    says: "A subject is `type: subject`, its type one of `types`, a scope optional",
    doc,
    held: Check("commits"),
  },
  {name: "subject-lowercase", says: "A subject starts lowercase", doc, held: Check("commits")},
  {name: "subject-no-period", says: "A subject ends without a period", doc, held: Check("commits")},
  {
    name: "subject-width",
    says: "A subject is `subjectWidth` characters at most, the type included",
    doc,
    held: Check("commits"),
  },
  {
    name: "subject-imperative",
    says: "A subject is in the imperative mood: add, not added or adds",
    doc,
    held: Pending("a list of the past and third-person forms a subject opens with"),
  },
  {
    name: "body-short",
    says: "A body is `bodyLines` lines at most, trailers not counted",
    doc,
    held: Check("commits"),
  },
  {
    name: "body-plain",
    says: "A body is plain text: no backticks, asterisks, headings, bullets or links",
    doc,
    held: Check("commits"),
  },
  {
    name: "trailer-shape",
    says: "A co-author trailer is one of `trailers`, naming the model",
    doc,
    held: Check("commits"),
  },
  {
    name: "message-checked",
    says: "Every jj subcommand that takes -m has its message checked before it runs",
    doc,
    held: Hook("hooks/commit"),
  },
  {
    name: "describing-complete",
    says: "`describing` is every jj subcommand that takes -m",
    doc,
    held: Pending("jj's own help read for every subcommand that accepts -m"),
  },
  {
    name: "since-recorded",
    says: "Every repository the registry lists has its `since`",
    doc,
    held: Check("commits"),
  },
  {
    name: "verified-before-commit",
    says: "A `committing` command waits until verify passed at the working copy, `skip` aside",
    doc,
    held: Hook("hooks/verified"),
  },
  {
    name: "main-covers-work",
    says: "A turn ends with main covering every described, non-empty commit",
    doc,
    held: Hook("hooks/bookmark"),
  },
]
