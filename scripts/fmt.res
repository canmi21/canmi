/**
 * A repository's `fmt`, rustfmt over its crates and oxfmt over the files its glob names, `--glob`
 * replacing that glob. `--dry-run` lists what either would change and fails nothing.
 */
let defaultGlob = "**/*.{ts,tsx,mts,cts,js,mjs,cjs,jsx,css,json,jsonc,md,svelte}"

let args = Node.args()
let dry =
  args->Array.includes("--dry-run") ||
  args->Array.includes("-n") ||
  Node.envIs("usage_dry_run", "true")
let glob = switch args->Array.indexOf("--glob") {
| -1 => defaultGlob
| at => args[at + 1]->Option.getOr(defaultGlob)
}

/** One command; a failure ends the task unless it is only a report, as a dry run's are. */
let step = (command, commandArgs) => {
  let status = Node.run(command, commandArgs)
  if !dry && status != 0 {
    Node.exit(status)
  }
}

if Node.existsSync("Cargo.toml") {
  step("cargo", dry ? ["fmt", "--all", "--check", "--message-format", "short"] : ["fmt", "--all"])
}
step(
  "oxfmt",
  [dry ? ["--list-different"] : [], ["--no-error-on-unmatched-pattern", glob]]->Array.flat,
)
