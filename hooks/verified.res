/** Before a jj command making a commit: refuse it until verify passed at this working copy. */
let label = repo =>
  repo == Registry.root
    ? "mise run check"
    : repo->String.startsWith(Registry.repos ++ "/")
    ? `mise run check ${Registry.label(repo)}`
    : "the repository's verify"

/** The exit status the harness reads: 2 refuses the command, with the reason on stderr. */
let handle = (payload: Payload.t): int => {
  let command = Payload.command(payload)
  let places = Jj_command.placed(command, ~cwd=Payload.cwd(payload), Commits.committing)
  if places == [] || Jj_command.skipped(command)->Array.includes("verify") {
    0
  } else {
    let unverified = places->Array.filterMap(at => {
      let repo = Payload.jj(~cwd=at, ["workspace", "root"])->String.trim
      repo == "" || Stamp.holds(repo) ? None : Some(repo)
    })
    switch unverified[0] {
    | None => 0
    | Some(repo) =>
      Console.error(
        `Commit refused by hooks/verified.res: ${repo} has not passed verify at this working ` ++
        `copy.\n\nRun \`${label(
            repo,
          )}\` from the workspace, then commit again. To commit ` ++ `without it, name the gate: \`SKIP=verify jj commit ...\`. See docs/commits.md.`,
      )
      2
    }
  }
}
