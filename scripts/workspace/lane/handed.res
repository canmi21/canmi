/**
 * What a lane's diff holds against its rules, `lane handed <name> [--own <directory> ...]` and the
 * size part of `lane close`, docs/agents/lanes.md. Lengths read `hardLines` and `splitBeforeLines`.
 */
type finding = {file: string, why: string}

type judged = {refused: array<finding>, listed: array<finding>}

/** The lockfiles an integrator writes again when a wave is merged, `lockfile-derived`. */
let lockfiles = ["pnpm-lock.yaml", "Cargo.lock", "flake.lock", "package-lock.json", "yarn.lock"]

/** The paths a lane changed against where it forked from main, or the failure to read them. */
let changed = cwd => {
  let answer = Node.spawnSync(
    "jj",
    ["diff", "--from", "fork_point(main | @)", "--to", "@", "--name-only"],
    {cwd, encoding: "utf8", maxBuffer: 268435456},
  )
  answer.status->Nullable.toOption == Some(0)
    ? Ok(
        answer.stdout
        ->Nullable.getOr("")
        ->String.split("\n")
        ->Array.filter(line => line != ""),
      )
    : Error(answer.stderr->Nullable.getOr("jj diff failed")->String.trim)
}

let under = (file, entry) =>
  entry->String.endsWith("/") ? file->String.startsWith(entry) : file == entry

let basename = file => file->String.split("/")->Array.at(-1)->Option.getOr(file)

/** Each file past `Code.hardLines`, refused, and past `Code.splitBeforeLines`, listed. */
let sizes = (~lines, files) => {
  let counted =
    files
    ->Array.filter(file => !(Lines.common->Array.some(glob => Lines.matches(basename(file), glob))))
    ->Array.filterMap(file => lines(file)->Option.map(count => (file, count)))
  {
    refused: counted
    ->Array.filter(((_, count)) => count > Code.hardLines)
    ->Array.map(((file, count)) => {
      file,
      why: `${Int.toString(count)} lines, past hardLines ${Int.toString(Code.hardLines)}`,
    }),
    listed: counted
    ->Array.filter(((_, count)) => count > Code.splitBeforeLines && count <= Code.hardLines)
    ->Array.map(((file, count)) => {
      file,
      why: `${Int.toString(count)} lines, past splitBeforeLines ${Int.toString(
          Code.splitBeforeLines,
        )}`,
    }),
  }
}

/** The files that only the integrator changes, `single-writer`. */
let single = files =>
  // The integrator runs with no role, and lands what only it may change.
  Node.env->Dict.get("MONOFLAKE_ROLE") == None
    ? []
    : files
      ->Array.filter(file => Delegation.singleWriter->Array.some(under(file, _)))
      ->Array.map(file => {file, why: "only the integrator changes it, single-writer"})

/** The lockfiles a lane changed, which are written again at the merge, `lockfile-derived`. */
let locked = files =>
  files
  ->Array.filter(file => lockfiles->Array.includes(basename(file)))
  ->Array.map(file => {file, why: "a lockfile is written again at the merge, lockfile-derived"})

/** The files outside every directory in `own`, `own-directory`, none judged where none is given. */
let outside = (~own, files) =>
  own == []
    ? []
    : files
      ->Array.filter(file => !(own->Array.some(dir => file->String.startsWith(dir ++ "/"))))
      ->Array.map(file => {file, why: "outside the block's own directory, own-directory"})

/** What a lane's changed files hold against all the rules `handed` reads. */
let judge = (~lines, ~own, files) => {
  let size = sizes(~lines, files)
  {
    refused: Array.flat([size.refused, single(files), locked(files), outside(~own, files)]),
    listed: size.listed,
  }
}

/** Each formatter a changed file is held to, the program, its checking flags and its owner. */
let formatters = [
  ("rescript", ["format", "--check"], "rescript format"),
  ("oxfmt", ["--list-different", "--no-error-on-unmatched-pattern"], "oxfmt"),
  ("rustfmt", ["--check"], "rustfmt"),
]

/** The checks to run over `files`, each a program, its arguments and the files it reads. */
let formatPlan = files =>
  formatters->Array.filterMap(((program, flags, owner)) => {
    let suffixes =
      Format.owners->Array.filterMap(((suffix, formatter)) =>
        formatter == Format.Formats(owner) ? Some(suffix) : None
      )
    let mine =
      files->Array.filter(file => suffixes->Array.some(suffix => file->String.endsWith(suffix)))
    mine == [] ? None : Some((program, Array.concat(flags, mine), mine))
  })

/** The files a formatter would change, `check` giving a run's status and everything it said. */
let unformatted = (~check, files) =>
  formatPlan(files)->Array.flatMap(((program, args, mine)) => {
    let (status, said) = check(program, args)
    let named = mine->Array.filter(file => said->String.includes(file))
    status == 0
      ? []
      : (named == [] ? mine : named)->Array.map(file => {file, why: `needs formatting, ${program}`})
  })

let shown = ({file, why}) => `${file}: ${why}`

/** The lines of a file of a working copy, none where it is gone or not text. */
let linesOf = (~cwd, file) =>
  try {
    let text = Node.readFileSync(Node.join([cwd, file]))
    let parts = text->String.split("\n")
    Some(text->String.endsWith("\n") ? Array.length(parts) - 1 : Array.length(parts))
  } catch {
  | _ => None
  }

/** A formatter run in `cwd`, its status and everything it said. */
let checkIn = (~cwd, program, args) => {
  let answer = Node.spawnSync(program, args, {cwd, encoding: "utf8", maxBuffer: 268435456})
  (
    answer.status->Nullable.getOr(1),
    answer.stdout->Nullable.getOr("") ++ answer.stderr->Nullable.getOr(""),
  )
}

/** The parts of the form layer finding something over the tree `cwd` would commit, each logged. */
let formedIn = cwd =>
  switch Commit_tree.tree(cwd, ~place=cwd, ~filesets=[]) {
  | Ok(tree) => Commit_tree.refused(cwd, tree)->Array.map(((name, _)) => name)
  | Error(why) => [why]
  }

/**
 * One working copy judged and printed, `all` for every rule of `handed` with formatting and the
 * form layer, else lengths alone.
 */
let report = (~cwd, ~dir, ~own, ~all, ~check=?, ~form=formedIn) => {
  let check = check->Option.getOr((program, args) => checkIn(~cwd, program, args))
  switch changed(cwd) {
  | Error(why) =>
    Console.error(`${dir} could not be judged: ${why}`)
    1
  | Ok(files) =>
    // A generated or vendored file is not ours to size, as the lines part of the check has it.
    let marks = Lines.attributes(cwd, files)
    let theirs = file => {
      let mark = marks->Dict.get(file)->Option.getOr(Dict.make())
      ["linguist-generated", "linguist-vendored"]->Array.some(name =>
        mark->Dict.get(name) == Some("true")
      )
    }
    let lines = file => theirs(file) ? None : linesOf(~cwd, file)
    let judged = all ? judge(~lines, ~own, files) : sizes(~lines, files)
    let loose = all
      ? unformatted(~check, files->Array.filter(file => Node.existsSync(Node.join([cwd, file]))))
      : []
    let formed = all ? form(cwd) : []
    judged.listed->Array.forEach(one => Console.log(`${dir}/${shown(one)}`))
    Array.concat(judged.refused, loose)->Array.forEach(one => Console.error(`${dir}/${shown(one)}`))
    formed->Array.forEach(name => Console.error(`${dir}: the form layer finds this in ${name}`))
    judged.refused == [] && loose == [] && formed == [] ? 0 : 1
  }
}
