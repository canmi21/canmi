/**
 * `lane take <name> [--in <repository>]`, a lane's changed paths restored into the main checkout,
 * the lane snapshotted first since `jj restore` reads its last snapshot, and refused where no
 * passing `lane handed` judged what it holds now, docs/agents/lanes.md.
 */
/** The paths one line of `jj diff --summary` names, both sides of a rename, a copy's new one. */
let pathsOfSummary = (line: string) => {
  let body = line->String.slice(~start=2)
  switch body->String.match(/^(.*)\{(.*) => (.*)\}(.*)$/) {
  | Some([_, Some(before), Some(from), Some(to), Some(after)]) =>
    let tidy = path => path->String.replaceAll("//", "/")
    let kept = line->String.startsWith("C ") ? [] : [tidy(`${before}${from}${after}`)]
    Array.concat(kept, [tidy(`${before}${to}${after}`)])
  | _ => [body]
  }
}

let summaryPaths = (text: string) =>
  text
  ->String.split("\n")
  ->Array.filter(line => line != "")
  ->Array.flatMap(pathsOfSummary)

/** What keeps a path from being taken, main having moved it or the checkout holding an edit. */
let blocked = (~touched, ~moved, ~edited) =>
  Array.concat(
    touched
    ->Array.filter(path => moved->Array.includes(path))
    ->Array.map(path => `${path}: main moved it since the lane forked`),
    touched
    ->Array.filter(path => edited->Array.includes(path))
    ->Array.map(path => `${path}: the main checkout holds an edit to it`),
  )

/** The stdout of a jj command, or why it failed. */
let jj = (cwd, args) => {
  let answer = Node.spawnSync("jj", args, {cwd, encoding: "utf8", maxBuffer: 268435456})
  answer.status->Nullable.toOption == Some(0)
    ? Ok(answer.stdout->Nullable.getOr(""))
    : Error(answer.stderr->Nullable.getOr("jj failed")->String.trim)
}

let fork = "fork_point(main | @)"

let fileset = path =>
  `root-file:"${path->String.replaceAll("\\", "\\\\")->String.replaceAll("\"", "\\\"")}"`

/**
 * One workspace of the lane taken into `source`, or why not, printing the paths. `handed` says
 * whether its last passing `lane handed` judged what it holds now.
 */
let takeOne = (~source, ~name, ~dry, ~handed, one: Lane_state.found) =>
  if Lane_check.stale(one.path) {
    Error(`lanes/${name}/${one.rel} is stale, so what it holds is not what its seat saw`)
  } else {
    switch handed(one) {
    | Error(why) => Error(why)
    | Ok() =>
      switch (
        jj(one.path, ["st"]),
        jj(one.path, ["diff", "--from", fork, "--to", "@", "--summary"]),
        jj(one.path, ["diff", "--from", fork, "--to", "main", "--summary"]),
        jj(source, ["diff", "--from", "main", "--to", "@", "--summary"]),
      ) {
      | (Error(why), _, _, _)
      | (_, Error(why), _, _)
      | (_, _, Error(why), _)
      | (_, _, _, Error(why)) =>
        Error(`lanes/${name}/${one.rel}: ${why}`)
      | (Ok(_), Ok(touched), Ok(moved), Ok(edited)) =>
        let touched = summaryPaths(touched)
        switch blocked(~touched, ~moved=summaryPaths(moved), ~edited=summaryPaths(edited)) {
        | [] if touched == [] =>
          Console.log(`lanes/${name}/${one.rel}: nothing to take`)
          Ok()
        | [] if dry =>
          touched->Array.forEach(path => Console.log(`would take ${one.rel}: ${path}`))
          Ok()
        | [] =>
          jj(
            source,
            Array.concat(
              ["restore", "--from", `${name}@`, "--to", "@"],
              touched->Array.map(fileset),
            ),
          )->Result.map(_ =>
            touched->Array.forEach(path => Console.log(`took ${one.rel}: ${path}`))
          )
        | found =>
          Error(found->Array.map(line => `lanes/${name}/${one.rel}: ${line}`)->Array.join("\n"))
        }
      }
    }
  }

let main = (workspaces: array<Lane_state.found>, ~root, ~registered, ~name, ~dry, ~handed) =>
  if workspaces == [] {
    Console.error(`lanes/${name} holds no such jj workspace`)
    2
  } else {
    let failed = workspaces->Array.filterMap(one =>
      switch Lane_state.sourceOf(~root, ~registered, one.rel) {
      | None => Some(`lanes/${name}/${one.rel} is neither canmi nor a registered repository's path`)
      | Some(source) =>
        switch takeOne(~source, ~name, ~dry, ~handed, one) {
        | Ok() => None
        | Error(why) => Some(why)
        }
      }
    )
    failed->Array.forEach(why => Console.error(why))
    failed == [] ? 0 : 1
  }
