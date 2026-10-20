/** What a repository's README, description and license carry; the settings part reads it. */
let doc = "docs/readme.md"
let rules: array<Rule.t> = [
  {
    name: "one-license",
    says: "The workspace keeps one LICENSE, at its root",
    doc,
    held: Check("settings"),
  },
  {
    name: "description-short",
    says: "A repository's description is one sentence of four to eight words, ending in a full stop",
    doc,
    held: Pending("each repository's description read from the forge"),
  },
]
