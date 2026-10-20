/**
 * After a rebase: hand back the rules that changed under the agent, the diff of the rules between
 * the working copy before the rebase and after it. The before is read from jj's operation log, so
 * nothing has to remember it; nothing is said when no rule moved. See docs/commits.md.
 */
let rules = ["spec", "docs", "model", "AGENTS.md"]
let rebasing = "rebase "
let snapshot = "snapshot working copy"
let shownLines = 200

let rebased = command =>
  Jj_command.invocations(command)->Array.some(((subcommand, _)) => subcommand == "rebase")

/** The operation just older than the newest run of rebase operations. */
let before = (~cwd) => {
  let ops =
    Payload.jj(
      ~cwd,
      [
        "op",
        "log",
        "--no-graph",
        "--ignore-working-copy",
        "--limit",
        "40",
        "-T",
        `id.short() ++ "\\t" ++ description ++ "\\n"`,
      ],
    )
    ->String.split("\n")
    ->Array.filterMap(line =>
      switch line->String.indexOf("\t") {
      | -1 => None
      | at => Some((line->String.slice(~start=0, ~end=at), line->String.slice(~start=at + 1)))
      }
    )
  let first = ops->Array.findIndex(((_, description)) => description->String.startsWith(rebasing))
  if first < 0 {
    None
  } else {
    ops
    ->Array.slice(~start=first)
    ->Array.find(((_, description)) =>
      !(description->String.startsWith(rebasing)) && description != snapshot
    )
    ->Option.map(((id, _)) => id)
  }
}

let context = (payload: Payload.t): option<string> =>
  if !rebased(Payload.command(payload)) {
    None
  } else {
    let cwd = Payload.cwd(payload)
    before(~cwd)
    ->Option.map(operation =>
      Payload.jj(
        ~cwd,
        [
          "log",
          "--at-op",
          operation,
          "--ignore-working-copy",
          "--no-graph",
          "-r",
          "@",
          "-T",
          "commit_id",
        ],
      )->String.trim
    )
    ->Option.filter(previous => previous != "")
    ->Option.flatMap(previous => {
      let diff = Payload.jj(
        ~cwd,
        ["diff", "--ignore-working-copy", "--git", "--from", previous, "--to", "@", "--", ...rules],
      )
      if diff->String.trim == "" {
        None
      } else {
        let lines = diff->String.split("\n")
        let more = lines->Array.length - shownLines
        let shown =
          lines->Array.slice(~start=0, ~end=shownLines)->Array.join("\n") ++ (
              more > 0
                ? `\n... ${Int.toString(
                      more,
                    )} more lines; run \`jj diff --git --from ${previous->String.slice(
                      ~start=0,
                      ~end=12,
                    )} --to @ -- ${rules->Array.join(" ")}\` for the rest.`
                : ""
            )
        Some(
          "The rebase brought rule changes from main into this working copy. Read them before the " ++
          "next commit -- they were written elsewhere while this task was underway, and " ++
          "docs/agent-protocol.md says a rebase is where they are taken in. If one changes what " ++
          "this task should do, adjust; if none does, carry on.\n\n" ++
          shown,
        )
      }
    })
  }
