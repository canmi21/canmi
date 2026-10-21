/** How long a file and a comment run, and what a comment holds; the lines and comments parts. */
let softLines = 500
let hardLines = 1000

/** A block's body lines, those of the block opening a file, and the columns every line keeps. */
let blockLines = 6
let openingLines = 10
let columns = 100

/** The body lines a block aims at, past which the plain part warns. */
let aimLines = 2

/** A divider of repeated characters, which a module boundary should be instead. */
let separator = /^\s*(?:\/\/|#|\*|\/\*)\s*([-=*#~_])\1{2,}/

let doc = "docs/code.md"
let rules: array<Rule.t> = [
  {
    name: "file-short",
    says: "A file of ours aims under `softLines`, and one over `hardLines` fails",
    doc,
    held: Check("lines"),
  },
  {
    name: "comment-short",
    says: "A comment block is `blockLines` body lines, `openingLines` opening a file, `columns` wide",
    doc,
    held: Check("comments"),
  },
  {
    name: "comment-plain",
    says: "A comment aims at `aimLines` body lines and states, its prose with no colon and no dash",
    doc,
    held: Check("plain"),
  },
  {
    name: "no-separators",
    says: "No comment is a divider of repeated characters",
    doc,
    held: Check("comments"),
  },
  {
    name: "citations-resolve",
    says: "A link, a cited doc and a section quoted beside it all exist",
    doc: "docs/agent-protocol.md",
    held: Check("refs"),
  },
  {
    name: "marker-waits",
    says: "A FIXME or TODO says what it waits for",
    doc,
    held: Pending("telling a marker that names what it waits on from one that does not"),
  },
  {
    name: "generated-marked",
    says: "Generated code opens with @generated and is marked linguist-generated",
    doc: "docs/repos.md",
    held: Pending("a list of each repository's generators and what they write"),
  },
]
