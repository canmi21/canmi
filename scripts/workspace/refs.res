/**
 * How this workspace refers to its own files, `refs [--json]`: a markdown link in a doc resolves,
 * a doc under `docs/`, or under a project's `repos/<path>/`, cited from code exists -- unless it is
 * in a project not cloned, a note and no failure -- and a section quoted beside it exists. With
 * `--json`, the pair graph instead.
 */
let codeSuffixes = [
  ".ts",
  ".js",
  ".mjs",
  ".rs",
  ".py",
  ".res",
  ".toml",
  ".json",
  ".jsonc",
  ".yaml",
  ".yml",
]
/** Generated, enormous, and citing nothing. */
let skipFiles = ["pnpm-lock.yaml"]

/** This workspace's docs and, below it, a project's, both resolving at the root. */
let cited = `(?:repos/[a-z0-9-]+/${References.docTail}|docs/${References.docTail})`
let codeRef = RegExp.fromString(cited, ~flags="g")
let codeAnchor = References.codeAnchor(`${cited}|${References.rootDocs}`)

let root = Registry.root
let files = () => References.tracked(root, ~skipFiles)
let docs = () =>
  files()->Array.filter(path => Node.extname(path) == ".md")->Array.toSorted(String.compare)

/** Where a citation points: beside the citing file, or from the root. */
let resolve = (path, cited) =>
  [Node.join([Node.dirname(path), cited]), Node.join([root, cited])]->Array.find(Node.existsSync)

/** Whether a citation lands in a repository the registry lists that this machine has not cloned. */
let uncloned = target => {
  let rest = Node.relative(Registry.repos, target)
  !(rest->String.startsWith("..")) &&
  Registry.paths()->Array.some(path =>
    rest->String.startsWith(`${path}/`) && !Node.existsSync(Node.join([Registry.repos, path]))
  )
}

let main = (~json=false) => {
  let citing = References.citingFiles(files(), codeSuffixes)
  let graph = References.pairGraph(root, citing, codeRef)
  if json {
    Console.log(JSON.stringifyAny(graph)->Option.getOr("{}"))
    0
  } else {
    let written = docs()
    let sources = Array.concat(
      citing->Array.map(path => (path, codeAnchor, References.commentWrap)),
      written->Array.map(doc => (doc, References.docAnchor, References.proseWrap)),
    )
    let (dead, absent) = References.deadLinks(root, written, ~elsewhere=uncloned)
    let (stale, anchors) = References.deadAnchors(root, sources, resolve)
    let gone =
      graph->Dict.toArray->Array.filter(((spec, _)) => !Node.existsSync(Node.join([root, spec])))
    let absent = Array.concat(
      absent,
      gone
      ->Array.filter(((spec, _)) => uncloned(Node.join([root, spec])))
      ->Array.map(((spec, _)) => spec),
    )
    let problems = [
      dead->Array.map(one => `dead link: ${one}`),
      gone
      ->Array.filter(((spec, _)) => !uncloned(Node.join([root, spec])))
      ->Array.toSorted(((a, _), (b, _)) => a < b ? -1. : 1.)
      ->Array.map(((spec, by)) => `missing spec cited by ${by->Array.join(", ")}: ${spec}`),
      stale->Array.map(one => `missing section: ${one}`),
    ]->Array.flat
    if problems->Array.length > 0 {
      Console.error("Reference check failed:\n")
      problems->Array.forEach(problem => Console.error(`  ${problem}`))
      1
    } else {
      let linked = graph->Dict.valuesToArray->Array.reduce(0, (sum, by) => sum + by->Array.length)
      let note =
        absent->Array.length > 0
          ? `, ${Int.toString(absent->Array.length)} into projects not cloned here`
          : ""
      Console.log(
        `references OK: ${Int.toString(written->Array.length)} docs, ${Int.toString(
            linked,
          )} code -> spec citations, ${Int.toString(anchors)} quoted sections${note}`,
      )
      0
    }
  }
}

if Node.isMain {
  Node.exit(main(~json=Node.args()->Array.includes("--json")))
}
