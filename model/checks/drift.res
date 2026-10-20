/**
 * Prose a repository's AGENTS.md or docs say that the workspace's already do, or that another
 * repository's say too: a sentence most of whose runs of `run` words appear there. A warning, not
 * a failure -- docs/repos.md, "A repository's own rules extend the workspace's".
 */
let run = 8
let share = 0.6
/** Fewer words than this is a phrase two documents share by accident, not a rule said twice. */
let shortest = 12

type sentence = {file: string, line: int, opening: string, grams: array<string>}

/** What holds a repository's rules: its AGENTS.md, and the prose under docs/ or its old name. */
let ruling = path =>
  path == "AGENTS.md" ||
    ([Layout.rulesHome, Layout.retired]->Array.some(home => path->String.startsWith(home ++ "/")) &&
    path->String.endsWith(".md") &&
    !(path->String.includes("/rfcs/")))

let word = /[a-z0-9]+/g

let gramsOf = text => {
  let words =
    text->String.toLowerCase->String.match(word)->Option.getOr([])->Array.filterMap(w => w)
  words->Array.length < shortest
    ? []
    : Array.fromInitializer(~length=words->Array.length - run + 1, at =>
        words->Array.slice(~start=at, ~end=at + run)->Array.join(" ")
      )
}

/** A document's sentences, code and tables left out, each with the line its paragraph opens on. */
let sentences = (text, ~file): array<sentence> => {
  let found = []
  let fenced = ref(false)
  let paragraph = ref([])
  let opened = ref(0)
  let close = () => {
    paragraph.contents
    ->Array.join(" ")
    ->String.replaceRegExp(/`[^`]*`/g, " ")
    ->String.replaceRegExp(/([.!?;])\s+/g, "$1\n")
    ->String.split("\n")
    ->Array.forEach(said => {
      let grams = gramsOf(said)
      if grams != [] {
        let opening = said->String.split(" ")->Array.slice(~start=0, ~end=6)->Array.join(" ")
        found->Array.push({file, line: opened.contents, opening, grams})
      }
    })
    paragraph := []
  }
  text
  ->String.split("\n")
  ->Array.forEachWithIndex((line, at) => {
    let trimmed = line->String.trim
    if trimmed->String.startsWith("```") {
      close()
      fenced := !fenced.contents
    } else if fenced.contents || trimmed->String.startsWith("|") {
      ()
    } else if trimmed == "" {
      close()
    } else {
      if paragraph.contents == [] {
        opened := at + 1
      }
      paragraph.contents->Array.push(trimmed)
    }
  })
  close()
  found
}

let read = root =>
  Lines.tracked(root)
  ->Array.filter(ruling)
  ->Array.flatMap(path => {
    let file = Node.join([root, path])
    Node.existsSync(file) ? sentences(Node.readFileSync(file), ~file=path) : []
  })

/** Each sentence of `repositories`, by label, that the workspace's `own` or another's says. */
let problems = (~own: array<sentence>, ~repositories: array<(string, array<sentence>)>, ~only) => {
  let workspace = Dict.make()
  own->Array.forEach(said =>
    said.grams->Array.forEach(gram =>
      if workspace->Dict.get(gram)->Option.isNone {
        workspace->Dict.set(gram, said.file)
      }
    )
  )
  let holders = Dict.make()
  repositories->Array.forEach(((label, said)) =>
    said->Array.forEach(sentence =>
      sentence.grams->Array.forEach(
        gram => {
          let have = holders->Dict.get(gram)->Option.getOr([])
          if !(have->Array.includes(label)) {
            have->Array.push(label)
            holders->Dict.set(gram, have)
          }
        },
      )
    )
  )
  let shared = (grams, count) => Int.toFloat(count) >= share *. Int.toFloat(grams->Array.length)
  repositories
  ->Array.filter(((label, _)) => only->Option.mapOr(true, chosen => chosen == label))
  ->Array.flatMap(((label, said)) =>
    said->Array.filterMap(sentence => {
      let where = `${label}/${sentence.file}:${Int.toString(
          sentence.line,
        )} "${sentence.opening} ..."`
      let restated = sentence.grams->Array.filterMap(gram => workspace->Dict.get(gram))
      if shared(sentence.grams, restated->Array.length) {
        Some(`${where}: restates the workspace's ${restated->Array.getUnsafe(0)}`)
      } else {
        let others =
          sentence.grams->Array.map(
            gram =>
              holders->Dict.get(gram)->Option.getOr([])->Array.filter(other => other != label),
          )
        let named = Set.fromArray(others->Array.flat)->Set.values->Array.fromIterator
        shared(sentence.grams, others->Array.filter(found => found != [])->Array.length)
          ? Some(
              `${where}: ${named
                ->Array.toSorted(String.compare)
                ->Array.join(", ")} say it too; two repositories' rule is the workspace's`,
            )
          : None
      }
    })
  )
}

/** Each finding once, in the order found, as a paragraph's sentences can repeat one. */
let distinct = found => Set.fromArray(found)->Set.values->Array.fromIterator

let main = (~only: option<string>): array<string> => {
  let repositories =
    Registry.paths()
    ->Array.filter(path => !(Layout.archives->Array.includes(path)))
    ->Array.filter(path => Node.existsSync(Node.join([Registry.repos, path])))
    ->Array.map(path => (path, read(Node.join([Registry.repos, path]))))
  distinct(problems(~own=read(Registry.root), ~repositories, ~only))
}
