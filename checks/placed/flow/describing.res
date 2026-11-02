/** `describing-complete`, model/rules/commits.res, read from the version control's own help. */
let listed = /^  ([a-z][a-z-]*)\s{2,}\S/

/** The subcommands its help lists, those under the Commands heading. */
let commands = (help: string): array<string> =>
  help
  ->String.split("\n")
  ->Array.filterMap(line =>
    switch listed->RegExp.exec(line)->Option.map(RegExp.Result.matches) {
    | Some([Some(name)]) => Some(name)
    | _ => None
    }
  )

/** Whether one subcommand's help lists a -m option, which writes a description. */
let takesMessage = (help: string) => /^\s+-m, --message\b/m->RegExp.test(help)

/** Each finding for the subcommands that take -m, and the names that are no subcommand. */
let problems = (~takes: array<string>, ~unknown: array<string>) =>
  Array.concat(
    takes
    ->Array.filter(name => !(Commits.describing->Array.includes(name)))
    ->Array.map(name => `${name} takes -m, and Commits.describing does not list it`),
    unknown->Array.map(name => `Commits.describing lists ${name}, which is no subcommand`),
  )

let program = "jj"
let help = (name: array<string>) => Node.output(program, [...name, "--help"])

/** The subcommands that take -m, set against `Commits.describing`. */
let main = (): array<string> => {
  let all = commands(help([]))
  if all == [] {
    ["the help lists no subcommand, so describing cannot be read"]
  } else {
    problems(
      ~takes=all->Array.filter(name => takesMessage(help([name]))),
      ~unknown=Commits.describing->Array.filter(name => help([name])->String.trim == ""),
    )
  }
}
