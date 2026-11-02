/** The ci rules as the parts of the check run them, over the repository at `root`. */
let held = (~root): array<string> => {
  let documents = Runs.documents(~root)
  Array.flat([
    Caches.rustCacheProblems(documents),
    Caches.runnerProblems(documents),
    Crane.main(~root),
  ])
}

/** ci-native-steps, soft while the workflows of monoflake still break it. */
let steps = (~root): array<string> => Entries.nativeProblems(Runs.documents(~root))

/** ci-shell-minimal and ci-entries over a tree, refused where a commit lands on a main line. */
let shell = (tree: Lines.tree): array<Form_layer.finding> => {
  let documents = Runs.documentsOf(tree)
  Array.concat(Entries.shellFindings(documents), Entries.entryFindings(documents))
}

/** The same over the working copy at `root`. */
let tagged = (~root) => shell(Lines.disk(root))
