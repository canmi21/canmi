/** Which tool owns layout and which owns meaning; the settings part reads it. */
/** Each language, its formatter, and its linter. */
let owners = [
  ("TypeScript, JavaScript, Svelte", "oxfmt", "oxlint"),
  ("Rust", "rustfmt", "clippy"),
  ("ReScript", "rescript format", "rescript"),
]

/** oxlint rules off because the formatter already rewrites what they report. */
let overlapping = ["no-irregular-whitespace"]

let doc = "docs/lint-format.md"
let rules: array<Rule.t> = [
  {
    name: "overlap-off",
    says: "Every linter rule in `overlapping` is off in .oxlintrc.json",
    doc,
    held: Check("settings"),
  },
  {
    name: "overlap-measured",
    says: "A new linter's overlap with its formatter is found by feeding the formatter a violation",
    doc,
    held: Pending("a fixture per overlapping rule, formatted and linted"),
  },
  {
    name: "svelte-beside-oxfmt",
    says: "A package.json declaring oxfmt declares svelte beside it",
    doc,
    held: Check("settings"),
  },
  {
    name: "disable-has-reason",
    says: "An oxlint disable comment carries its reason on the same line, after --",
    doc,
    held: Check("comments"),
  },
]
