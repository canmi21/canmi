/**
 * `each <task> [args] [--dry-run]` runs the task in every repository declaring it, one at a time.
 */
let main = (argv: array<string>): int => {
  let dry = argv->Array.some(arg => arg == "-n" || arg == "--dry-run")
  let rest = argv->Array.filter(arg => arg != "-n" && arg != "--dry-run")
  switch rest[0] {
  | None =>
    Console.error("usage: mise run each <task> [args] [--dry-run]")
    2
  | Some(task) =>
    // On past a failure, so one repository's red run does not hide the rest.
    Node.run(
      ~cwd=Registry.root,
      "mise",
      Array.flat([
        ["run"],
        dry ? ["-n"] : [],
        ["--jobs", "1", "--continue-on-error", `//repos/...:${task}`],
        rest->Array.slice(~start=1),
      ]),
    )
  }
}

if Node.isMain {
  Node.exit(main(Node.args()))
}
