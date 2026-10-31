/** The shared formatter for repository tasks described in docs/repos.md. */
type globOptions = {cwd: string}
@module("node:fs") external globSync: (string, globOptions) => array<string> = "globSync"

let defaultGlob = "**/*.{ts,tsx,mts,cts,js,mjs,cjs,jsx,css,json,jsonc,md,svelte}"

/** An option takes patterns until the next flag and may be repeated. */
let values = (args, flag) => {
  let taking = ref(false)
  args->Array.filter(value => {
    if value->String.startsWith("-") {
      taking := value == flag
      false
    } else {
      taking.contents
    }
  })
}

let matches = (root, patterns) =>
  patterns
  ->Array.flatMap(pattern =>
    Node.existsSync(Node.join([root, pattern])) ? [pattern] : globSync(pattern, {cwd: root})
  )
  ->Array.toSorted(String.compare)

type command = {program: string, args: array<string>}
type nix = {flake: string, files: array<string>}

/** Each flake keeps its own pin and the extra files use the first flake's pin. */
let nix = (root, args) => {
  let patterns = values(args, "--nix-files")
  let flakes = values(args, "--nixfmt")->Array.flatMap(pattern => matches(root, [pattern]))
  flakes
  ->Array.filter(flake =>
    Node.stat(Node.join([root, flake]))->Option.mapOr(false, Node.statsIsDirectory)
  )
  ->Array.mapWithIndex((flake, index) => {
    let files =
      patterns->Array.length == 0
        ? matches(root, [Node.join([flake, "*.nix"])])
        : matches(root, patterns)
    {
      flake: Node.join([root, flake]),
      files: [files, index == 0 ? matches(root, values(args, "--nix-extra")) : []]->Array.flat,
    }
  })
}

let commands = (root, args, ~dry) => {
  let globs = values(args, "--glob")
  [
    args->Array.includes("--rescript")
      ? [{program: "rescript", args: dry ? ["format", "--check"] : ["format"]}]
      : [],
    Node.existsSync(Node.join([root, "Cargo.toml"]))
      ? [
          {
            program: "cargo",
            args: dry ? ["fmt", "--all", "--check", "--message-format", "short"] : ["fmt", "--all"],
          },
        ]
      : [],
    [
      {
        program: "oxfmt",
        args: [
          dry ? ["--list-different"] : [],
          ["--no-error-on-unmatched-pattern"],
          globs->Array.length == 0 ? [defaultGlob] : globs,
        ]->Array.flat,
      },
    ],
  ]->Array.flat
}

/** Nix reads a flake copy as recorded in docs/lessons.md. */
let formatNix = (~dry, ~run, job) => {
  if job.files->Array.length == 0 {
    0
  } else {
    let copy = Node.mkdtempSync(Node.join([Node.tmpdir(), "fmt-"]))->Node.realpathSync
    let status = try {
      ["flake.nix", "flake.lock"]->Array.forEach(name =>
        Node.writeFileSync(Node.join([copy, name]), Node.readFileSync(Node.join([job.flake, name])))
      )
      run({
        program: "nix",
        args: [
          ["run", "--inputs-from", `path:${copy}`, "nixpkgs#nixfmt", "--"],
          dry ? ["--check"] : [],
          job.files,
        ]->Array.flat,
      })
    } catch {
    | error =>
      Node.run("trash", [copy])->ignore
      throw(error)
    }
    Node.run("trash", [copy])->ignore
    status
  }
}

let format = (~root, ~args, ~dry, ~run) => {
  let rec steps = remaining =>
    switch remaining {
    | list{} => 0
    | list{step, ...rest} =>
      let status = step()
      !dry && status != 0 ? status : steps(rest)
    }
  [
    commands(root, args, ~dry)->Array.map(command => () => run(command)),
    nix(root, args)->Array.map(job => () => formatNix(~dry, ~run, job)),
  ]
  ->Array.flat
  ->List.fromArray
  ->steps
}

if Node.isMain {
  let args = Node.args()
  let dry =
    args->Array.includes("--dry-run") ||
    args->Array.includes("-n") ||
    Node.envIs("usage_dry_run", "true")
  Node.exit(
    format(~root=Node.cwd(), ~args, ~dry, ~run=({program, args}) => Node.run(program, args)),
  )
}
