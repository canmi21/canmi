/**
 * The form layer over the tree a commit onto a main line would leave, `form-at-commit`. Run as
 * `commit_tree <repository> <place> [fileset ...]` by hooks/gates/form.res, which reads its log.
 */
let lines = Onset.lines

/** jj's lines from `place` over the repository's stored state, none where it fails. */
let asked = (~place, args) =>
  Node.output(~cwd=place, "jj", ["--ignore-working-copy", ...args])->lines

/** The files `filesets` change in the working copy, as paths from `repo`; every file with none. */
let changed = (repo, ~place, filesets) => {
  let answer = Node.spawnSync(
    "jj",
    ["--ignore-working-copy", "diff", "-r", "@", "--name-only", ...filesets],
    {cwd: place, encoding: "utf8", maxBuffer: 268435456},
  )
  switch answer.status->Nullable.toOption {
  | Some(0) =>
    Ok(
      answer.stdout
      ->Nullable.getOr("")
      ->lines
      ->Array.map(path => Node.relative(repo, Node.resolve([place, path]))),
    )
  | _ =>
    let said = answer.stderr->Nullable.getOr("")->lines->Array.get(0)->Option.getOr("no message")
    Error(`jj could not read the filesets ${filesets->Array.join(" ")}, ${said}`)
  }
}

/**
 * The tree the commit leaves behind. With filesets it is the working copy where they name a file
 * and the parent's version elsewhere; onto a merge it is the whole working copy. A fileset jj
 * cannot read is an error, never the parent's version.
 */
let tree = (repo, ~place, ~filesets): result<Lines.tree, string> =>
  switch Stamp.snapshot(repo) {
  | "" => Error("the working copy could not be snapshotted")
  | at =>
    let whole = Lines.committed(repo, at)
    let parents = asked(~place, ["log", "--no-graph", "-r", "@-", "-T", `commit_id ++ "\\n"`])
    switch (filesets, parents) {
    | ([], _) => Ok(whole)
    | (_, [parent]) =>
      switch (changed(repo, ~place, filesets), changed(repo, ~place, [])) {
      | (Ok(included), Ok(every)) =>
        let left = every->Array.filter(path => !(included->Array.includes(path)))
        let before = Lines.committed(repo, parent)
        Ok({
          ...whole,
          paths: Array.concat(
            whole.paths->Array.filter(path => !(left->Array.includes(path))),
            before.paths->Array.filter(path => left->Array.includes(path)),
          ),
          bytes: path => left->Array.includes(path) ? before.bytes(path) : whole.bytes(path),
        })
      | (Error(why), _) | (_, Error(why)) => Error(why)
      }
    | _ => Ok(whole)
    }
  }

/** The rules of the form layer a part holds, by name. */
let rulesOf = part =>
  Rules.all->Array.filterMap(rule =>
    switch rule {
    | {layer: Form, held: Check(held), name} if held == part => Some(name)
    | _ => None
    }
  )

/** The parts finding something over `tree` as at a push, each logged and named with its rules. */
let refused = (repo, tree) =>
  Check.formed(repo, tree)->Array.filter(((name, part)) => {
    Console.log(`\n=== ${Registry.label(repo)} ${name}, the form layer at a commit ===`)
    let failed = Check.outcome(part, ~pushing=true) != 0
    if failed {
      Console.log(`refused: ${name} holds ${rulesOf(name)->Array.join(", ")}`)
    }
    failed
  })

if Node.isMain {
  Node.exit(
    switch Node.args() {
    | args if args->Array.length >= 2 =>
      let repo = args->Array.getUnsafe(0)
      let place = args->Array.getUnsafe(1)
      switch tree(repo, ~place, ~filesets=args->Array.slice(~start=2)) {
      | Ok(found) => refused(repo, found)->Array.length > 0 ? 1 : 0
      | Error(why) =>
        Console.log(`refused: ${why}, so no tree was judged`)
        1
      }
    | _ => 2
    },
  )
}
