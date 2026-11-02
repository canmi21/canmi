/** Refuses trash on a cache a tool writes again and on the pnpm global store. */
/** The operands of a trash, past its flags. */
let operands = (arguments: array<string>) =>
  arguments->Array.filter(word => !(word->String.startsWith("-")) || word == "-")

/** Where an operand points, a leading tilde read as home. */
let resolved = (operand, ~cwd) => {
  let home = Node.env->Dict.get("HOME")->Option.getOr("")
  Node.resolve([
    cwd,
    operand == "~" || operand->String.startsWith("~/")
      ? home ++ operand->String.slice(~start=1)
      : operand,
  ])
}

/** Whether `needle`, a path of one or more names, sits in `path` on whole names. */
let within = (path, needle) => ("/" ++ path ++ "/")->String.includes("/" ++ needle ++ "/")

/** Why a path may not be trashed, or none where it may. */
let reason = (path): option<string> =>
  switch Delegation.stores->Array.find(store => within(path, store)) {
  | Some(_) => Some(`${path} is inside the pnpm global store, which nothing touches`)
  | None =>
    Delegation.caches
    ->Array.find(((name, _)) => within(path, name))
    ->Option.map(((name, clean)) => `${path} is inside ${name}, a cache cleared by ${clean}`)
  }

/** The exit status the harness reads, 2 refusing the command with the reason on stderr. */
let refuse = (payload: Payload.t): int =>
  try {
    let command = Stale_jobs.withoutHeredocs(Payload.command(payload))
    let cwd = Payload.cwd(payload)
    let found = Jj_command.segments(command)->Array.flatMap(segment =>
      switch Jj_command.programOf(segment) {
      | Some(("trash", rest)) =>
        operands(rest)->Array.filterMap(operand => reason(resolved(operand, ~cwd)))
      | _ => []
      }
    )
    switch found[0] {
    | None => 0
    | Some(why) =>
      Console.error(
        `trash refused by hooks/cache/trash.res: ${why}.\n` ++
        "A cache a tool writes again is cleared by its own tool's clean, which frees the space trash does not.\n" ++ "The rule: cache-not-trashed in model/rules/delegation.res, and docs/toolchain.md, \"An agent removes what it made with rm, and trashes what it did not\".",
      )
      2
    }
  } catch {
  | _ => 0
  }
