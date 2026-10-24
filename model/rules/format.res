/** Which tool owns layout and which owns meaning; the settings part reads it. */
/** What writes a file's layout, or that nothing does, on purpose. */
type formatter =
  | Formats(string)
  | Unformatted

/** Each suffix the repositories share and its formatter; one repository's own is in its model. */
let owners = [
  (".ts", Formats("oxfmt")),
  (".tsx", Formats("oxfmt")),
  (".mts", Formats("oxfmt")),
  (".cts", Formats("oxfmt")),
  (".js", Formats("oxfmt")),
  (".mjs", Formats("oxfmt")),
  (".cjs", Formats("oxfmt")),
  (".jsx", Formats("oxfmt")),
  (".css", Formats("oxfmt")),
  (".json", Formats("oxfmt")),
  (".jsonc", Formats("oxfmt")),
  (".md", Formats("oxfmt")),
  (".svelte", Formats("oxfmt")),
  (".rs", Formats("rustfmt")),
  (".res", Formats("rescript format")),
  (".resi", Formats("rescript format")),
  (".toml", Unformatted),
  (".yaml", Unformatted),
  (".yml", Unformatted),
  (".py", Unformatted),
]

/** Each language's linter, its semantic half alone. */
let linters = [
  ("TypeScript, JavaScript, Svelte", "oxlint"),
  ("Rust", "clippy"),
  ("ReScript", "rescript"),
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
    name: "formatted-on-write",
    says: "After each Edit or Write, a PostToolUse hook formats that file alone by its suffix in `owners`, doing nothing for none or `Unformatted`, and blocking nobody when the formatter fails",
    doc,
    held: Pending(
      "the PostToolUse hook, its formatter finding its configuration upward from the file",
    ),
    escape: ByTool,
  },
  {
    name: "suffix-owned",
    says: "Every suffix a repository tracks has a formatter in `owners` or its model's table, or is registered `Unformatted`",
    doc,
    held: Pending("each repository's tracked files read against `owners` and its own table"),
  },
  {
    name: "edit-after-format",
    says: "Whether an Edit after the hook rewrote its file fails on content it no longer finds is proven in a lane before the hook spreads",
    doc,
    held: Pending("the hook tried in one lane, an Edit made after it formatted the file"),
  },
  {
    name: "disable-has-reason",
    says: "An oxlint disable comment carries its reason on the same line, after --",
    doc,
    held: Check("comments"),
  },
]
