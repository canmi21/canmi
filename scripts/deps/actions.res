let machine = Node.args()->Array.includes("--json")
let items: array<Reminder.item> = []
let log = text =>
  if !machine {
    Console.log(text)
  }
let emit = () =>
  if machine {
    Console.log(Reminder.encode(items))
  }

/**
 * The releases a repository's workflows pin, each moved to the newest one a day old within its
 * major unless `--major`, and the branches pinned by a commit, each moved to its head. See
 * docs/toolchain/ci.md.
 */
type release = {
  @as("tag_name") tag: string,
  @as("published_at") published: Nullable.t<string>,
  prerelease: bool,
  draft: bool,
}

/** How long a release waits before a pin moves to it, as long as minimumReleaseAge holds one. */
let delay =
  24. *. 60. *. 60. *. 1000.

/** A step's `uses`, its repository, a path inside it, the commit pinned and the release named. */
let uses = /^(\s*(?:-\s+)?uses:\s+)([\w.-]+\/[\w.-]+)((?:\/[^@\s]+)?)@([0-9a-f]{40})(\s+#\s+)(\S+)\s*$/

/** A value whose comment names the repository it is a release of. */
let named = /^(\s*(?:-\s+)?[\w-]+:\s+)("?)([\w.+-]+)\2(\s+#\s+)([\w.-]+\/[\w.-]+)\s*$/

/** One line a release is pinned on, and how it is written again with another. */
type pin = {
  index: int,
  repository: string,
  current: string,
  /** Whether the line also pins the release's commit. */
  commit: bool,
  write: (string, string) => string,
}

let groups = (pattern, line) =>
  pattern
  ->RegExp.exec(line)
  ->Option.map(result => result->RegExp.Result.matches->Array.map(group => group->Option.getOr("")))

/** Every pin in a workflow's text, by its line. */
let pins = (text: string): array<pin> =>
  text
  ->String.split("\n")
  ->Array.mapWithIndex((line, index) =>
    switch groups(uses, line) {
    | Some([prefix, repository, path, _, separator, current]) =>
      Some({
        index,
        repository,
        current,
        commit: true,
        write: (version, commit) => `${prefix}${repository}${path}@${commit}${separator}${version}`,
      })
    | _ =>
      switch groups(named, line) {
      | Some([prefix, quote, current, separator, repository]) =>
        Some({
          index,
          repository,
          current,
          commit: false,
          write: (version, _) => `${prefix}${quote}${version}${quote}${separator}${repository}`,
        })
      | _ => None
      }
    }
  )
  ->Array.filterMap(pin => pin)

/** A commit whose comment names the repository and the branch it follows. */
let followed = /^(\s*(?:-\s+)?[\w-]+:\s+)([0-9a-f]{40})(\s+#\s+)([\w.-]+\/[\w.-]+)@([\w.\/-]+)\s*$/

/** One line a branch is pinned on by a commit, and how it is written again with another. */
type head = {
  index: int,
  repository: string,
  branch: string,
  current: string,
  write: string => string,
}

/** Every branch pinned in a workflow's text, by its line. */
let heads = (text: string): array<head> =>
  text
  ->String.split("\n")
  ->Array.mapWithIndex((line, index) =>
    switch groups(followed, line) {
    | Some([prefix, current, separator, repository, branch]) =>
      Some({
        index,
        repository,
        branch,
        current,
        write: commit => `${prefix}${commit}${separator}${repository}@${branch}`,
      })
    | _ => None
    }
  )
  ->Array.filterMap(head => head)

/** A version without the `v` a tag may open with. */
let bare = version => version->String.startsWith("v") ? version->String.slice(~start=1) : version

/** A tag spelled as `like` is, with its `v` or without. */
let spelled = (tag, like) => like->String.startsWith("v") ? tag : bare(tag)

/** What a pin at `current` may move to, what waits out the day, and what lies past its major. */
type plan = {move: option<string>, waiting: option<string>, beyond: option<string>}

let plan = (releases: array<release>, current, ~across, ~now): plan => {
  let numbered =
    releases->Array.filter(release =>
      !release.draft && !release.prerelease && /^\d/->RegExp.test(bare(release.tag))
    )
  let newer = release => Outdated.compare(bare(release.tag), bare(current)) > 0
  let inside = release => Outdated.major(bare(release.tag)) == Outdated.major(bare(current))
  let aged = release =>
    release.published
    ->Nullable.toOption
    ->Option.mapOr(false, date => now -. Date.fromString(date)->Date.getTime >= delay)
  let newest = list =>
    switch list->Array.map(release => release.tag) {
    | [] => None
    | tags => Some(tags->Array.toSorted((a, b) => Outdated.order(bare(a), bare(b)))->Array.at(-1))
    }->Option.flatMap(tag => tag)
  let candidates = numbered->Array.filter(release => newer(release) && (across || inside(release)))
  let move = newest(candidates->Array.filter(aged))
  let waiting =
    newest(candidates->Array.filter(release => !aged(release)))->Option.filter(tag =>
      move->Option.mapOr(true, moved => Outdated.compare(bare(tag), bare(moved)) > 0)
    )
  let beyond = across
    ? None
    : newest(numbered->Array.filter(release => !inside(release) && newer(release)))
  {move, waiting, beyond}
}

/** What `gh api` answers for `path` once, given `Net.patience`, or why it did not. */
@module("node:child_process")
external execFile: (
  string,
  array<string>,
  {"timeout": int, "maxBuffer": int, "encoding": string},
  (Nullable.t<JsExn.t>, string, string) => unit,
) => unit = "execFile"
let ghOnce = path =>
  Promise.make((resolve, _) =>
    execFile(
      "gh",
      ["api", path],
      {"timeout": Net.patience, "maxBuffer": 268435456, "encoding": "utf8"},
      (error, stdout, stderr) => resolve(error->Nullable.isNullable ? Ok(stdout) : Error(stderr)),
    )
  )

/** Whether GitHub refused a path for good, a 4xx, which asking again would not change. */
let refused = (stderr: string) => /HTTP 4\d\d/->RegExp.test(stderr)

/** The environment variable naming the directory one `update` run keeps GitHub's answers in. */
let answersVariable = "UPDATE_ANSWERS"

/** A file name for `path`'s answer in that directory. */
let answerFile = path => path->String.replaceRegExp(/[^\w.-]/g, "_") ++ ".json"

/**
 * An asker of `gh api` paths, each asked once per process and, where `directory` is given, once
 * per `update` run across its repositories; a stalled or failed read is asked again on a fresh
 * connection, and only an answer that came is kept.
 */
let asker = (~directory: option<string>, ~once=ghOnce) => {
  let known: Map.t<string, promise<option<string>>> = Map.make()
  path =>
    switch known->Map.get(path) {
    | Some(answer) => answer
    | None =>
      let kept = directory->Option.map(directory => Node.join([directory, answerFile(path)]))
      let answer = switch kept {
      | Some(file) if Node.existsSync(file) => Promise.resolve(Some(Node.readFileSync(file)))
      | _ =>
        Net.retried(~again=why => !refused(why), () => once(path))->Promise.thenResolve(result =>
          switch result {
          | Ok(text) =>
            kept->Option.forEach(file =>
              try Node.writeFileSync(file, text) catch {
              | _ => ()
              }
            )
            Some(text)
          | Error(_) => None
          }
        )
      }
      known->Map.set(path, answer)
      answer
    }
}

/**
 * Runs `work`, one `update`, with a directory its movers keep GitHub's answers in, so an action
 * several repositories pin is asked once, the directory removed when the work ends.
 */
let answering = async work => {
  let answers = Node.mkdtempSync(Node.join([Node.tmpdir(), "update-answers-"]))
  Node.env->Dict.set(answersVariable, answers)
  let forget = () => {
    Node.env->Dict.delete(answersVariable)
    Node.rmSync(answers, {recursive: true, force: true})
  }
  switch await work() {
  | code =>
    forget()
    code
  | exception error =>
    forget()
    throw(error)
  }
}

/** What GitHub answers for `path`, parsed, or None where it could not be read. */
@scope("JSON") @val external parse: string => 'a = "parse"
let ask = asker(~directory=Node.env->Dict.get(answersVariable))
let api = async path => (await ask(path))->Option.map(text => parse(text))

type target = {@as("type") kind: string, sha: string}
type tip = {sha: string}
type pointer = {@as("object") target: target}

/** The commit a tag names, an annotated tag followed to the commit it points at. */
let commitOf = async (repository, tag) => {
  let rec follow = async (target: target) =>
    switch target.kind {
    | "commit" => Some(target.sha)
    | "tag" =>
      switch await api(`repos/${repository}/git/tags/${target.sha}`) {
      | Some(pointer: pointer) => await follow(pointer.target)
      | None => None
      }
    | _ => None
    }
  switch await api(`repos/${repository}/git/ref/tags/${tag}`) {
  | Some(pointer: pointer) => await follow(pointer.target)
  | None => None
  }
}

/** How many of a repository's actions are asked about at once. */
let asking = 4

let main = async () => {
  let args = Node.args()
  // In CI it reports alone, as GitHub refuses a workflow change pushed by its token, docs/ci.md.
  let ci = Node.envIs("CI", "true")
  if ci {
    log("actions: in CI the pins are read and reported alone; a local update moves them")
  }
  let dry = machine || ci || args->Array.includes("--dry-run") || args->Array.includes("-n")
  let across = args->Array.includes("--major")
  let github = Node.join([Node.cwd(), ".github"])
  let yaml = file => file->String.endsWith(".yml") || file->String.endsWith(".yaml")
  let within = (directory, keep) => {
    let at = Node.join([github, directory])
    Node.existsSync(at) ? Node.readdir(at)->Array.filterMap(keep(at)) : []
  }
  // A workflow, or a composite action a workflow calls, each at `.github/actions/<name>/`.
  let files = Array.concat(
    within("workflows", _ => file => yaml(file) ? Some(`workflows/${file}`) : None),
    within("actions", at =>
      name =>
        ["action.yml", "action.yaml"]
        ->Array.find(file => Node.existsSync(Node.join([at, name, file])))
        ->Option.map(file => `actions/${name}/${file}`)
    ),
  )
  if files == [] {
    log("actions: no workflow here")
    emit()
    Node.exit(0)
  }
  let now = Date.now()
  let releasesOf = repository => api(`repos/${repository}/releases?per_page=100`)
  let headOf = (head: head) => api(`repos/${head.repository}/commits/${head.branch}`)
  let sorted = files->Array.toSorted(String.compare)
  // Every release list and head the files name is asked first, a few at once, the walk below
  // then reading the answers in its own order.
  let texts = sorted->Array.map(file => Node.readFileSync(Node.join([github, file])))
  let wanted =
    Array.concat(
      texts->Array.flatMap(text =>
        pins(text)->Array.map(pin => `repos/${pin.repository}/releases?per_page=100`)
      ),
      texts->Array.flatMap(text =>
        heads(text)->Array.map(head => `repos/${head.repository}/commits/${head.branch}`)
      ),
    )
    ->Set.fromArray
    ->Set.values
    ->Iterator.toArray
  let _ = await Net.bounded(wanted, ~limit=asking, ask)
  let failed = ref(false)
  let wrote = ref(false)
  for at in 0 to sorted->Array.length - 1 {
    let file = sorted->Array.getUnsafe(at)
    let path = Node.join([github, file])
    let lines = texts->Array.getUnsafe(at)->String.split("\n")
    let changed = ref(false)
    let found = pins(lines->Array.join("\n"))
    for index in 0 to found->Array.length - 1 {
      let pin = found->Array.getUnsafe(index)
      let name = `${file} ${pin.repository}`
      switch await releasesOf(pin.repository) {
      | None =>
        log(`actions: ${name} ${pin.current}, its releases could not be read`)
        failed := true
      | Some(releases) =>
        let {move, waiting, beyond} = plan(releases, pin.current, ~across, ~now)
        beyond->Option.forEach(tag =>
          items->Array.push(Reminder.item("major", name, pin.current, spelled(tag, pin.current)))
        )
        let notes =
          [
            waiting->Option.map(tag => `${tag} waits out its first day`),
            beyond->Option.map(tag => `${tag} is past its major`),
          ]->Array.filterMap(note => note)
        let after = notes->Array.length == 0 ? "" : `; ${notes->Array.join("; ")}`
        switch move {
        | None => log(`actions: ${name} ${pin.current}, the newest a day old${after}`)
        | Some(tag) =>
          let version = spelled(tag, pin.current)
          items->Array.push(
            Reminder.item(
              Outdated.major(bare(version)) == Outdated.major(bare(pin.current))
                ? "action"
                : "major",
              name,
              pin.current,
              version,
            ),
          )
          switch pin.commit ? await commitOf(pin.repository, tag) : Some("") {
          | None =>
            log(`actions: ${name} ${tag}, its commit could not be read`)
            failed := true
          | Some(commit) =>
            log(`actions: ${name} ${pin.current} -> ${version}${after}`)
            lines->Array.setUnsafe(pin.index, pin.write(version, commit))
            changed := true
          }
        }
      }
    }
    let branches = heads(lines->Array.join("\n"))
    for index in 0 to branches->Array.length - 1 {
      let head = branches->Array.getUnsafe(index)
      let name = `${file} ${head.repository}@${head.branch}`
      let short = commit => commit->String.slice(~start=0, ~end=12)
      switch await headOf(head) {
      | None =>
        log(`actions: ${name} ${short(head.current)}, its head could not be read`)
        failed := true
      | Some(tip: tip) if tip.sha == head.current =>
        log(`actions: ${name} ${short(head.current)}, its head`)
      | Some(tip: tip) =>
        items->Array.push(Reminder.item("action", name, head.current, tip.sha))
        log(`actions: ${name} ${short(head.current)} -> ${short(tip.sha)}`)
        lines->Array.setUnsafe(head.index, head.write(tip.sha))
        changed := true
      }
    }
    if changed.contents && !dry {
      Node.writeFileSync(path, lines->Array.join("\n"))
      wrote := true
    }
  }

  // A pin moved raises the version of what is released from it, monoflake/driver's RFC 8c0rg.
  if wrote.contents && Node.existsSync(Node.join([github, "release", "bump.res"])) {
    if Node.run("mise", ["run", "bump"]) != 0 {
      failed := true
    }
  }
  emit()
  Node.exit(failed.contents ? 1 : 0)
}

if Node.isMain {
  main()->ignore
}
