/**
 * `update` over many repositories at once, in waves: the workspace first, as every repository reads
 * its [tools], then each repository once every sibling whose checkout its own build reaches into
 * has finished, a few at a time. See docs/repos.md.
 */
/** The environment variable a wave's child is handed, naming the file its outcome goes to. */
let outcomeVariable = "UPDATE_OUTCOME"

/** How many repositories update at once in a wave. */
let width = 3

/** What one or more repositories' update came to, by repository label. */
type outcome = {
  skipped: array<string>,
  failed: array<string>,
  reverted: array<(string, array<string>, array<string>)>,
  held: array<(string, array<string>)>,
}

let nothing = () => {skipped: [], failed: [], reverted: [], held: []}

/** A path a file names that leaves its own directory: a link or a file, a path dependency, a
 * sibling repository given by name, a directory given to `-C` or `cd`. */
let reaching = /(?:link:|file:|path\s*=\s*"|repository\s*=\s*"|-C\s+|\bcd\s+)(\.\.\/[^"'\s,;)]+)/g

/** The files that declare what reaches across checkouts. */
let declaring = ["package.json", "pnpm-workspace.yaml", "Cargo.toml", "workspace.toml", "mise.toml"]

/** Directories no declaration of a build lives in. */
let passed = [
  "node_modules",
  "target",
  ".git",
  ".jj",
  ".svelte-kit",
  ".wrangler",
  "dist",
  "build",
  "vendor",
]

/** How deep below a repository's root its declaring files are looked for. */
let deepest = 4

/**
 * The repositories among `others` that `text`, a declaring file at `file` inside `repo`, reaches
 * into, each once.
 */
let reached = (~repo: string, ~file: string, ~others: array<string>, text: string) => {
  let found = []
  reaching->RegExp.setLastIndex(0)
  let rec next = () =>
    switch reaching->RegExp.exec(text) {
    | Some(result) =>
      switch result->RegExp.Result.matches {
      | [Some(relative)] =>
        let target = Node.resolve([Node.dirname(file), relative])
        let inside = target == repo || target->String.startsWith(repo ++ "/")
        if !inside {
          others
          ->Array.find(other =>
            other != repo && (target == other || target->String.startsWith(other ++ "/"))
          )
          ->Option.forEach(other => found->Array.includes(other) ? () : found->Array.push(other))
        }
      | _ => ()
      }
      next()
    | None => ()
    }
  next()
  found
}

/** Every declaring file under `repo`, `deepest` levels down at most. */
let declarations = repo => {
  let files = []
  let rec walk = (directory, depth) =>
    try {
      Node.readdirTyped(directory, {withFileTypes: true})->Array.forEach(entry => {
        let name = entry->Node.name
        let path = Node.join([directory, name])
        if entry->Node.isDirectory {
          if depth < deepest && !(passed->Array.includes(name)) {
            walk(path, depth + 1)
          }
        } else if entry->Node.isFile && declaring->Array.includes(name) {
          files->Array.push(path)
        }
      })
    } catch {
    | _ => ()
    }
  walk(repo, 0)
  files
}

/**
 * Each repository of `repos` with the siblings among them whose checkout its build reaches into, as
 * (repository, sibling, the file that says so).
 */
let edges = (repos: array<string>) =>
  repos->Array.flatMap(repo =>
    declarations(repo)->Array.flatMap(file =>
      reached(~repo, ~file, ~others=repos, Node.readFileSync(file))->Array.map(
        sibling => (repo, sibling, file),
      )
    )
  )

/**
 * The waves `repos` update in: `first` alone where it is among them, then each repository in the
 * wave after the last of its siblings; a cycle left over goes one at a time, in `repos`' order.
 */
let plan = (repos: array<string>, ~first, ~edges: array<(string, string, string)>) => {
  let rest = repos->Array.filter(repo => repo != first)
  let after = repo =>
    edges->Array.filterMap(((from, sibling, _)) =>
      from == repo && rest->Array.includes(sibling) ? Some(sibling) : None
    )
  let waves = repos->Array.includes(first) ? [[first]] : []
  let finished = []
  let rec layer = remaining =>
    if remaining != [] {
      let ready =
        remaining->Array.filter(repo =>
          after(repo)->Array.every(one => finished->Array.includes(one))
        )
      if ready == [] {
        remaining->Array.forEach(repo => waves->Array.push([repo]))
      } else {
        waves->Array.push(ready)
        ready->Array.forEach(repo => finished->Array.push(repo))
        layer(remaining->Array.filter(repo => !(ready->Array.includes(repo))))
      }
    }
  layer(rest)
  waves
}

/** `outcome` kept for the parent of a wave, as JSON at `file`. */
let keep = (file, outcome: outcome) =>
  Node.writeFileSync(file, JSON.stringifyAny(outcome)->Option.getOr("{}"))

@scope("JSON") @val external parsed: string => outcome = "parse"

/** The outcomes of `parts` as one, each list in the order of `order`. */
let merged = (parts: array<(string, outcome)>, ~order: array<string>) => {
  let at = label => order->Array.findIndex(one => one == label)
  let byOrder = (a, b) => Int.toFloat(at(a) - at(b))
  let all = parts->Array.map(((_, outcome)) => outcome)
  {
    skipped: all->Array.flatMap(one => one.skipped)->Array.toSorted(byOrder),
    failed: all->Array.flatMap(one => one.failed)->Array.toSorted(byOrder),
    reverted: all
    ->Array.flatMap(one => one.reverted)
    ->Array.toSorted(((a, _, _), (b, _, _)) => byOrder(a, b)),
    held: all->Array.flatMap(one => one.held)->Array.toSorted(((a, _), (b, _)) => byOrder(a, b)),
  }
}

/** The command a wave's child runs: this dispatcher's `update`, for one repository. */
let updating = (~root, ~flags, repo) => (
  "node",
  [
    Node.join([root, "scripts", "workspace", "repos.res.mjs"]),
    "update",
    Registry.label(repo),
    ...flags,
  ],
)

/**
 * Updates `repo` as a child of the wave, its whole output kept as one block, never interleaved with
 * another's, and what it came to read back from the file it kept.
 */
let child = async (repo, ~root, ~command) => {
  let file = Node.join([
    Node.mkdtempSync(Node.join([Node.tmpdir(), "update-outcome-"])),
    "outcome.json",
  ])
  Node.env->Dict.set(outcomeVariable, file)
  let (program, programArgs) = command(repo)
  let running = Node.captured(~cwd=root, program, programArgs)
  Node.env->Dict.delete(outcomeVariable)
  let (status, stdout, stderr) = await running
  let outcome = try parsed(Node.readFileSync(file)) catch {
  | _ => {...nothing(), failed: status == 0 ? [] : [Registry.label(repo)]}
  }
  Node.rmSync(Node.dirname(file), {recursive: true, force: true})
  (`${stdout}${stderr}`->String.replaceRegExp(/\n+$/, ""), outcome)
}

/**
 * `update` over `repos` in waves, `here` running the workspace's own in this process, every other
 * repository a child; one outcome for them all, in `repos`' order.
 */
let run = async (repos: array<string>, ~root, ~flags, ~here: array<string> => promise<outcome>) => {
  let waves = plan(repos, ~first=root, ~edges=edges(repos))
  let parts = []
  for index in 0 to waves->Array.length - 1 {
    let wave = waves->Array.getUnsafe(index)
    if wave == [root] {
      parts->Array.push((root, await here(wave)))
    } else {
      // Each block is printed whole as its repository ends, so a wave's output never interleaves.
      let outcomes = await Net.bounded(wave, ~limit=width, async repo => {
        let (block, outcome) = await child(repo, ~root, ~command=updating(~root, ~flags, ...))
        Console.log(block)
        outcome
      })
      wave->Array.forEachWithIndex((repo, at) =>
        parts->Array.push((repo, outcomes->Array.getUnsafe(at)))
      )
    }
  }
  merged(parts, ~order=repos->Array.map(Registry.label))
}

/** What `outcome` says under the summary: pins held back, then what verify reverted. */
let told = (outcome: outcome) => {
  outcome.held
  ->Array.filter(((place, _)) =>
    !(outcome.failed->Array.includes(place)) &&
    !(outcome.reverted->Array.some(((back, _, _)) => back == place))
  )
  ->Array.forEach(((place, sources)) =>
    Console.log(
      `warning: ${place} holds back its pins from ${sources->Array.join(
          ", ",
        )}, whose releases were not read; the rest that moved is kept`,
    )
  )
  if outcome.reverted != [] {
    Console.log(
      "\nReverted, because verify failed with what moved; these files are back as they were:\n",
    )
    outcome.reverted->Array.forEach(((place, shown, paths)) => {
      Console.log(`  ${place}: ${paths->Array.join(", ")}`)
      shown->Array.forEach(line => Console.log(`      ${line}`))
    })
    Console.log("\n  the full log is above; the next `update` tries the same bounds again")
  }
}
