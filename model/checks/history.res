/** A commit message against model/rules/commits.res, for the commit hook and the history alike. */
let escaped = text => text->String.replaceRegExp(/[.*+?^${}()|[\]\\]/g, "\\$&")

let header = RegExp.fromString(`^(${Commits.types->Array.join("|")})(\\([a-z0-9.-]+\\))?!?: (.+)$`)
let coauthor = /^Co-Authored-By:/i
let trailer = RegExp.fromString(
  `^Co-Authored-By: (?:${Commits.trailers
    ->Array.map(((name, address)) => `${name} [A-Za-z0-9.-]+ <${escaped(address)}>`)
    ->Array.join("|")})$`,
)
/** A trailer line, `Key: value`, which a body's length does not count. */
let trailerLine = /^[A-Za-z][A-Za-z-]*: /
/** What Markdown would render: code, emphasis, a heading, a bullet, a link. */
let marks = /`|\*\*|^#{1,6} |^\s*[-*+] |\[[^\]]*\]\([^)]*\)/

let expected =
  Commits.trailers->Array.map(((name, address)) =>
    `Co-Authored-By: ${name} <Model>-<Version> <${address}>`
  )

/** Every way `message` breaks the rules, each a line to show whoever wrote it. */
let problems = (message: string): array<string> => {
  let lines = message->String.trimEnd->String.split("\n")
  let subject = lines[0]->Option.getOr("")
  switch header->RegExp.exec(subject) {
  | None => [
      `${subject} -- is not a Conventional Commit; expected \`type: subject\`, type one of ${Commits.types->Array.join(
          ", ",
        )}`,
    ]
  | Some(result) =>
    let text = switch result->RegExp.Result.matches {
    | [_, _, Some(text)] => text
    | _ => ""
    }
    let found = []
    let first = text->String.slice(~start=0, ~end=1)
    if first != first->String.toLowerCase {
      found->Array.push(`${subject} -- a subject starts lowercase`)
    }
    if text->String.endsWith(".") {
      found->Array.push(`${subject} -- a subject ends without a period`)
    }
    let width = subject->String.length
    if width > Commits.subjectWidth {
      found->Array.push(
        `${subject} -- is ${Int.toString(width)} characters, the limit ${Int.toString(
            Commits.subjectWidth,
          )}`,
      )
    }
    let rest = lines->Array.slice(~start=1)
    rest->Array.forEach(line => {
      let line = line->String.trim
      if coauthor->RegExp.test(line) && !(trailer->RegExp.test(line)) {
        found->Array.push(`${line} -- a co-author trailer is one of: ${expected->Array.join("; ")}`)
      }
    })
    let body =
      rest->Array.filter(line => line->String.trim != "" && !(trailerLine->RegExp.test(line)))
    if body->Array.length > Commits.bodyLines {
      found->Array.push(
        `${subject} -- the body is ${Int.toString(
            body->Array.length,
          )} lines, at most ${Int.toString(Commits.bodyLines)}`,
      )
    }
    body->Array.forEach(line =>
      if marks->RegExp.test(line) {
        found->Array.push(`${line} -- a body is plain text, no Markdown`)
      }
    )
    found
  }
}

/** Every described commit after `Commits.since` up to the working copy, by its commit. */
let main = (~root): array<string> =>
  Node.output(
    ~cwd=root,
    "jj",
    [
      "log",
      "--no-graph",
      "-r",
      `${Commits.since}..@ & ~empty() & ~description(exact:"")`,
      "-T",
      `commit_id.short() ++ "\\x00" ++ description ++ "\\x01"`,
    ],
  )
  ->String.split("\x01")
  ->Array.filterMap(entry =>
    switch entry->String.trimStart->String.split("\x00") {
    | [id, message] => Some((id, message))
    | _ => None
    }
  )
  ->Array.flatMap(((id, message)) => problems(message)->Array.map(problem => `${id}: ${problem}`))
