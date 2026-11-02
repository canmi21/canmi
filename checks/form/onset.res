/** When a form finding first appeared in a repository's history, read by jj as a hint alone. */
type t =
  | Working
  | Committed(string, int)

/** jj's answer from `root`, or None where it failed or the root is no jj repository. */
let read = (~root, args) => {
  let answer = Node.spawnSync("jj", args, {cwd: root, encoding: "utf8", maxBuffer: 268435456})
  answer.status->Nullable.toOption == Some(0) ? Some(answer.stdout->Nullable.getOr("")) : None
}

let lines = text => text->String.split("\n")->Array.filter(line => line != "")

/** A path as a quoted fileset string. */
let quoted = path => `"${path->String.replaceAll("\\", "\\\\")->String.replaceAll("\"", "\\\"")}"`

/** Every commit of `@`'s ancestry, newest first, `@` itself at 0. */
let ancestry = (~root): array<string> =>
  read(~root, ["log", "--no-graph", "-r", "::@", "-T", `commit_id ++ "\\n"`])->Option.mapOr(
    [],
    lines,
  )

/** A commit by its place in `chain`, and the commits after it up to the working copy's parent. */
let placed = (chain, commit) =>
  switch chain->Array.indexOf(commit) {
  | -1 => None
  | 0 => Some(Working)
  | at => Some(Committed(commit, at - 1))
  }

/**
 * The oldest commit of the run `holds` keeps through, among those up to `at` touching `fileset`,
 * found by halving and so read as if it held throughout once it began.
 */
let run = (~root, ~fileset, ~holds: string => bool, ~at="@"): option<t> => {
  let touched =
    read(
      ~root,
      ["log", "--no-graph", "-r", `files(${fileset}) & ::(${at})`, "-T", `commit_id ++ "\\n"`],
    )->Option.mapOr([], lines)
  let at = index => touched->Array.getUnsafe(index)
  let last = touched->Array.length - 1
  if last < 0 || !holds(at(0)) {
    None
  } else {
    let low = ref(0)
    let high = ref(last)
    if holds(at(last)) {
      low := last
    }
    while high.contents - low.contents > 1 {
      let middle = (low.contents + high.contents) / 2
      if holds(at(middle)) {
        low := middle
      } else {
        high := middle
      }
    }
    placed(ancestry(~root), at(low.contents))
  }
}

/** A text's lines, counted as the lines part counts a file's. */
let counted = text =>
  switch text {
  | "" => 0
  | text =>
    let all = text->String.splitByRegExp(/\r\n|\r|\n/)
    all->Array.at(-1) == Some(Some("")) ? all->Array.length - 1 : all->Array.length
  }

/** Since when the file at `path` has run past `limit` lines. */
let file = (~root, path, ~limit, ~at=?) =>
  run(~root, ~fileset=`root-file:${quoted(path)}`, ~at?, ~holds=commit =>
    read(~root, ["file", "show", "-r", commit, `root-file:${quoted(path)}`])->Option.mapOr(
      false,
      text => counted(text) > limit,
    )
  )

/** Since when the files under the directory `path` have been as `holds` reads them. */
let directory = (~root, path, ~holds: array<string> => bool, ~at=?) =>
  run(~root, ~fileset=`root:${quoted(path)}`, ~at?, ~holds=commit =>
    holds(
      read(~root, ["file", "list", "-r", commit, `root:${quoted(path)}`])
      ->Option.mapOr([], lines)
      ->Array.filter(file => !Layout.vendored(file)),
    )
  )

/** The names directly inside the directory `path`, read from the files under it. */
let entries = (path, files: array<string>) => {
  let inside = Set.make()
  files->Array.forEach(file =>
    if file->String.startsWith(path ++ "/") {
      switch file->String.slice(~start=path->String.length + 1)->String.split("/")->Array.get(0) {
      | Some(name) => inside->Set.add(name)
      | None => ()
      }
    }
  )
  inside->Set.size
}

/**
 * Since when a comment block broke its limit, by the commit each line came from, its spoken line
 * past `limit` in order of arrival and its oldest line in `wide`.
 */
let block = (~root, path, ~spoken: array<int>, ~limit, ~wide: array<int>, ~at="@") =>
  switch read(~root, ["file", "annotate", "-r", at, "-T", `commit.commit_id() ++ "\\n"`, path]) {
  | None => None
  | Some(text) =>
    let origins = lines(text)
    let chain = ancestry(~root)
    let age = number =>
      origins[number - 1]->Option.flatMap(commit =>
        switch chain->Array.indexOf(commit) {
        | -1 => None
        | at => Some(at)
        }
      )
    let arrived = spoken->Array.filterMap(age)->Array.toSorted((a, b) => Int.toFloat(b - a))
    let long = arrived->Array.length > limit ? arrived[limit] : None
    let broad =
      wide
      ->Array.filterMap(age)
      ->Array.reduce(None, (oldest, at) => Some(Math.Int.max(at, oldest->Option.getOr(at))))
    switch (long, broad) {
    | (Some(a), Some(b)) => Some(Math.Int.max(a, b))
    | (Some(a), None) | (None, Some(a)) => Some(a)
    | (None, None) => None
    }->Option.flatMap(at => placed(chain, chain->Array.getUnsafe(at)))
  }

/** The hint a warning carries, empty where no history could be read. */
let said = (found: option<t>) =>
  switch found {
  | None => ""
  | Some(Working) => " (first in the working copy)"
  | Some(Committed(commit, since)) =>
    ` (first in ${commit->String.slice(~start=0, ~end=12)}, ${Int.toString(since)} ${since == 1
        ? "commit"
        : "commits"} since)`
  }
