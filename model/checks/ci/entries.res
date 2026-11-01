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

/** ci-entries, a command that is neither an entry nor plumbing, once to a step. */
let entryProblems = (documents: array<document>): array<string> =>
  runs(documents)->Array.flatMap(((at, run)) =>
    run
    ->commands
    ->Array.map(head)
    ->Array.filter(command =>
      !(structure->Array.includes(command)) &&
      !undecided(command) &&
      !(command->String.startsWith("./")) &&
      !(Toolchain.entryCommands->Array.includes(command)) &&
      !(Toolchain.plumbingCommands->Array.includes(command))
    )
    ->Array.reduce([], (found, command) =>
      found->Array.includes(command) ? found : [...found, command]
    )
    ->Array.map(command => `${at} runs ${command}, which is no entry`)
  )

/** ci-shell-minimal, a loop, a parse, a retry or a branch beyond passing outputs. */
let shellProblems = (documents: array<document>): array<string> =>
  runs(documents)->Array.flatMap(((at, run)) => {
    let segments = run->commands
    let passes = run->String.includes("GITHUB_OUTPUT") || run->String.includes("GITHUB_ENV")
    let kinds =
      [
        (
          segments->Array.some(segment =>
            ["for", "while", "until"]->Array.includes(opening(segment))
          ),
          "a loop",
        ),
        (segments->Array.some(segment => opening(segment) == "case"), "a case"),
        (
          !passes &&
          segments->Array.some(segment => ["if", "elif"]->Array.includes(opening(segment))),
          "a branch",
        ),
        (
          segments->Array.some(segment =>
            segment.piped && Toolchain.parserCommands->Array.includes(head(segment))
          ),
          "a parse",
        ),
        (
          segments->Array.some(segment => ["sleep", "retry"]->Array.includes(head(segment))),
          "a retry",
        ),
      ]->Array.filterMap(((found, kind)) => found ? Some(kind) : None)
    kinds->Array.map(kind => `${at} holds ${kind} in its shell`)
  })
