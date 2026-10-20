/**
 * The workspace's own verify, `check workspace [part ...]`: every part, or those named. What it
 * holds is what lies between repositories -- the registry, the toolchain, no copy of what is
 * inherited -- and the rules it keeps over every repository, a repository turning one off in its
 * `workspace.toml`; it reaches into none but by that repository's own tasks.
 */
let python = "/usr/bin/python3"

let parts: array<(string, unit => int)> = [
  // The files an outside build reads agree with mise, and no project redeclares a workspace tool.
  ("tools", () => Tools.check(~everything=true)),
  // The registry, the task roots and the disk agree, and no project copies what it inherits.
  ("repos", Registry.check),
  // The hooks' tests, under macOS's own Python, which is what runs them.
  (
    "hooks",
    () =>
      Node.run(
        ~cwd=Registry.root,
        python,
        ["-m", "unittest", "discover", "-s", "hooks", "-p", "test_*.py"],
      ),
  ),
  // The scripts type-checked and tested, since no repository below holds them.
  (
    "scripts",
    () =>
      Node.run(~cwd=Registry.root, "pnpm", ["exec", "tsc", "-p", "tsconfig.json"]) == 0
        ? Node.run(~cwd=Registry.root, "pnpm", ["exec", "vitest", "run"])
        : 1,
  ),
  // Every file of ours under the line limits, a repository keeping the rule or turning it off.
  ("lines", () => Lines.main()),
  // The workspace's links, citations and quoted sections resolve.
  ("refs", () => Refs.main()),
]

/** Each part named, or every one, its own log under its name, and on past a failure. */
let run = (named: array<string>): int => {
  let known = parts->Array.map(((name, _)) => name)
  named->Array.forEach(name =>
    if !(known->Array.includes(name)) {
      Registry.fail(
        `the workspace's check has no part ${name}; the parts are ${known->Array.join(", ")}`,
      )
    }
  )
  let failed =
    parts
    ->Array.filter(((name, _)) => named->Array.length == 0 || named->Array.includes(name))
    ->Array.filterMap(((name, part)) => {
      Console.log(`\n=== workspace ${name} ===`)
      part() == 0 ? None : Some(name)
    })
  if failed->Array.length > 0 {
    Console.log(`\nfailed: ${failed->Array.join(", ")}`)
  }
  failed->Array.length > 0 ? 1 : 0
}
