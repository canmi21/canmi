/**
 * Holds every file of ours to `Code`'s line limits, docs/code.md, `lines [root ...]`. What is
 * generated, vendored or binary is not ours, and `lines=deferred` passes a file known to be over.
 */
let soft = Code.softLines
let hard = Code.hardLines
/** Machine output common enough to name here; what one project generates it marks itself. */
let common = [
  "*.lock",
  "*.lockb",
  "pnpm-lock.yaml",
  "package-lock.json",
  "*.min.js",
  "*.min.css",
  "*.map",
]
let sniff = 8000
let attributeNames = ["linguist-generated", "linguist-vendored", "lines"]

/** `name` against a glob of literal text and `*`, as fnmatch reads one with no slash in it. */
let matches = (name, glob) => {
  let pattern =
    glob
    ->String.split("*")
    ->Array.map(part => part->String.replaceRegExp(/[.+?^${}()|[\]\\]/g, "\\$&"))
    ->Array.join(".*")
  RegExp.fromString(`^${pattern}$`)->RegExp.test(name)
}

/**
 * The files version control keeps under `root`, jj first, since a second jj workspace has no
 * `.git`.
 */
let tracked = root =>
  if Node.existsSync(Node.join([root, ".jj"])) {
    Node.output(~cwd=root, "jj", ["file", "list"])
    ->String.split("\n")
    ->Array.filter(line => line != "")
  } else {
    Node.output(~cwd=root, "git", ["ls-files"])
    ->String.split("\n")
    ->Array.filter(line => line != "")
  }

/** A tree measured, its paths and each file's bytes, the working copy's or the commit `at`'s. */
type tree = {
  root: string,
  at: option<string>,
  paths: array<string>,
  bytes: string => option<Node.bytes>,
}

/** The working copy under `root`, read from the disk. */
let disk = root => {
  root,
  at: None,
  paths: tracked(root),
  bytes: path => Net.readBytesOf(Node.join([root, path])),
}

/** Each file `jj file show` printed, split at the NUL and `mark` heading it, then its path. */
let split: (Node.bytes, string) => array<(string, Node.bytes)> = %raw(`(bytes, mark) => {
  const marker = Buffer.from("\0" + mark);
  const found = [];
  let at = bytes.indexOf(marker);
  while (at !== -1) {
    const named = at + marker.length;
    const end = bytes.indexOf(0, named);
    const next = bytes.indexOf(marker, end + 1);
    found.push([
      bytes.subarray(named, end).toString("utf8"),
      bytes.subarray(end + 1, next === -1 ? bytes.length : next),
    ]);
    at = next;
  }
  return found;
}`)

let nonce: unit => string = %raw(`() => crypto.randomUUID()`)

/** The tree of the commit `at` in the repository at `root`, read by jj once, never checked out. */
let committed = (root, at) => {
  let read = args =>
    Node.execBytes(
      "jj",
      ["--ignore-working-copy", ...args, "-r", at],
      {cwd: root, maxBuffer: 1073741824},
    )
  let mark = nonce()
  let shown =
    read(["file", "show", "-T", `"\\0${mark}" ++ path ++ "\\0"`, "all()"])
    ->split(mark)
    ->Map.fromArray
  {
    root,
    at: Some(at),
    paths: read(["file", "list"])
    ->Node.chunkText
    ->String.split("\n")
    ->Array.filter(line => line != ""),
    bytes: path => shown->Map.get(path),
  }
}

/** Each path's attributes that are set, as git reads `.gitattributes` in the tree `at` names. */
let attributes = (root, paths: array<string>, ~at=?): Dict.t<Dict.t<string>> => {
  let found = Dict.make()
  let answer = Node.spawnSync(
    "git",
    Array.concat(
      ["check-attr", "--stdin"],
      Array.concat(at->Option.mapOr([], commit => [`--source=${commit}`]), attributeNames),
    ),
    {cwd: root, encoding: "utf8", input: paths->Array.join("\n"), maxBuffer: 268435456},
  )
  answer.stdout
  ->Nullable.getOr("")
  ->String.split("\n")
  ->Array.forEach(line => {
    let parts = line->String.split(": ")
    let count = parts->Array.length
    if count >= 3 {
      let value = parts->Array.getUnsafe(count - 1)
      let name = parts->Array.getUnsafe(count - 2)
      let path = parts->Array.slice(~start=0, ~end=count - 2)->Array.join(": ")
      if value != "unspecified" && value != "unset" {
        let held = found->Dict.get(path)->Option.getOr(Dict.make())
        held->Dict.set(name, value)
        found->Dict.set(path, held)
      }
    }
  })
  found
}

let nul: Node.bytes => bool = %raw(`bytes => bytes.subarray(0, 8000).includes(0)`)
let lineCount: Node.bytes => int = %raw(`bytes => {
  const text = bytes.toString("utf8");
  if (text === "") return 0;
  const lines = text.split(/\r\n|\r|\n/);
  return lines[lines.length - 1] === "" ? lines.length - 1 : lines.length;
}`)

