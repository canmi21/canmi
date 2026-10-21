/**
 * The reference rules two gates share, that a link and a citation resolve and a section exists.
 * Each gate states only which files it reads and how a citation resolves from where it sits.
 */
let mdLink = /\[[^\]]*\]\(([^)]+)\)/g
/** A path as a doc writes one, lowercase throughout, as docs/naming.md asks. */
let docPath = "[a-z0-9-]+(?:/[a-z0-9-]+)*\\.md"
/** A citation's tail past its prefix, directories lowercase and the basename as named. */
let docTail = "(?:[a-z0-9-]+/)*[A-Za-z0-9-]+\\.md"
/** The entry point every tree carries, citable by anchor and by nothing else. */
let rootDocs = "AGENTS\\.md"
/** A section a citation names, quoted after it, never across a full stop or a semicolon. */
let anchor = `[^".;\\n]{1,60}?"(?<anchor>[^"]{6,160})"`
let docAnchor = RegExp.fromString(
  `(?:\\[[^\\]]*\\]\\()?(?<target>(?:\\.\\./)*${docPath})\\)?${anchor}`,
  ~flags="g",
)
/** A wrapped anchor's continuation lines folded away, `///` and `//!` tried before `//`. */
let commentWrap = /\n[ \t]*(?:\*|\/\/\/|\/\/!|\/\/|#)?[ \t]*/g
/** Prose carries no comment markers. */
let proseWrap = /\n\s*/g
let spaces = /\s+/g
let notWord = /[^a-z0-9 ]/g
let fence = /```[\s\S]*?```/g
let inlineCode = /`[^`\n]+`/g
/** Who a citation names as its owner just before it, `platform's spec/...` or `the workspace's`. */
let ownerOf = /\b(\w+)'s `?$/

let read = path =>
  try Node.readFileSync(path) catch {
  | _ => ""
  }

