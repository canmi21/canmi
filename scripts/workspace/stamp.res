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

let timeout = 30000

/** What comparing the working copy with the stamp found. */
type verdict =
  | Held
  | Unstamped
  | Changed(array<string>)
  | Failed(int, string)
  | TimedOut(int)

@get external errorCode: JsExn.t => Nullable.t<string> = "code"

/** Reads the answer of the jj diff between the stamp and the working copy. */
let judge = (answer: Node.spawned): verdict =>
  switch (answer.status->Nullable.toOption, answer.error->Nullable.toOption) {
  | (Some(0), _) =>
    switch answer.stdout->Nullable.getOr("")->String.trim {
    | "" => Held
    | summary =>
      Changed(
        summary
        ->String.split("\n")
        ->Array.map(line => line->String.slice(~start=2)->String.trim),
      )
    }
  | (None, Some(error)) if errorCode(error)->Nullable.toOption == Some("ETIMEDOUT") =>
    TimedOut(timeout)
  | (status, _) =>
    let said = answer.stderr->Nullable.getOr("")->String.trim->String.split("\n")
    Failed(status->Option.getOr(-1), said[0]->Option.getOr("no message"))
  }

/** Whether the working copy holds the same files that last passed, whatever its description. */
let verdict = repo =>
  switch read(repo) {
  | None => Unstamped
  | Some(commit) =>
    judge(
      Node.spawnSync(
        "jj",
        ["diff", "--from", commit, "--to", "@", "--summary"],
        {cwd: repo, encoding: "utf8", maxBuffer: 268435456, timeout},
      ),
    )
  }

let holds = repo => verdict(repo) == Held
