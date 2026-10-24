/**
 * What push scans a public repository for, the private identifiers in what it sends and in what it
 * tracks. See docs/agents/pushing.md, "A push carries nothing private".
 */
@module("node:os") external homedir: unit => string = "homedir"

/** The gate `SKIP` names to pass a hit in what is sent. */
let gate = "scan"

/** Where a hit stands, a line of a file or a commit message. */
type place = Line(string, int) | Message

type hit = {place: place, identifier: string}

/** The list's path with `~` read as the home directory. */
let expanded = path =>
  path == "~" || path->String.startsWith("~/")
    ? Node.join([homedir(), path->String.slice(~start=1)])
    : path

/** The identifiers a list holds, one per line, blank lines passed over. */
let listed = text =>
  text->String.split("\n")->Array.map(String.trim)->Array.filter(line => line != "")

/** The list at `Toolchain.privateIdentifiers`, or None where it cannot be read. */
let identifiers = () => {
  let path = expanded(Toolchain.privateIdentifiers)
  try {
    Some(listed(Node.readFileSync(path)))
  } catch {
  | _ => None
  }
}

let wordy = /[A-Za-z0-9_]/
let isWordy = (text, index) =>
  index >= 0 && index < text->String.length && wordy->RegExp.test(text->String.charAt(index))

/** Whether `line` holds `identifier` with no letter, digit or underscore either side. */
let holds = (line, identifier) => {
  let length = identifier->String.length
  let rec from = start =>
    switch line->String.indexOfFrom(identifier, start) {
    | -1 => false
    | at => (!isWordy(line, at - 1) && !isWordy(line, at + length)) || from(at + 1)
    }
  length > 0 && from(0)
}

/** The identifiers one line holds. */
let found = (line, identifiers) => identifiers->Array.filter(identifier => holds(line, identifier))

/** Each line a git diff adds, with its file and its number in the new file. */
let added = (diff): array<(string, int, string)> => {
  let file = ref("")
  let number = ref(0)
  let inHunk = ref(false)
  let hunk = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/
  diff
  ->String.split("\n")
  ->Array.filterMap(line =>
    if line->String.startsWith("diff --git ") {
      inHunk := false
      None
    } else if !inHunk.contents && line->String.startsWith("+++ ") {
      let target = line->String.slice(~start=4)
      let path = target->String.startsWith("b/") ? target->String.slice(~start=2) : target
      file := path
      None
    } else {
      switch hunk->RegExp.exec(line) {
      | Some(groups) =>
        inHunk := true
        number :=
          groups[1]
          ->Option.flatMap(start => start)
          ->Option.flatMap(start => Int.fromString(start))
          ->Option.getOr(1)
        None
      | None if !inHunk.contents => None
      | None if line->String.startsWith("+") => {
          let at = number.contents
          number := at + 1
          Some((file.contents, at, line->String.slice(~start=1)))
        }
      | None if line->String.startsWith(" ") || line == "" => {
          number := number.contents + 1
          None
        }
      | None => None
      }
    }
  )
}

/** The hits in what a push sends, the lines its diff adds and its commits' descriptions. */
let sent = (~diff, ~messages, identifiers): array<hit> =>
  Array.concat(
    added(diff)->Array.flatMap(((file, number, text)) =>
      found(text, identifiers)->Array.map(identifier => {place: Line(file, number), identifier})
    ),
    messages
    ->String.split("\n")
    ->Array.flatMap(line =>
      found(line, identifiers)->Array.map(identifier => {place: Message, identifier})
    ),
  )

/** The hits in tracked files, each path with its text, a file holding a NUL passed over. */
let tracked = (files: array<(string, string)>, identifiers): array<hit> =>
  files->Array.flatMap(((file, text)) =>
    text->String.includes("\x00")
      ? []
      : text
        ->String.split("\n")
        ->Array.flatMapWithIndex((line, index) =>
          found(line, identifiers)->Array.map(
            identifier => {
              place: Line(file, index + 1),
              identifier,
            },
          )
        )
  )

/** Whether a `SKIP` value names the scan, comma-separated as a commit's is. */
let skipping = (value: option<string>) =>
  value->Option.mapOr(false, value =>
    value->String.split(",")->Array.map(String.trim)->Array.includes(gate)
  )

/** The hits sent split into those passed and those refused, by whether SKIP names the scan. */
let verdict = (sent: array<hit>, ~skip: option<string>) => skipping(skip) ? (sent, []) : ([], sent)

/** One hit as a line naming where it stands and what it holds. */
let shown = (place, hit) =>
  switch hit.place {
  | Line(file, number) => `${place}: ${file}:${Int.toString(number)} holds ${hit.identifier}`
  | Message => `${place}: a commit message holds ${hit.identifier}`
  }

/** jj's answer in `repo`, or why it failed. */
let jj = (repo, args) => {
  let result = Node.spawnSync("jj", args, {cwd: repo, encoding: "utf8", maxBuffer: 268435456})
  switch result.status->Nullable.toOption {
  | Some(0) => Ok(result.stdout->Nullable.getOr(""))
  | _ =>
    Error(`jj ${args->Array.join(" ")} failed: ${result.stderr->Nullable.getOr("")->String.trim}`)
  }
}

let remoteMain = `remote_bookmarks(exact:"main", exact:"origin")`

/** What a push of main from `repo` sends, its diff from origin's main and its descriptions. */
let outgoing = repo =>
  jj(
    repo,
    ["log", "--no-graph", "-r", remoteMain, "-T", `commit_id ++ "\\n"`],
  )->Result.flatMap(remote => {
    let from = remote->String.trim == "" ? "root()" : remoteMain
    jj(repo, ["diff", "--from", from, "--to", "main", "--git"])->Result.flatMap(diff =>
      jj(
        repo,
        ["log", "--no-graph", "-r", `${remoteMain}..main ~ root()`, "-T", `description ++ "\\n"`],
      )->Result.map(messages => (diff, messages))
    )
  })

/** Each file `repo` tracks with its text, one that cannot be read passed over. */
let files = repo =>
  jj(repo, ["file", "list"])->Result.map(listed =>
    listed
    ->String.split("\n")
    ->Array.filter(path => path != "")
    ->Array.filterMap(path =>
      try {
        Some((path, Node.readFileSync(Node.join([repo, path]))))
      } catch {
      | _ => None
      }
    )
  )

/** The hits in what `repo` sends and in what it tracks, or why it could not be scanned. */
let repository = (repo, identifiers) =>
  outgoing(repo)->Result.flatMap(((diff, messages)) =>
    files(repo)->Result.map(files => (
      sent(~diff, ~messages, identifiers),
      tracked(files, identifiers),
    ))
  )
