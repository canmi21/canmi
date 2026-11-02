/** Refuses a jj command that makes a commit until verify passed at this working copy. */
let label = repo =>
  repo == Registry.root
    ? "mise run check"
    : repo->String.startsWith(Registry.repos ++ "/")
    ? `mise run check ${Registry.label(repo)}`
    : "the repository's verify"

/** Why a working copy is refused, said by what the comparison with the stamp found. */
let reason = (verdict: Stamp.verdict) =>
  switch verdict {
  | Held => ""
  | Unstamped => "has not passed verify at this working copy"
  | Changed(paths) =>
    let shown = paths->Array.slice(~start=0, ~end=5)->Array.join(", ")
    let more = paths->Array.length - 5
    `has changed since verify passed, ${shown}${more > 0 ? `, and ${more->Int.toString} more` : ""}`
  | Failed(status, said) =>
    `could not be compared with the stamp, jj diff exited ${status->Int.toString}: ${said}`
  | TimedOut(ms) =>
    `could not be compared with the stamp, jj diff timed out after ${ms->Int.toString} ms`
  }

/** The exit status the harness reads, 2 refusing the command with the reason on stderr. */
let handle = (payload: Payload.t): int => {
  let command = Payload.command(payload)
  let places = Jj_command.placed(command, ~cwd=Payload.cwd(payload), Commits.committing)
  if places == [] || Jj_command.skipped(command)->Array.includes("verify") {
    0
  } else {
    let unverified = places->Array.filterMap(at => {
      let repo = Payload.jj(~cwd=at, ["workspace", "root"])->String.trim
      switch repo == "" ? Stamp.Held : Stamp.verdict(repo) {
      | Held => None
      | verdict => Some((repo, verdict))
      }
    })
    switch unverified[0] {
    | None => 0
    | Some((repo, verdict)) =>
      Console.error(
        `Commit refused by hooks/gates/verified.res: ${repo} ${reason(verdict)}.\n\nRun \`${label(
            repo,
          )}\` from the workspace, then commit again. To commit ` ++ `without it, name the gate: \`SKIP=verify jj commit ...\`. See docs/commits.md.`,
      )
      2
    }
  }
}
