/**
 * What push scans a public repository for, the private identifiers in what it sends and in what it
 * tracks. See docs/agents/pushing.md, "A push carries nothing private".
 */
@module("node:os") external homedir: unit => string = "homedir"

/** The gate `SKIP` names to pass a hit in what is sent. */
let gate = "scan"

/** Where a hit stands, a line of a file or a commit message. */
type place = Line(string, int) | Message

/** A hit, with the short id of the commit that sends it, none for a tracked file. */
type hit = {place: place, identifier: string, commit: option<string>}

/** One outgoing commit, its short id, its own diff against its parents and its description. */
type commit = {id: string, diff: string, message: string}

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

/** An identifier as a pattern in any case, no letter, digit or underscore on either side. */
let pattern = identifier =>
  RegExp.fromString(
    `(?<![A-Za-z0-9_])${identifier->String.replaceRegExp(
        /[.*+?^${}()|[\]\\]/g,
        "\\$&",
      )}(?![A-Za-z0-9_])`,
    ~flags="i",
  )

/** Each identifier beside its pattern, an empty one passed over. */
let patterns = identifiers =>
  identifiers->Array.filterMap(identifier =>
    identifier == "" ? None : Some((identifier, pattern(identifier)))
  )

/** Whether `line` holds `identifier` as a whole word in any case. */
let holds = (line, identifier) => identifier != "" && pattern(identifier)->RegExp.test(line)

/** The identifiers one line holds. */
let found = (line, patterns) =>
  patterns->Array.filterMap(((identifier, pattern)) =>
    pattern->RegExp.test(line) ? Some(identifier) : None
  )

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

/** The hits in what a push sends, each commit's added lines and its description. */
let sent = (commits: array<commit>, identifiers): array<hit> => {
  let patterns = patterns(identifiers)
  commits->Array.flatMap(({id, diff, message}) => {
    let commit = Some(id)
    Array.concat(
      added(diff)->Array.flatMap(((file, number, text)) =>
        found(text, patterns)->Array.map(
          identifier => {
            place: Line(file, number),
            identifier,
            commit,
          },
        )
      ),
      message
      ->String.split("\n")
      ->Array.flatMap(line =>
        found(line, patterns)->Array.map(identifier => {place: Message, identifier, commit})
      ),
    )
  })
}

/** The hits in tracked files, each path with its text, a file holding a NUL passed over. */
let tracked = (files: array<(string, string)>, identifiers): array<hit> => {
  let patterns = patterns(identifiers)
  files->Array.flatMap(((file, text)) =>
    text->String.includes("\x00")
      ? []
      : text
        ->String.split("\n")
        ->Array.flatMapWithIndex((line, index) =>
          found(line, patterns)->Array.map(
            identifier => {
              place: Line(file, index + 1),
              identifier,
              commit: None,
            },
          )
        )
  )
}

/** Whether a `SKIP` value names the scan, comma-separated as a commit's is. */
let skipping = (value: option<string>) =>
  value->Option.mapOr(false, value =>
    value->String.split(",")->Array.map(String.trim)->Array.includes(gate)
  )

/** The hits sent split into those passed and those refused, by whether SKIP names the scan. */
let verdict = (sent: array<hit>, ~skip: option<string>) => skipping(skip) ? (sent, []) : ([], sent)

/** The tracked hits whose file and identifier no line sent also holds. */
let alreadyTracked = (tracked: array<hit>, sent: array<hit>) =>
  tracked->Array.filter(hit =>
    switch hit.place {
    | Message => true
    | Line(file, _) =>
      !(
        sent->Array.some(other =>
          switch other.place {
          | Line(sentFile, _) => sentFile == file && other.identifier == hit.identifier
          | Message => false
          }
        )
      )
    }
  )

/** What one repository's push is told, the hits refused, passed by SKIP and tracked. */
type judgment = {refused: array<hit>, passed: array<hit>, warned: array<hit>}

let nothing = {refused: [], passed: [], warned: []}

/** A repository's judgment, `scan` run only where it is public, or why it could not be scanned. */
let judged = (~public, ~skip, scan: unit => result<(array<hit>, array<hit>), string>) =>
  public
    ? scan()->Result.map(((sent, tracked)) => {
        let (passed, refused) = verdict(sent, ~skip)
        {refused, passed, warned: alreadyTracked(tracked, sent)}
      })
    : Ok(nothing)

/** One hit as a line naming where it stands and what it holds. */
let shown = (place, hit) => {
  let commit = hit.commit->Option.mapOr("", id => `${id} `)
  switch hit.place {
  | Line(file, number) =>
    `${place}: ${commit}${file}:${Int.toString(number)} holds ${hit.identifier}`
  | Message => `${place}: ${commit}a commit message holds ${hit.identifier}`
  }
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

/** Every commit a push of main sends, all of main's where origin has no main yet. */
let range = `remote_bookmarks(exact:"main", exact:"origin")..main ~ root()`

/** Each commit a push of main from `repo` sends, with its own diff and its description. */
let outgoing = repo =>
  jj(repo, ["log", "--no-graph", "-r", range, "-T", `commit_id ++ "\\n"`])->Result.flatMap(ids =>
    ids
    ->String.split("\n")
    ->Array.filter(id => id != "")
    ->Array.reduce(Ok([]), (gathered, id) =>
      gathered->Result.flatMap(
        commits =>
          jj(repo, ["diff", "-r", id, "--git"])->Result.flatMap(
            diff =>
              jj(repo, ["log", "--no-graph", "-r", id, "-T", "description"])->Result.map(
                message =>
                  commits->Array.concat([{id: id->String.slice(~start=0, ~end=12), diff, message}]),
              ),
          ),
      )
    )
  )

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
  outgoing(repo)->Result.flatMap(commits =>
    files(repo)->Result.map(files => (sent(commits, identifiers), tracked(files, identifiers)))
  )
