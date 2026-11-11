let remote = `remote_bookmarks(exact:"main", exact:"origin")`

/** Each commit main@origin has that main lacks, as its short id and subject. */
let incoming = read =>
  read([
    "log",
    "--no-graph",
    "-r",
    `main..${remote} ~ root()`,
    "-T",
    `commit_id.short() ++ " " ++ description.first_line() ++ "\\n"`,
  ])->Result.map(Onset.lines)

/** The refusal for a main that moved, the commits that came in and the steps that follow. */
let behind = (place, commits) =>
  `main@origin moved, ${Int.toString(commits->Array.length)} incoming commit(s):\n` ++
  commits->Array.map(line => `    ${line}\n`)->Array.join("") ++
  "read them, rebase onto main@origin, check again, then push:\n" ++
  "    jj rebase -b main -d main@origin\n" ++
  "    jj bookmark set main -r <your last commit>   (only where main was behind your commits)\n" ++
  `    mise run check ${place}\n` ++
  `    mise run push ${place}`

/** Refused where main@origin, as last fetched, holds what main lacks, with no fetch of its own. */
let ready = (read, ~place) =>
  incoming(read)->Result.flatMap(commits => commits == [] ? Ok() : Error(behind(place, commits)))

/** A refused push, most often a main CI moved since the last fetch, and the steps that follow. */
let refused = place =>
  `jj git push failed in ${place}; where main@origin moved, most often by CI's scheduled update, ` ++
  "fetch and read what came in, rebase onto it, check again, then push:\n" ++
  "    jj git fetch\n" ++
  "    jj rebase -b main -d main@origin\n" ++
  `    mise run check ${place}\n` ++
  `    mise run push ${place}`

/** The reason a push stops, said the same by a dry run in the conditional. */
let stopped = (why, ~dry) => `${why}, so ${dry ? "a push would push" : "push pushes"} nothing`

let planned = (repositories, inspect) =>
  repositories->Array.reduce(Ok([]), (gathered, repo) =>
    gathered->Result.flatMap(pending =>
      inspect(repo)->Result.map(commits => pending->Array.concat([(repo, Some(commits))]))
    )
  )
