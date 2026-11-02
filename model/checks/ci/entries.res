/** ci-native-steps, ci-entries and ci-shell-minimal, docs/ci.md, "CI orchestrates". */
open Runs

/** The structural words and closers of shell that name no command. */
let structure = [
  "",
  "then",
  "else",
  "do",
  "done",
  "fi",
  "esac",
  "}",
  ")",
  "in",
  "for",
  "case",
  "while",
]

/** Whether a head is a path, a dynamic word or an expression, which is not decided here. */
let undecided = head => ["$", "\"", "'"]->Array.some(mark => head->String.startsWith(mark))

/** Each step with a run block of a document, its file, job and name beside it. */
let runs = (documents: array<document>) =>
  documents->Array.flatMap(document =>
    document.jobs->Array.flatMap(job =>
      job.steps->Array.filterMap(
        step =>
          step.run->Option.map(run => (`${document.file}: job ${job.id} step "${step.name}"`, run)),
      )
    )
  )

/** The entry a segment calls, such as `mise run check`, or none. */
let entry = segment => {
  let words = bare(segment.text)->String.split(" ")
  switch words->Array.getUnsafe(0) {
  | "mise" if words->Array.get(1) == Some("run") =>
    Some(words->Array.slice(~start=0, ~end=3)->Array.join(" "))
  | first if Toolchain.entryCommands->Array.includes(first) =>
    Some(words->Array.slice(~start=0, ~end=2)->Array.join(" "))
  | _ => None
  }
}

/** The distinct entries a run calls. */
let called = run =>
  run
  ->commands
  ->Array.filterMap(entry)
  ->Array.reduce([], (found, one) => found->Array.includes(one) ? found : [...found, one])

/** ci-native-steps, a step running several stages' entries. */
let nativeProblems = (documents: array<document>): array<string> =>
  runs(documents)->Array.filterMap(((at, run)) => {
    let many = called(run)
    many->Array.length > 1
      ? Some(`${at} chains ${Int.toString(many->Array.length)} entries, ${many->Array.join(", ")}`)
      : None
  })

/** Where a CI-only entry sits, the repository's `.github/`, however the workflow reaches it. */
let entryHome = path => {
  let bare =
    path
    ->String.replaceRegExp(
      /^(?:\$GITHUB_WORKSPACE|\$\{GITHUB_WORKSPACE\}|\$\{\{\s*github\.workspace\s*\}\})\//,
      "",
    )
    ->String.replaceRegExp(/^(?:\.\.?\/)+/, "")
  bare->String.startsWith(".github/") && bare->String.endsWith(".res.mjs")
}

