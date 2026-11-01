/** Docs and AGENTS.md against model/rules/planning.res, holding the rules in force and no history. */
let date = `\\d{4}-\\d{2}-\\d{2}`
let decider = `(?:author|advisor|user|integrator)`
let deciding = `(?:decided|agreed|chosen|settled|approved)`

/** The phrases that date a rule's origin or name who chose it, each with what it is. */
let origins = [
  (
    `\\b${deciding}\\s+(?:by|with)\\s+the\\s+${decider}\\s+(?:on|in)\\s+${date}`,
    "a decider and a date",
  ),
  (`\\b(?:learned|${deciding})\\s+on\\s+${date}`, "a date of origin"),
  (`\\bchosen\\s+by\\s+the\\s+advisor\\b`, "a decider"),
  (`\\bprovisional(?:ly)?\\s+(?:chosen|decided|picked)\\s+by\\b`, "a provisional decider"),
  (`\\buntil\\s+${date},\\s+when\\b`, "a history"),
]->Array.map(((pattern, what)) => (RegExp.fromString(pattern, ~flags="gi"), what))

/** The line a character offset falls on, counting from one. */
let lineAt = (text, offset) =>
  text->String.slice(~start=0, ~end=offset)->String.split("\n")->Array.length

/** Whether `file` may carry `matched` because a date in force is listed for it. */
let allowed = (~file, matched) =>
  Planning.datesInForce->Array.some(((path, day)) => path == file && matched->String.includes(day))

/** Each origin or history a doc's text states, a phrase read across wrapped lines. */
let problems = (text, ~file): array<string> =>
  origins->Array.flatMap(((pattern, what)) => {
    pattern->RegExp.setLastIndex(0)
    let rec collect = found =>
      switch pattern->RegExp.exec(text) {
      | None => found
      | Some(result) =>
        let matched = result->RegExp.Result.fullMatch->String.replaceRegExp(/\s+/g, " ")
        let line = lineAt(text, result->RegExp.Result.index)
        collect(
          allowed(~file, matched)
            ? found
            : [
                ...found,
                `${file}:${Int.toString(line)}: "${matched}" is ${what}; the RFCs hold it`,
              ],
        )
      }
    collect([])
  })

/** Whether a tracked path is a doc this rule reads, outside docs/rfcs. */
let read = (relative: string) => {
  let parts = relative->String.split("/")
  !(relative->String.includes("docs/rfcs/")) &&
  (Node.basename(relative) == "AGENTS.md" ||
    (parts->Array.get(0) == Some("docs") && relative->String.endsWith(".md")))
}

/** Every doc of one repository, read from its root. */
let repository = (~root): array<string> =>
  References.tracked(root)
  ->Array.map(path => Node.relative(root, path))
  ->Array.filter(read)
  ->Array.flatMap(relative =>
    problems(References.read(Node.join([root, relative])), ~file=relative)
  )

/** The workspace's docs and those of each active repository under a listed prefix. */
let main = (~root): array<string> =>
  Array.concat(
    repository(~root),
    Waiting.active()
    ->Array.filter(path =>
      Planning.docsReadIn->Array.some(prefix => path->String.startsWith(prefix))
    )
    ->Array.flatMap(path =>
      repository(~root=Node.join([Registry.repos, path]))->Array.map(line => `${path}/${line}`)
    ),
  )
