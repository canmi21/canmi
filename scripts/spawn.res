/** A gate's one command, run in the repository with its output as it arrives, ending as it ends. */
let whitespace = /\s+/

/** The words `value` holds, split as an unquoted shell variable is, or none for none. */
let words = (value: option<string>) =>
  value
  ->Option.getOr("")
  ->String.splitByRegExp(whitespace)
  ->Array.filterMap(word => word)
  ->Array.filter(word => word != "")

/** Runs `command` from the repository's root and exits with its status. */
let exec = (command, commandArgs) => {
  let ran = Node.spawnSync(command, commandArgs, {stdio: "inherit"})
  switch ran.error->Nullable.toOption {
  | Some(error) => Console.error(`${command}: ${error->JsExn.message->Option.getOr("")}`)
  | None => ()
  }
  Node.exit(ran.status->Nullable.getOr(1))
}
