let remote = `remote_bookmarks(exact:"main", exact:"origin")`

let incoming = read =>
  read([
    "log",
    "--no-graph",
    "-r",
    `main..${remote} ~ root()`,
    "-T",
    `commit_id.short() ++ "\\n"`,
  ])->Result.map(Onset.lines)

let ready = read =>
  incoming(read)->Result.flatMap(commits =>
    commits == []
      ? Ok()
      : Error(
          `main@origin has incoming commits ${commits->Array.join(
              ", ",
            )}; ` ++ "pull, read them, rebase onto main@origin, move main, and check again before pushing",
        )
  )

let planned = (repositories, inspect) =>
  repositories->Array.reduce(Ok([]), (gathered, repo) =>
    gathered->Result.flatMap(pending =>
      inspect(repo)->Result.map(commits => pending->Array.concat([(repo, Some(commits))]))
    )
  )
