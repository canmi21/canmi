/**
 * The CI entry of a scheduled update, one stage a workflow step, calling the core in
 * scripts/deps/scheduled.res. See docs/ci.md.
 */
@module("node:fs") external appendFileSync: (string, string) => unit = "appendFileSync"

let usage = "scheduled colocate <path> | update <path> | moved <path> | message <path> <file> | commit <path> <file> | held <names>"

let fail = why => {
  Console.error(`scheduled: ${why}`)
  Node.exit(1)
}

/** A value handed to the next step, where GitHub reads them, or shown on the Mac. */
let output = (key, value) =>
  switch Node.env->Dict.get("GITHUB_OUTPUT") {
  | Some(file) if file != "" => appendFileSync(file, `${key}=${value}\n`)
  | _ => Console.log(`${key}=${value}`)
  }

let update = async path => {
  let (status, held) = await Scheduled.update(path)
  output("held", held->Array.join(", "))
  if status != 0 {
    fail(`update exited ${Int.toString(status)}, so nothing is committed`)
  }
}

let main = async () =>
  try {
    switch Node.args() {
    | ["colocate", path] => Scheduled.colocate(path)
    | ["update", path] => await update(path)
    | ["moved", path] => output("moved", Scheduled.moved(path) ? "true" : "false")
    | ["message", path, file] => Scheduled.message(path, file)
    | ["commit", path, file] => Scheduled.commit(path, file)
    | ["held", names] if names != "" =>
      Console.log(
        `::error::the releases of ${names} could not be read, so their pins were kept as they were`,
      )
      Node.exit(1)
    | ["held", _] => ()
    | _ => fail(usage)
    }
  } catch {
  | Scheduled.Failed(why) => fail(why)
  }

if Node.isMain {
  await main()
}