/** The scripts a run hands to node, read over its whole text so an expression's string counts. */
let nodeScripts = run =>
  run
  ->String.match(/(?<![\w.\/-])node\s+["']?[^\s"';|&)]+/g)
  ->Option.getOr([])
  ->Array.filterMap(call => call)
  ->Array.map(call => call->String.replaceRegExp(/^node\s+["']?/, ""))

/** What follows the first of `marks` in a wrapper's words, or none where it has no such mark. */
let after = (words: array<string>, marks) =>
  words
  ->Array.findIndex(word => marks->Array.includes(word))
  ->(at => at < 0 ? None : Some(words->Array.slice(~start=at + 1)))

/**
 * Whether a command is a mise task, plumbing, `pnpm install` or `pnpm exec`, a structural word, or
 * a wrapper whose wrapped command passes. A shell inside a wrapper has no pass of its own.
 */
let rec passes = (words: array<string>) => {
  let command = words->Array.getUnsafe(0)
  let second = words->Array.get(1)
  let wrapped = inner =>
    switch inner {
    | Some(rest) if rest != [] => passes(rest)
    | _ => false
    }
  structure->Array.includes(command) ||
  undecided(command) ||
  Toolchain.plumbingCommands->Array.includes(command) ||
  command == "node" ||
  command == "mise" && second == Some("run") ||
  command == "pnpm" && (second == Some("install") || second == Some("exec")) ||
  command == "sudo" &&
    wrapped(
      Some(words->Array.slice(~start=1)->Array.filter(word => !(word->String.startsWith("-")))),
    ) ||
  command == "mise" && second == Some("exec") && wrapped(after(words, ["--"])) ||
  (command == "nix" && second == Some("shell") && wrapped(after(words, ["--command", "-c"])))
}

/**
 * ci-entries, a step calls a mise task, plumbing, or a CI-only entry under `.github/`, once to a
 * step, a form rule refused where a commit lands on a main line.
 */
let entryFindings = (documents: array<document>): array<Form_layer.finding> =>
  runs(documents)->Array.flatMap(((at, run)) => {
    let others =
      run
      ->commands
      ->Array.map(segment => bare(segment.text)->String.split(" "))
      ->Array.filter(words => !passes(words))
      ->Array.map(words => `${at} runs ${words->Array.getUnsafe(0)}, which is no entry`)
    let places =
      run
      ->nodeScripts
      ->Array.filter(path => !entryHome(path))
      ->Array.map(path => `${at} runs node ${path}, which is no entry under .github/`)
    Array.concat(others, places)
    ->Array.reduce([], (found, says) => found->Array.includes(says) ? found : [...found, says])
    ->Array.map((says): Form_layer.finding => {rule: "ci-entries", says, onset: () => None})
  })

/** The same findings as plain lines. */
let entryProblems = (documents: array<document>): array<string> =>
  entryFindings(documents)->Array.map(finding => finding.says)

/** The command substitutions of a run, `$(...)` without arithmetic or nesting. */
let substitutions = run => run->String.match(/\$\((?!\()[^()]*\)/g)->Option.getOr([])

/** Whether a segment only prepares or passes an output, which is no command of the step's own. */
let preparation = segment =>
  Toolchain.preparationCommands->Array.includes(head(segment)) ||
    ["GITHUB_OUTPUT", "GITHUB_ENV", "GITHUB_PATH"]->Array.some(name =>
      segment.text->String.includes(name)
    )

/** The kinds of orchestration a run holds, none for one command and its preparation. */
let shellKinds = run => {
  let run = run->String.replaceRegExp(/\$\{\{[^}]*\}\}/g, "EXPRESSION")
  let segments = run->commands
  let passes = run->String.includes("GITHUB_OUTPUT") || run->String.includes("GITHUB_ENV")
  let opens = names => segments->Array.some(segment => names->Array.includes(opening(segment)))
  let shots =
    segments->Array.filter(segment =>
      !segment.piped &&
      !(structure->Array.includes(head(segment))) &&
      head(segment) != "" &&
      !preparation(segment)
    )
  [
    (opens(["for", "while", "until"]), "a loop"),
    (opens(["case"]), "a case"),
    (opens(["if", "elif"]), "a branch"),
    (
      segments->Array.some(segment =>
        Toolchain.parserAlways->Array.includes(head(segment)) ||
          (segment.piped && Toolchain.parserCommands->Array.includes(head(segment)))
      ),
      "a parse",
    ),
    (!passes && run->substitutions->Array.length > 0, "a value carried between commands"),
    (
      opens(["sleep", "retry"]) || segments->Array.some(segment => head(segment) == "sleep"),
      "a retry",
    ),
    (
      !opens(["for", "while", "until", "case", "if", "elif"]) && shots->Array.length > 1,
      "several commands in sequence",
    ),
  ]->Array.filterMap(((found, kind)) => found ? Some(kind) : None)
}

/** Whether a step is named in `Toolchain.shellExempt`, which says why. */
let exempt = (document: document, ~name) =>
  Toolchain.shellExempt->Array.some(((file, step, _)) => document.file == file && step == name)

/** ci-shell-minimal, one finding for each kind of shell a step holds beyond its call. */
let shellFindings = (documents: array<document>): array<Form_layer.finding> =>
  documents->Array.flatMap(document =>
    document.jobs->Array.flatMap(job =>
      job.steps->Array.flatMap(
        step =>
          switch step.run {
          | Some(run) if !exempt(document, ~name=step.name) =>
            let at = `${document.file}: job ${job.id} step "${step.name}"`
            run
            ->shellKinds
            ->Array.map(
              (kind): Form_layer.finding => {
                rule: "ci-shell-minimal",
                says: `${at} holds ${kind} in its shell`,
                onset: () => None,
              },
            )
          | _ => []
          },
      )
    )
  )

/** The same findings as plain lines. */
let shellProblems = (documents: array<document>): array<string> =>
  shellFindings(documents)->Array.map(finding => finding.says)
