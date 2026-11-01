/** The ci rules as the parts of the check run them, over the repository at `root`. */
let held = (~root): array<string> => {
  let documents = Runs.documents(~root)
  Array.flat([
    Caches.rustCacheProblems(documents),
    Caches.runnerProblems(documents),
    Crane.main(~root),
  ])
}

/** The shell rules, soft while the workflows of monoflake still break them. */
let steps = (~root): array<string> => {
  let documents = Runs.documents(~root)
  Array.flat([
    Entries.nativeProblems(documents),
    Entries.entryProblems(documents),
    Entries.shellProblems(documents),
  ])
}
