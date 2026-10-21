/** The working copy a repository's verify last passed at, kept in its .jj. See docs/commits.md. */
let file = repo => Node.join([repo, ".jj", "verified"])

/** The working copy as a commit, as of now; jj snapshots on every command, so asking is enough. */
let snapshot = repo =>
  Node.output(~cwd=repo, "jj", ["log", "-r", "@", "--no-graph", "-T", "commit_id"])->String.trim

let write = (repo, commit) =>
  if commit != "" && Node.existsSync(Node.join([repo, ".jj"])) {
    Node.writeFileSync(file(repo), commit ++ "\n")
  }

let read = repo =>
  try {
    switch Node.readFileSync(file(repo))->String.trim {
    | "" => None
    | commit => Some(commit)
    }
  } catch {
  | _ => None
  }

/** Whether the working copy holds the same files that last passed, whatever its description. */
let holds = repo =>
  switch read(repo) {
  | None => false
  | Some(commit) =>
    let answer = Node.spawnSync(
      "jj",
      ["diff", "--from", commit, "--to", "@", "--summary"],
      {cwd: repo, encoding: "utf8", maxBuffer: 268435456, timeout: 30000},
    )
    answer.status->Nullable.toOption == Some(0) &&
      answer.stdout->Nullable.getOr("")->String.trim == ""
  }