/** Every file of ours in `tree` with its line count, and the ones it defers. */
let measured = (tree, ~workspace) => {
  let paths = tree.paths->Array.filter(path => {
    let parts = path->String.split("/")
    let name = parts->Array.at(-1)->Option.getOr(path)
    !(workspace && path->String.startsWith("repos/")) &&
    !(
      parts
      ->Array.slice(~start=0, ~end=parts->Array.length - 1)
      ->Array.some(part => part->String.startsWith("vendor"))
    ) &&
    !(common->Array.some(glob => matches(name, glob)))
  })
  let marks = attributes(tree.root, paths, ~at=?tree.at)
  let deferred = []
  let found = paths->Array.filterMap(path => {
    let mark = marks->Dict.get(path)->Option.getOr(Dict.make())
    if (
      mark->Dict.get("linguist-generated") == Some("true") ||
        mark->Dict.get("linguist-vendored") == Some("true")
    ) {
      None
    } else {
      switch tree.bytes(path) {
      | Some(bytes) if !nul(bytes) =>
        if mark->Dict.get("lines") == Some("deferred") {
          deferred->Array.push(path)
        }
        Some((path, lineCount(bytes)))
      | _ => None
      }
    }
  })
  (found, deferred)
}

/** The roots measured with none given, the workspace and each repository that keeps the rule. */
let roots = () =>
  Array.concat(
    [Registry.root],
    Waiting.active()
    ->Array.map(path => Node.join([Registry.repos, path]))
    ->Array.filter(where =>
      Node.existsSync(where) &&
      switch Project.read(where) {
      | Ok(declared) => declared.rules.lines
      | Error(_) => true
      }
    ),
  )

/** The lines part over `trees`, a file past the hard limit a form warning until `pushing`. */
let judged = (trees: array<tree>, ~pushing) => {
  let strict = Node.env->Dict.get("AUDIT")->Option.isSome
  let overHard = []
  let overSoft = []
  let postponed = []
  let stale = []
  let total = ref(0)
  trees->Array.forEach(tree => {
    let root = tree.root
    let (found, deferred) = measured(tree, ~workspace=root == Registry.root)
    found->Array.forEach(((path, count)) => {
      total := total.contents + 1
      let shown = Node.relative(Registry.root, Node.join([root, path]))
      if deferred->Array.includes(path) {
        count > hard ? postponed->Array.push((shown, count)) : stale->Array.push((shown, count))
      } else if count > hard {
        let onset = Onset.file(~root, path, ~limit=hard, ~at=?tree.at)
        overHard->Array.push((shown, count, onset))
      } else if count > soft {
        overSoft->Array.push((shown, count))
      }
    })
  })
  let largest = list => list->Array.toSorted(((_, a), (_, b)) => Int.toFloat(b - a))
  let int = Int.toString
  overSoft
  ->largest
  ->Array.forEach(((path, count)) =>
    Console.log(`warning: ${path} is ${int(count)} lines, over the soft limit of ${int(soft)}`)
  )
  postponed
  ->largest
  ->Array.forEach(((path, count)) =>
    Console.log(
      `warning: ${path} is ${int(count)} lines, over the hard limit of ${int(hard)}, deferred`,
    )
  )
  stale
  ->Array.map(((path, _)) => path)
  ->Array.toSorted(String.compare)
  ->Array.forEach(path =>
    Console.log(`warning: ${path} is under the hard limit; its \`lines=deferred\` can go`)
  )
  let failing = Form_layer.fails(~pushing)
  overHard
  ->Array.toSorted(((_, a, _), (_, b, _)) => Int.toFloat(b - a))
  ->Array.forEach(((path, count, onset)) =>
    Console.log(
      `${failing ? "error" : "warning"}: ${path} is ${int(
          count,
        )} lines, over the hard limit of ${int(hard)}${Onset.said(onset)}`,
    )
  )
  let warned = overSoft->Array.length + postponed->Array.length + stale->Array.length > 0
  Console.log(
    `lines: ${int(total.contents)} files measured, ${int(overSoft->Array.length)} over ${int(
        soft,
      )}, ${int(overHard->Array.length)} over ${int(hard)}, ${int(
        postponed->Array.length,
      )} deferred${strict ? " (audit: warnings fail)" : ""}`,
  )
  (failing && overHard->Array.length > 0) || (strict && warned) ? 1 : 0
}

/** The lines part over the working copy of each root given, or of every root measured. */
let main = (~given=[], ~pushing=false) =>
  judged(
    (given->Array.length > 0 ? given->Array.map(one => Node.resolve([one])) : roots())->Array.map(
      disk,
    ),
    ~pushing,
  )

if Node.isMain {
  Node.exit(main(~given=Node.args()))
}
