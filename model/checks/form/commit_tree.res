/**
 * The form layer over the tree a commit onto a main line would leave, `form-at-commit`. Run as
 * `commit_tree <repository> <place> [fileset ...]` by hooks/gates/form.res, which reads its log.
 */
let lines = Onset.lines

/** jj's lines from `place` over the repository's stored state, none where it fails. */
let asked = (~place, args) =>
  Node.output(~cwd=place, "jj", ["--ignore-working-copy", ...args])->lines

/** The files `filesets` change in the working copy, as paths from `repo`; every file with none. */
let changed = (repo, ~place, filesets) =>
  asked(~place, ["diff", "-r", "@", "--name-only", ...filesets])->Array.map(path =>
    Node.relative(repo, Node.resolve([place, path]))
  )

/**
 * The tree the commit leaves behind. With filesets it is the working copy where they name a file
 * and the parent's version elsewhere; onto a merge it is the whole working copy.
 */
let tree = (repo, ~place, ~filesets): option<Lines.tree> =>
  switch Stamp.snapshot(repo) {
  | "" => None
  | at =>
    let whole = Lines.committed(repo, at)
    let parents = asked(~place, ["log", "--no-graph", "-r", "@-", "-T", `commit_id ++ "\\n"`])
    switch (filesets, parents) {
    | ([], _) => Some(whole)
    | (_, [parent]) =>
      let included = changed(repo, ~place, filesets)
      let left = changed(repo, ~place, [])->Array.filter(path => !(included->Array.includes(path)))
      let before = Lines.committed(repo, parent)
      Some({
        ...whole,
        paths: Array.concat(
          whole.paths->Array.filter(path => !(left->Array.includes(path))),
          before.paths->Array.filter(path => left->Array.includes(path)),
        ),
        bytes: path => left->Array.includes(path) ? before.bytes(path) : whole.bytes(path),
      })
    | _ => Some(whole)
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
      | Some(found) => refused(repo, found)->Array.length > 0 ? 1 : 0
      | None => 0
      }
    | _ => 2
    },
  )
}