/** Every file git knows about under `root`, less the names and the trees the caller excludes. */
let tracked = (root, ~skipFiles=[], ~skipDirs=[]) =>
  Node.output(
    ~cwd=root,
    "git",
    ["-C", root, "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
  )
  ->String.split("\x00")
  ->Array.filter(name =>
    name != "" &&
    !(skipFiles->Array.includes(Node.basename(name))) &&
    !(name->String.split("/")->Array.some(part => skipDirs->Array.includes(part)))
  )
  ->Array.map(name => Node.join([root, name]))
  // The index still lists a file deleted since the last commit; what is on disk is what is read.
  ->Array.filter(Node.existsSync)

/** Whether a tracked file with no extension is text, and so can hold a citation. */
let extensionlessText = path =>
  Node.extname(path) == "" && {
      let body = read(path)
      body != "" && !(body->String.includes("\x00"))
    }

/** Code, plus the extensionless text lying beside it. */
let citingFiles = (files, suffixes) =>
  files->Array.filter(path =>
    suffixes->Array.includes(Node.extname(path)) || extensionlessText(path)
  )

/** Fenced blocks and inline code blanked, lines kept, since an example of a link is none. */
let withoutCode = text =>
  text
  ->String.replaceRegExpBy0Unsafe(fence, (~match, ~offset as _, ~input as _) =>
    String.repeat("\n", match->String.split("\n")->Array.length - 1)
  )
  ->String.replaceRegExpBy0Unsafe(inlineCode, (~match, ~offset as _, ~input as _) =>
    String.repeat(" ", match->String.length)
  )

/** Text reduced to its lowercase words, every other character a space, collapsed last. */
let flatten = text =>
  text
  ->String.toLowerCase
  ->String.replaceRegExp(notWord, " ")
  ->String.replaceRegExp(spaces, " ")
  ->String.trim

let bodies: Dict.t<string> = Dict.make()

/** One file flattened and kept, or None when it is not there. */
let flattened = (path: option<string>) =>
  switch path {
  | Some(path) if Node.stat(path)->Option.mapOr(false, stats => stats->Node.statsIsFile) =>
    switch bodies->Dict.get(path) {
    | Some(body) => Some(body)
    | None =>
      let body = flatten(read(path))
      bodies->Dict.set(path, body)
      Some(body)
    }
  | _ => None
  }

/** The anchor pattern for one gate's idea of a citation. */
let codeAnchor = target => RegExp.fromString(`(?<target>${target})${anchor}`, ~flags="g")

type found = {whole: string, target: string, anchor: string, index: int}

@send external matchAll: (string, RegExp.t) => Iterator.t<RegExp.Result.t> = "matchAll"
@get external index: RegExp.Result.t => int = "index"
@get external groups: RegExp.Result.t => Nullable.t<Dict.t<string>> = "groups"

let each = (pattern, text) =>
  text
  ->matchAll(pattern)
  ->Iterator.toArray
  ->Array.map(result => {
    let named = result->groups->Nullable.toOption->Option.getOr(Dict.make())
    {
      whole: result->RegExp.Result.fullMatch,
      target: named->Dict.get("target")->Option.getOr(""),
      anchor: named->Dict.get("anchor")->Option.getOr(""),
      index: result->index,
    }
  })

/** cited doc -> the files that cite it. */
let pairGraph = (root, files, pattern): Dict.t<array<string>> => {
  let graph = Dict.make()
  files->Array.forEach(path => {
    let relative = Node.relative(root, path)
    each(pattern, read(path))
    ->Array.map(one => one.whole)
    ->Set.fromArray
    ->Set.values
    ->Iterator.toArray
    ->Array.toSorted(String.compare)
    ->Array.forEach(cited =>
      graph->Dict.set(cited, Array.concat(graph->Dict.get(cited)->Option.getOr([]), [relative]))
    )
  })
  graph
}

/** Markdown links that point at nothing, split from those `elsewhere` reads as absent instead. */
let deadLinks = (root, docs, ~elsewhere: option<string => bool>=?) => {
  let dead = []
  let absent = []
  docs->Array.forEach(doc =>
    Graph.groups(mdLink, withoutCode(read(doc)))->Array.forEach(target =>
      if (
        !(
          ["http://", "https://", "#", "mailto:"]->Array.some(
            prefix => target->String.startsWith(prefix),
          )
        )
      ) {
        let landing = Node.join([Node.dirname(doc), target->String.split("#")->Array.getUnsafe(0)])
        if !Node.existsSync(landing) {
          let entry = `${Node.relative(root, doc)} -> ${target}`
          elsewhere->Option.mapOr(false, elsewhere => elsewhere(landing))
            ? absent->Array.push(entry)
            : dead->Array.push(entry)
        }
      }
    )
  )
  (dead, absent)
}

/** A repository the registry lists by its path or by the last part of it. */
let repositoryNamed = name =>
  Registry.paths()->Array.find(path =>
    path == name || path->String.split("/")->Array.at(-1) == Some(name)
  )

/** The cited file in the repository the text before it names, or None when it names none. */
let owned = (root, before, cited) =>
  switch ownerOf
  ->RegExp.exec(before)
  ->Option.flatMap(result => result->RegExp.Result.matches->Array.get(0))
  ->Option.flatMap(x => x) {
  | None => None
  | Some(name) if name == Node.basename(root) => None
  | Some("workspace") =>
    let rec up = at => {
      let parent = Node.dirname(at)
      parent == at
        ? None
        : Node.existsSync(Node.join([parent, cited]))
        ? Some(Node.join([parent, cited]))
        : up(parent)
    }
    up(root)
  | Some(name) =>
    repositoryNamed(name)
    ->Option.map(path => Node.join([Registry.repos, path, cited]))
    ->Option.flatMap(path => Node.existsSync(path) ? Some(path) : None)
  }

/** Section names quoted from code or another doc that the named file no longer holds. */
let deadAnchors = (
  root,
  sources: array<(string, RegExp.t, RegExp.t)>,
  resolve: (string, string) => option<string>,
) => {
  let dead = []
  let seen = ref(0)
  sources->Array.forEach(((path, pattern, wrap)) => {
    let text = read(path)->String.replaceRegExp(wrap, " ")
    each(pattern, text)->Array.forEach(found => {
      let before = text->String.slice(~start=Math.Int.max(0, found.index - 40), ~end=found.index)
      let body = switch flattened(owned(root, before, found.target)) {
      | Some(body) => Some(body)
      | None => flattened(resolve(path, found.target))
      }
      switch body {
      | Some(body) =>
        seen := seen.contents + 1
        if !(body->String.includes(flatten(found.anchor))) {
          dead->Array.push(`${Node.relative(root, path)} -> ${found.target} ("${found.anchor}")`)
        }
      | None => ()
      }
    })
  })
  (dead, seen.contents)
}
