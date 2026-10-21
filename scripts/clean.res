/**
 * A repository's `clean`, what cargo and the JavaScript tools built and never a dependency or local
 * state, docs/toolchain.md. Arguments name further caches.
 */
/** What `find` lists from `root`, a path a line, as the shell's `find` loops read them. */
let find = (root, findArgs) =>
  Node.execFileSync(
    "find",
    Array.concat(["."], findArgs),
    {cwd: root, encoding: "utf8", maxBuffer: 268435456},
  )
  ->String.split("\n")
  ->Array.filter(line => line != "")

let pruned = ["-name", ".git", "-o", "-name", ".jj", "-o", "-name", "target"]
let built = [".svelte-kit", "dist", "build", "coverage", ".turbo", ".output", "__pycache__"]
let dropped = [".vite", ".vite-temp", ".cache", ".vitest", ".svelte2tsx-language-server-files"]

/** `-name a -o -name b ...` for each of `names`. */
let anyName = names =>
  names->Array.flatMapWithIndex((name, index) =>
    index == 0 ? ["-name", name] : ["-o", "-name", name]
  )

/** Every path a tool may have written, in the order the shell version found them. */
let candidates = (root, ~extra=[]) => {
  let prune = more => [["("], pruned, more, [")", "-prune", "-o"]]->Array.flat
  let made = find(
    root,
    [
      prune(["-o", "-name", "node_modules", "-o", "-name", ".wrangler", "-o", "-name", ".vercel"]),
      ["-type", "d", "("],
      anyName(built),
      [")", "-print", "-prune"],
    ]->Array.flat,
  )
  let installed = find(root, [prune([]), ["-name", "node_modules", "-prune", "-print"]]->Array.flat)
  let inside = installed->Array.flatMap(one =>
    Node.lstatSync(Node.join([root, one]))->Node.statsIsSymbolicLink
      ? []
      : dropped
        ->Array.map(cache => `${one}/${cache}`)
        ->Array.filter(path =>
          Node.stat(Node.join([root, path]))->Option.mapOr(
            false,
            stats => stats->Node.statsIsDirectory,
          )
        )
  )
  let below = (name, keep) =>
    find(
      root,
      [
        prune(["-o", "-name", "node_modules"]),
        ["-type", "d", "-name", name, "-prune", "-print"],
      ]->Array.flat,
    )->Array.map(directory => `${directory}/${keep}`)
  [
    made,
    inside,
    extra->Array.map(path => `./${path}`),
    below(".wrangler", "tmp"),
    below(".vercel", "output"),
  ]->Array.flat
}

/** `du -sh`'s size of `path`, as the shell version printed it. */
let size = (root, path) =>
  Node.output(~cwd=root, "du", ["-sh", path])
  ->String.trim
  ->String.splitByRegExp(Spawn.whitespace)
  ->Array.get(0)
  ->Option.flatMap(word => word)
  ->Option.getOr("")

/** The task `clean [--dry-run] [extra cache...]`, run from the repository's root. */
let main = (~root=Node.cwd(), ~args=Node.args()) => {
  let dry =
    args->Array.includes("--dry-run") ||
    args->Array.includes("-n") ||
    Node.envIs("usage_dry_run", "true")
  let extra = args->Array.filter(arg => !(arg->String.startsWith("-")))

  // cargo has nothing to clean, and fails, where there is no crate.
  if !Node.existsSync(Node.join([root, "Cargo.toml"])) {
    ()
  } else if dry {
    Console.log(
      `would run cargo clean, ${Node.existsSync(Node.join([root, "target"]))
          ? size(root, "target")
          : ""}`,
    )
  } else if Node.run(~cwd=root, "cargo", ["clean"]) != 0 {
    Node.exit(1)
  }
  let found = ref(false)
  candidates(root, ~extra)->Array.forEach(path =>
    if Node.existsSync(Node.join([root, path])) {
      let ignored =
        Node.spawnSync("git", ["check-ignore", "-q", path], {cwd: root}).status == Nullable.make(0)
      let tracked = Node.output(~cwd=root, "git", ["ls-files", "--", path])->String.trim != ""
      if ignored && !tracked {
        found := true
        if dry {
          Console.log(`would remove ${path}, ${size(root, path)}`)
        } else {
          Node.rmSync(Node.join([root, path]), {recursive: true, force: true})
          Console.log(`removed ${path}`)
        }
      }
    }
  )
  if !found.contents {
    Console.log("no tool caches to remove")
  }
}

if Node.isMain {
  main()
}
