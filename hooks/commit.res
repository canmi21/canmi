/** Refuses a jj command that writes a malformed description, then runs jj fix. */
/** Every -m value given to a subcommand that can write a description. */
let messages = command =>
  Jj_command.invocations(command)
  ->Array.filter(((subcommand, _)) => Commits.describing->Array.includes(subcommand))
  ->Array.flatMap(((_, arguments)) =>
    arguments->Array.filterMapWithIndex((word, index) =>
      if word == "-m" || word == "--message" {
        arguments[index + 1]
      } else if word->String.startsWith("--message=") {
        Some(word->String.slice(~start="--message="->String.length))
      } else {
        None
      }
    )
  )

/** The exit status the harness reads, 2 refusing the command with the reasons on stderr. */
let refuse = (payload: Payload.t): int => {
  let problems = messages(Payload.command(payload))->Array.flatMap(History.problems)
  if problems != [] {
    Console.error("Commit message rejected by hooks/commit.res:\n")
    problems->Array.forEach(problem => Console.error(`  - ${problem}\n`))
    Console.error(
      "Fix the message and run the command again. Scope is omitted in most cases.\n" ++ "The rules: model/rules/commits.res, and the why in docs/commits.md",
    )
    2
  } else {
    0
  }
}

/** Runs jj fix over what the command describes, once every gate passed. */
let fix = (payload: Payload.t) => {
  let command = Payload.command(payload)
  if messages(command) != [] {
    // Where each describing jj runs, past any `cd` before it, so a session's cwd never decides.
    let places =
      Jj_command.placed(command, ~cwd=Payload.cwd(payload), Commits.describing)->Array.reduce([], (
        seen,
        at,
      ) => seen->Array.includes(at) ? seen : seen->Array.concat([at]))
    // jj's repository config is not versioned, so the workspace's jujutsu.toml is named here,
    // wherever below it the commit is made.
    let home = Node.env->Dict.get("HOME")->Option.getOr("")
    let env = Node.envCopy(Node.env)
    env->Dict.set("JJ_CONFIG", `${home}/.config/jj/config.toml:${Registry.root}/jujutsu.toml`)
    places->Array.forEach(cwd =>
      if Payload.jj(~cwd, ["workspace", "root"])->String.trim != "" {
        // The commit just written and its working copy alone, as the ignore files on disk fit them.
        // A broken formatter is not a reason to refuse work, so its failure is passed over.
        Node.spawnWithEnv(
          "jj",
          ["fix", "-s", "mutable() & (@ | @-)"],
          {cwd, env, stdio: "ignore"},
        )->ignore
      }
    )
  }
}
