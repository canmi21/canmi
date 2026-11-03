type asked = {
  repository: string,
  subject: string,
  trailers: array<string>,
  paths: array<string>,
  thread: option<string>,
  dry: bool,
}

let usage = "Land a repository's working copy: fmt, bump, check, commit, push: `land <name> -m <subject> [--trailer <line>]... [--paths <path>...] [--thread <name>] [--dry-run]`"

let message = (asked: asked) =>
  asked.trailers == [] ? asked.subject : asked.subject ++ "\n\n" ++ asked.trailers->Array.join("\n")

let parse = arguments => {
  let repository = arguments->Array.get(0)->Option.getOr("")
  let subject = ref("")
  let trailers = []
  let paths = []
  let thread = ref(None)
  let dry = ref(false)
  let refused = ref(repository == "" || repository->String.startsWith("-"))
  let index = ref(1)
  let value = () => {
    index := index.contents + 1
    switch arguments->Array.get(index.contents) {
    | Some(value) if value != "" && !(value->String.startsWith("-")) => value
    | _ =>
      refused := true
      ""
    }
  }
  while index.contents < arguments->Array.length {
    switch arguments->Array.getUnsafe(index.contents) {
    | "-m" => subject := value()
    | "--trailer" => trailers->Array.push(value())
    | "--thread" => thread := Some(value())
    | "--dry-run" => dry := true
    | "--paths" =>
      let start = index.contents + 1
      while (
        index.contents + 1 < arguments->Array.length &&
          !(arguments->Array.getUnsafe(index.contents + 1)->String.startsWith("-"))
      ) {
        index := index.contents + 1
        paths->Array.push(arguments->Array.getUnsafe(index.contents))
      }
      if index.contents < start {
        refused := true
      }
    | _ => refused := true
    }
    index := index.contents + 1
  }
  if (
    refused.contents ||
    subject.contents == "" ||
    (repository != "workspace" && !(Registry.paths()->Array.includes(repository)))
  ) {
    Error(usage)
  } else {
    let asked = {
      repository,
      subject: subject.contents,
      trailers,
      paths,
      thread: thread.contents,
      dry: dry.contents,
    }
    let problems = History.problems(message(asked))
    problems == [] ? Ok(asked) : Error(usage ++ "\n" ++ problems->Array.join("\n"))
  }
}

type step =
  | Format
  | Bump
  | Check
  | Commit
  | Bookmark
  | PushDry
  | Push
  | Record

let steps = [Format, Bump, Check, Commit, Bookmark, PushDry, Push, Record]

let directory = asked => asked.repository == "workspace" ? "." : `repos/${asked.repository}`

let command = (asked, step) => {
  let name = asked.repository == "workspace" ? [] : [asked.repository]
  let verb = name_ => ("mise", ["run", name_, ...name])
  let repository = ["-R", directory(asked)]
  switch step {
  | Format => verb("fmt")
  | Bump => verb("bump")
  | Check => verb("check")
  | Commit =>
    // jj reads a path from the directory it runs in, the workspace's root.
    let inside = path => directory(asked) == "." ? path : `${directory(asked)}/${path}`
    ("jj", [...repository, "commit", "-m", message(asked), ...asked.paths->Array.map(inside)])
  | Bookmark => ("jj", [...repository, "bookmark", "move", "main", "--to", "@-"])
  | PushDry => ("mise", ["run", "push", ...name, "--dry-run"])
  | Push => verb("push")
  | Record =>
    switch asked.thread {
    | None => ("", [])
    | Some(thread) => (
        "mise",
        ["run", "//:thread", "landed", thread, asked.repository, "{commit}", asked.subject],
      )
    }
  }
}

let label = step =>
  switch step {
  | Format => "format"
  | Bump => "bump"
  | Check => "check"
  | Commit => "commit"
  | Bookmark => "bookmark"
  | PushDry => "push-dry"
  | Push => "push"
  | Record => "record"
  }

