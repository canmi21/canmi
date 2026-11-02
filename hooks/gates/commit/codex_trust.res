/**
 * After a commit that changes the hooks under `.codex/`, reminds the agent to tell the author to
 * trust Codex by hand, codex-trust-reminded.
 */
let committed = command =>
  Jj_command.invocations(command)->Array.some(((subcommand, _)) =>
    subcommand == "commit" || subcommand == "ci"
  )

/** Whether any of the files lies under the directory of the hooks Codex reads. */
let touches = (files: array<string>) =>
  files->Array.some(file => file->String.startsWith(Delegation.codexHooksDir))

let reminder = "This commit changed the hooks under .codex/. Codex reads them only once the author trusts them, and an agent cannot do that. Tell the author now, in this reply, to trust Codex by hand, without waiting for the next Codex seat. docs/agents/delegation.md says where."

/** The files the newest commit changed, read where the commit was made. */
let changed = (payload: Payload.t) => {
  let command = Payload.command(payload)
  let target = switch Jj_command.repository(command) {
  | Some(path) => ["-R", path]
  | None => []
  }
  Payload.jj(
    ~cwd=Payload.cwd(payload),
    [...target, "diff", "--ignore-working-copy", "-r", "@-", "--name-only"],
  )
  ->String.split("\n")
  ->Array.map(String.trim)
  ->Array.filter(file => file != "")
}

/** The reminder where the command committed and `files` of its commit touch `.codex/`. */
let remind = (payload: Payload.t, ~files) =>
  committed(Payload.command(payload)) && touches(files()) ? Some(reminder) : None

let context = (payload: Payload.t): option<string> => remind(payload, ~files=() => changed(payload))
