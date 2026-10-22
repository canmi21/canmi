/**
 * Every workflow linted by actionlint, and each action pinned against model/rules/toolchain.res,
 * an outside one by commit and the author's own at main. See docs/toolchain.md.
 */
let step = /^\s*(?:-\s+)?uses:\s+["']?([^\s"'#]+)["']?(\s+#\s+\S+)?\s*$/
let commit = /^[0-9a-f]{40}$/

/** What is wrong with one `uses` value, `owned` the owners the registry lists. */
let pinning = (value, ~comment, ~owned): option<string> =>
  if value->String.startsWith("./") {
    None
  } else if value->String.startsWith("docker://") {
    value->String.includes("@sha256:")
      ? None
      : Some(`${value} names an image by its tag alone, not its digest`)
  } else {
    switch value->String.split("@") {
    | [action, ref] =>
      let owner = action->String.split("/")->Array.getUnsafe(0)
      if owned->Array.includes(owner) {
        ref == "main" ? None : Some(`${value} is the author's own, taken at main and not pinned`)
      } else if !(commit->RegExp.test(ref)) {
        Some(`${value} is pinned by ${ref}, not by a commit`)
      } else if !comment {
        Some(`${value} has no comment naming its release`)
      } else {
        None
      }
    | _ => Some(`${value} names no ref`)
    }
  }

/** Each pin in one file's text that the rule refuses, `file` naming it. */
let problems = (text, ~file, ~owned): array<string> =>
  text
  ->String.split("\n")
  ->Array.mapWithIndex((line, index) =>
    step
    ->RegExp.exec(line)
    ->Option.flatMap(result =>
      switch result->RegExp.Result.matches {
      | [Some(value), comment] =>
        pinning(value, ~comment=comment->Option.isSome, ~owned)->Option.map(
          why => `${file}:${Int.toString(index + 1)}: ${why}`,
        )
      | _ => None
      }
    )
  )
  ->Array.filterMap(found => found)

let workflow = /^\.github\/workflows\/[^\/]+\.ya?ml$/
let action = /^\.github\/actions\/.+\/action\.ya?ml$/

let main = (~root): array<string> => {
  let owned = Registry.registry()->Array.map(((_, (user, _))) => user)
  let files =
    Lines.tracked(root)->Array.filter(path =>
      workflow->RegExp.test(path) || action->RegExp.test(path)
    )
  let pins =
    files->Array.flatMap(path =>
      problems(Node.readFileSync(Node.join([root, path])), ~file=path, ~owned)
    )
  let workflows = files->Array.filter(path => workflow->RegExp.test(path))
  let linted = if workflows == [] {
    []
  } else {
    let ran = Node.spawnSync(
      "actionlint",
      ["-no-color", ...workflows],
      {cwd: root, encoding: "utf8", maxBuffer: 268435456},
    )
    switch ran.status->Nullable.toOption {
    | Some(0) => []
    | Some(_) =>
      ran.stdout
      ->Nullable.getOr("")
      ->String.split("\n")
      ->Array.filter(line => /^\S+:\d+:\d+: /->RegExp.test(line))
    | None => ["actionlint could not be run; the workspace's [tools] installs it"]
    }
  }
  Array.concat(linted, pins)
}