let quoted = value =>
  /^[A-Za-z0-9_./:@{}-]+$/->RegExp.test(value)
    ? value
    : "'" ++ value->String.replaceRegExp(/'/g, "'\"'\"'") ++ "'"

let raised = (~before, ~after, ~paths) =>
  paths->Array.concat(
    after->Array.filter(path => !(before->Array.includes(path)) && !(paths->Array.includes(path))),
  )

let causes = output => {
  let all =
    output
    ->String.split("\n")
    ->Array.map(line => line->String.replaceRegExp(/\u001b\[[0-9;]*m/g, "")->String.trimEnd)
    ->Array.filter(line => line != "")
  let flagged = all->Array.filter(line => Repos.marked->RegExp.test(line))
  (flagged == [] ? all : flagged)->Array.slice(~start=-8)
}

/** The paths a repository's working copy changes, relative to it. */
let changedNames = asked =>
  Node.spawnSync(
    "jj",
    ["diff", "--name-only"],
    {cwd: Node.join([Registry.root, directory(asked)]), encoding: "utf8", maxBuffer: 268435456},
  ).stdout
  ->Nullable.getOr("")
  ->String.split("\n")
  ->Array.map(String.trim)
  ->Array.filter(line => line != "")

let run = async asked => {
  let status = ref(0)
  // Paths given leave out what bump writes, so each file it changes joins them.
  let current = ref(asked)
  let before = ref([])
  if asked.dry {
    Console.log(
      `land: the check lock for ${asked.repository} is held by message between the integrators, never a file`,
    )
  }

  // A sibling's pin moves to its main at origin first, so CI builds what this landing checked.
  if asked.dry {
    Console.log(`land: pin: moved to its sibling's main@origin where it pins one behind it`)
  } else {
    switch Repin.moved(~root=Node.join([Registry.root, directory(asked)])) {
    | Ok(None) => ()
    | Ok(Some((from, to, pin))) =>
      Console.log(`land: pin: ${pin} moved from ${from} to ${to}`)
      if asked.paths != [] {
        current := {...current.contents, paths: [...current.contents.paths, pin]}
      }
    | Error(why) =>
      Console.log(`land: pin: ${why}`)
      status := 1
    }
  }
  for index in 0 to steps->Array.length - 1 {
    let step = steps->Array.getUnsafe(index)
    let (program, arguments) = command(current.contents, step)
    if status.contents == 0 && program != "" {
      Console.log(
        `land: ${label(step)}: ${[program, ...arguments]->Array.map(quoted)->Array.join(" ")}`,
      )
      if !asked.dry {
        let arguments = if step == Record {
          let (code, output) = await Node.stream(
            ~cwd=Registry.root,
            "jj",
            ["-R", directory(asked), "log", "-r", "main", "--no-graph", "-T", "commit_id.short()"],
          )
          status := code
          arguments->Array.map(value => value == "{commit}" ? output->String.trim : value)
        } else {
          arguments
        }
        if step == Bump && asked.paths != [] {
          before := changedNames(asked)
        }
        let output = ref("")
        if status.contents == 0 {
          let (code, streamed) = await Node.stream(~cwd=Registry.root, program, arguments)
          status := code
          output := streamed
        }
        if step == Bump && status.contents == 0 && asked.paths != [] {
          let paths = raised(
            ~before=before.contents,
            ~after=changedNames(asked),
            ~paths=current.contents.paths,
          )
          current := {...current.contents, paths}
        }
        if status.contents != 0 {
          causes(output.contents)->Array.forEach(line => Console.log(line))
          Console.log(`land: ${label(step)} failed, status ${Int.toString(status.contents)}`)
        }
      }
    }
  }
  status.contents
}

if Node.isMain {
  switch parse(Node.args()) {
  | Error(why) =>
    Console.error(why)
    Node.exit(2)
  | Ok(asked) => run(asked)->Promise.thenResolve(Node.exit)->ignore
  }
}
