type asked = {
  repository: string,
  subject: string,
  trailers: array<string>,
  paths: array<string>,
  thread: option<string>,
  dry: bool,
}

let usage = "Land a repository's working copy: fmt, bump, check, commit, push: `land <name> -m <subject> [--trailer <line>]... [--paths <path>...] [--thread <name>] [--dry-run]`"

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
    Ok({
      repository,
      subject: subject.contents,
      trailers,
      paths,
      thread: thread.contents,
      dry: dry.contents,
    })
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
    let message =
      asked.trailers == []
        ? asked.subject
        : asked.subject ++ "\n\n" ++ asked.trailers->Array.join("\n")
    // jj reads a path from the directory it runs in, the workspace's root.
    let inside = path => directory(asked) == "." ? path : `${directory(asked)}/${path}`
    ("jj", [...repository, "commit", "-m", message, ...asked.paths->Array.map(inside)])
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

let run = async asked => {
  let status = ref(0)
  if asked.dry {
    Console.log(
      `land: the check lock for ${asked.repository} is held by message between the integrators, never a file`,
    )
  }
  for index in 0 to steps->Array.length - 1 {
    let step = steps->Array.getUnsafe(index)
    let (program, arguments) = command(asked, step)
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
        if status.contents == 0 {
          let (code, _) = await Node.stream(~cwd=Registry.root, program, arguments)
          status := code
        }
        if status.contents != 0 {
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
