/**
 * After a feat, refactor, build or perf commit that touched no rules, asks whether it settled
 * a question nobody wrote down, without blocking. See docs/commits.md, "Enforcement".
 */
let deciding = ["feat", "refactor", "build", "perf"]
/** The workspace keeps its rules in docs/ and model/, a project in spec/. */
let rules = ["spec/", "docs/", "model/", "AGENTS.md"]

let commits = command =>
  Jj_command.invocations(command)->Array.some(((subcommand, _)) =>
    subcommand == "commit" || subcommand == "ci"
  )

let context = (payload: Payload.t): option<string> =>
  if !commits(Payload.command(payload)) {
    None
  } else {
    let cwd = Payload.cwd(payload)
    let subject =
      Payload.jj(
        ~cwd,
        ["log", "--no-graph", "-r", "@-", "-T", "description.first_line()"],
      )->String.trim
    let kind = subject->String.split(":")->Array.getUnsafe(0)->String.split("(")->Array.getUnsafe(0)
    let paths =
      Payload.jj(~cwd, ["diff", "--summary", "-r", "@-"])
      ->String.split("\n")
      ->Array.filterMap(line =>
        switch line->String.indexOf(" ") {
        | -1 => None
        | at => Some(line->String.slice(~start=at + 1))
        }
      )
    if (
      !(deciding->Array.includes(kind->String.trim)) ||
      paths == [] ||
      paths->Array.some(path => rules->Array.some(rule => path->String.startsWith(rule)))
    ) {
      None
    } else {
      Some(
        `Committed \`${subject}\` without touching the rules -- docs/, model/, a project's spec/ -- ` ++
        "or AGENTS.md. If this change settled a question -- chose one option over another, " ++
        "accepted a tradeoff, added a tool, established a convention -- record the decision and " ++
        "its reasoning now, while it is still in context: a value a program can check in " ++
        "model/rules/, the why in docs/. Put it in the commit itself rather than a follow-up. If " ++
        "it settled nothing, say so briefly and move on. docs/agents/agent-protocol.md defines " ++ "what belongs in the rules and what in a code comment.",
      )
    }
  }
