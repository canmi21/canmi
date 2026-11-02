/** The ci rules as the parts of the check run them, over the repository at `root`. */
let held = (~root): array<string> => {
  let documents = Runs.documents(~root)
  Array.flat([
    Caches.rustCacheProblems(documents),
    Caches.runnerProblems(documents),
    Crane.main(~root),
  ])
}

/** The entry rules, soft while the workflows of monoflake still break them. */
let steps = (~root): array<string> => {
  let documents = Runs.documents(~root)
  Array.flat([Entries.nativeProblems(documents), Entries.entryProblems(documents)])
}

/** ci-shell-minimal over a tree, a form rule refused where a commit lands on a main line. */
let shell = (tree: Lines.tree): array<Form_layer.finding> =>
  Entries.shellFindings(Runs.documentsOf(tree))

/** The same over the working copy at `root`. */
let tagged = (~root) => shell(Lines.disk(root))
