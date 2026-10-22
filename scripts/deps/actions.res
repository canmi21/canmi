/**
 * The releases a repository's workflows pin, each moved to the newest one a day old within its
 * major unless `--major`. See docs/toolchain.md.
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

/** What `gh api` answers for `path`, parsed, or None where it failed. */
@scope("JSON") @val external parse: string => 'a = "parse"
let api = path => {
  let answer = Node.spawnSync("gh", ["api", path], {encoding: "utf8", maxBuffer: 268435456})
  answer.status == Nullable.make(0) ? Some(parse(answer.stdout->Nullable.getOr(""))) : None
}

type target = {@as("type") kind: string, sha: string}
type pointer = {@as("object") target: target}

/** The commit a tag names, an annotated tag followed to the commit it points at. */
let commitOf = (repository, tag) => {
  let rec follow = (target: target) =>
    switch target.kind {
    | "commit" => Some(target.sha)
    | "tag" =>
      api(`repos/${repository}/git/tags/${target.sha}`)->Option.flatMap((pointer: pointer) =>
        follow(pointer.target)
      )
    | _ => None
    }
  api(`repos/${repository}/git/ref/tags/${tag}`)->Option.flatMap((pointer: pointer) =>
    follow(pointer.target)
  )
}

let main = () => {
  let args = Node.args()
  let dry = args->Array.includes("--dry-run") || args->Array.includes("-n")
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
    Console.log("actions: no workflow here")
    Node.exit(0)
  }
  let now = Date.now()
  let known = Map.make()
  let releasesOf = repository =>
    switch known->Map.get(repository) {
    | Some(releases) => releases
    | None =>
      let releases = api(`repos/${repository}/releases?per_page=100`)
      known->Map.set(repository, releases)
      releases
    }
  let failed = ref(false)
  files
  ->Array.toSorted(String.compare)
  ->Array.forEach(file => {
    let path = Node.join([github, file])
    let lines = Node.readFileSync(path)->String.split("\n")
    let changed = ref(false)
    pins(lines->Array.join("\n"))->Array.forEach(pin => {
      let name = `${file} ${pin.repository}`
      switch releasesOf(pin.repository) {
      | None =>
        Console.log(`actions: ${name} ${pin.current}, its releases could not be read`)
        failed := true
      | Some(releases) =>
        let {move, waiting, beyond} = plan(releases, pin.current, ~across, ~now)
        let notes =
          [
            waiting->Option.map(tag => `${tag} waits out its first day`),
            beyond->Option.map(tag => `${tag} is past its major`),
          ]->Array.filterMap(note => note)
        let after = notes->Array.length == 0 ? "" : `; ${notes->Array.join("; ")}`
        switch move {
        | None => Console.log(`actions: ${name} ${pin.current}, the newest a day old${after}`)
        | Some(tag) =>
          let version = spelled(tag, pin.current)
          switch pin.commit ? commitOf(pin.repository, tag) : Some("") {
          | None =>
            Console.log(`actions: ${name} ${tag}, its commit could not be read`)
            failed := true
          | Some(commit) =>
            Console.log(`actions: ${name} ${pin.current} -> ${version}${after}`)
            lines->Array.setUnsafe(pin.index, pin.write(version, commit))
            changed := true
          }
        }
      }
    })
    if changed.contents && !dry {
      Node.writeFileSync(path, lines->Array.join("\n"))
    }
  })
  Node.exit(failed.contents ? 1 : 0)
}

if Node.isMain {
  main()
}
