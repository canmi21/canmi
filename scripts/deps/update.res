let cargoItems = (output, major) =>
  output
  ->String.split("\n")
  ->Array.filterMap(line => {
    if major {
      switch Actions.groups(/^\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s*$/, line) {
      | Some([name, from, _, _, to]) if /\d/->RegExp.test(from) && from != to && to != "-" =>
        Some(Reminder.item("major", name, from, to))
      | _ => None
      }
    } else {
      switch Actions.groups(/Updating (\S+) v(\S+) -> v(\S+)/, line) {
      | Some([name, from, to]) => Some(Reminder.item("package", name, from, to))
      | _ => None
      }
    }
  })

let toolLine = /^"?([^"=\s]+)"?\s*=\s*(.*)$/
let quotedPin = /^"([^"]*)"/
let prerelease = /^\d+(\.\d+)*-/

/** The tools a mise.toml's `[tools]` declares, a name quoted or bare, each with its plain pin. */
let toolsOf = (text: string): array<(string, string)> => {
  let found = []
  let inside = ref(false)
  text
  ->String.split("\n")
  ->Array.forEach(raw => {
    let line = raw->String.trim
    if line->String.startsWith("[") {
      inside := line->String.startsWith("[tools]")
    } else if inside.contents && !(line->String.startsWith("#")) {
      switch Actions.groups(toolLine, line) {
      | Some([name, value]) =>
        let pin = switch Actions.groups(quotedPin, value) {
        | Some([pin]) => pin
        | _ => ""
        }
        found->Array.push((name, pin))
      | _ => ()
      }
    }
  })
  found
}

/** Whether a tool is an npm package pinned at a prerelease, which mise's own upgrade never sees. */
let npmPrerelease = ((name, pin)) => name->String.startsWith("npm:") && prerelease->RegExp.test(pin)

/** npm's `latest` and when it was published, as `pnpm view` answers both in JSON. */
let viewOf = (answer: string): (string, option<float>) =>
  switch JSON.parseOrThrow(answer == "" ? "{}" : answer) {
  | Object(fields) =>
    let latest = switch fields->Dict.get("dist-tags.latest") {
    | Some(String(latest)) => latest
    | _ => ""
    }
    let published = switch fields->Dict.get("time") {
    | Some(Object(times)) =>
      switch times->Dict.get(latest) {
      | Some(String(at)) => Some(Date.fromString(at)->Date.getTime)
      | _ => None
      }
    | _ => None
    }
    (latest, published)
  | _ => ("", None)
  | exception _ => ("", None)
  }

/** -1, 0 or 1 as SemVer orders two versions, a prerelease's parts among themselves too. */
let semver = (a: string, b: string): int => {
  let split = version =>
    switch version->String.indexOf("-") {
    | -1 => (version, None)
    | dash => (
        version->String.slice(~start=0, ~end=dash),
        Some(version->String.slice(~start=dash + 1)),
      )
    }
  let ((core, pre), (other, otherPre)) = (split(a), split(b))
  let part = (x, y) =>
    switch (Int.fromString(x), Int.fromString(y)) {
    | (Some(p), Some(q)) if Outdated.digits->RegExp.test(x) && Outdated.digits->RegExp.test(y) =>
      p == q ? 0 : p < q ? -1 : 1
    | _ if Outdated.digits->RegExp.test(x) => -1
    | _ if Outdated.digits->RegExp.test(y) => 1
    | _ => x == y ? 0 : x < y ? -1 : 1
    }
  let rec parts = (x, y, index) =>
    switch (x[index], y[index]) {
    | (None, None) => 0
    | (None, Some(_)) => -1
    | (Some(_), None) => 1
    | (Some(p), Some(q)) =>
      let found = part(p, q)
      found == 0 ? parts(x, y, index + 1) : found
    }
  switch Outdated.compare(core, other) {
  | 0 =>
    switch (pre, otherPre) {
    | (None, None) => 0
    | (None, Some(_)) => 1
    | (Some(_), None) => -1
    | (Some(x), Some(y)) => parts(x->String.split("."), y->String.split("."), 0)
    }
  | found => found
  }
}

type move = Moves(string) | Young(string) | Stays

/** Where a prerelease pin moves, to npm's newer latest once it is as old as a package must be. */
let npmMove = (~pin, ~latest, ~published: option<float>, ~now: float) =>
  if latest == "" || semver(latest, pin) <= 0 {
    Stays
  } else {
    switch published {
    | Some(at) if now -. at >= Int.toFloat(Toolchain.releaseAge) *. 60000. => Moves(latest)
    | _ => Young(latest)
    }
  }

/** `text` with the tool `name` in `[tools]` pinned at `to`, every other line as it was. */
let repinned = (text: string, name: string, to: string): string => {
  let inside = ref(false)
  text
  ->String.split("\n")
  ->Array.map(line => {
    let trimmed = line->String.trim
    if trimmed->String.startsWith("[") {
      inside := trimmed->String.startsWith("[tools]")
      line
    } else {
      switch inside.contents ? Actions.groups(toolLine, trimmed) : None {
      | Some([found, _]) if found == name =>
        line->String.replaceRegExp(/=(\s*)"[^"]*"/, `=$1"${to}"`)
      | _ => line
      }
    }
  })
  ->Array.join("\n")
}

/**
 * A repository's `update`, its tools, crates and packages within their bounds, and with `--major`
 * across them for what outdated.res calls behind. See docs/toolchain/dependencies.md.
 */
let machine = async () => {
  let root = Node.cwd()
  let items = await Tools.machine(root)
  if Node.existsSync("package.json") {
    Outdated.machine(root)->Array.forEach(item => items->Array.push(item))
  }
  if Node.existsSync("Cargo.toml") {
    let result = Node.spawnSync(
      "cargo",
      ["update", "--dry-run"],
      {encoding: "utf8", maxBuffer: 268435456},
    )
    let output = result.stdout->Nullable.getOr("") ++ result.stderr->Nullable.getOr("")
    cargoItems(output, false)->Array.forEach(item => items->Array.push(item))
    let majors = Node.spawnSync(
      "cargo",
      ["upgrade", "--incompatible", "--compatible", "ignore", "--dry-run"],
      {encoding: "utf8", maxBuffer: 268435456},
    )
    let output = majors.stdout->Nullable.getOr("") ++ majors.stderr->Nullable.getOr("")
    cargoItems(output, true)->Array.forEach(item => items->Array.push(item))
  }
  Console.log(Reminder.encode(items))
}
let human = async () => {
  let args = Node.args()
  let dry =
    args->Array.includes("--dry-run") ||
    args->Array.includes("-n") ||
    Node.envIs("usage_dry_run", "true")
  let major = args->Array.includes("--major") || Node.envOn("usage_major")
  let n = dry ? ["--dry-run"] : []
  let declared = Node.existsSync("mise.toml") ? toolsOf(Node.readFileSync("mise.toml")) : []

  // A bare mise upgrade moves every tool it sees, the workspace's too, so it is given names alone.
  let own = declared->Array.filterMap(tool => npmPrerelease(tool) ? None : Some(Pair.first(tool)))
  if own != [] {
    Console.log(`$ mise upgrade ${own->Array.join(" ")}${dry ? " --dry-run" : ""}`)
    Node.run("mise", Array.concat(Array.concat(["upgrade"], own), n))->ignore
    // A pin is crossed too, onto its tool's newest stable release, the npm prereleases below apart.
    let prereleases =
      declared->Array.filterMap(tool => npmPrerelease(tool) ? Some(Pair.first(tool)) : None)
    let (_, left) = await Tools.cross(Node.cwd(), ~dry, ~skip=["rust", ...prereleases])
    left->Array.forEach(((bump: Tools.bump, why)) =>
      Console.log(`${bump.tool} ${bump.version}: ${why}`)
    )
    Console.log("")
  }

  // mise skips prereleases, so an npm tool pinned at one follows npm's latest instead.
  declared
  ->Array.filter(npmPrerelease)
  ->Array.forEach(((name, pin)) => {
    let package = name->String.slice(~start=4)
    let answer = Node.output("pnpm", ["view", package, "dist-tags.latest", "time", "--json"])
    let (latest, published) = viewOf(answer)
    switch npmMove(~pin, ~latest, ~published, ~now=Date.now()) {
    | Stays if latest == "" => Console.log(`${name} ${pin}: npm answered no latest`)
    | Stays => Console.log(`${name} ${pin} stays, npm's latest is ${latest}`)
    | Young(to) => Console.log(`${name} ${pin} -> ${to} waits out the release age`)
    | Moves(to) =>
      Console.log(`${name} ${pin} -> ${to}${dry ? ", a dry run writing nothing" : ""}`)
      if !dry {
        Node.writeFileSync("mise.toml", repinned(Node.readFileSync("mise.toml"), name, to))
      }
    }
  })
  if Node.existsSync("Cargo.toml") {
    let before = Node.existsSync("Cargo.lock") ? Some(Node.readFileSync("Cargo.lock")) : None
    if major {
      if (
        Node.spawnSync("sh", ["-c", "command -v cargo-upgrade"], {stdio: "ignore"}).status ==
          Nullable.make(0)
      ) {
        Node.run("cargo", Array.concat(["upgrade", "--incompatible"], n))->ignore
      } else {
        Console.log("cargo-edit is not installed: the crates' majors were not checked")
      }
    }
    Node.run("cargo", Array.concat(["update"], n))->ignore
    let after = Node.existsSync("Cargo.lock") ? Some(Node.readFileSync("Cargo.lock")) : None

    // A lock moved runs the bump, raising a version only where released code changed, RFC 8c0rg.
    if !dry && before != after && Node.existsSync(".github/release/bump.res") {
      if Node.run("mise", ["run", "bump"]) != 0 {
        Node.exit(1)
      }
    }
    Console.log("")
  }
  if !Node.existsSync("package.json") {
    Node.exit(0)
  }
  if dry {
    Console.log(Outdated.report(Node.cwd(), false)->Array.join("\n"))
    Node.exit(0)
  }
  let names = major ? Outdated.report(Node.cwd(), true) : []
  Console.log(`$ pnpm update -r${major ? ` --latest ${names->Array.join(" ")}` : ""}`)
  if major && names->Array.length == 0 {
    Console.log("nothing waits beyond its range")
    Node.exit(0)
  }
  let updated = Node.spawnSync(
    "pnpm",
    Array.concat(["update", "-r"], major ? Array.concat(["--latest"], names) : []),
    {encoding: "utf8", maxBuffer: 268435456},
  )
  let out =
    `${updated.stdout->Nullable.getOr("")}${updated.stderr->Nullable.getOr(
        "",
      )}`->String.replaceRegExp(/\n$/, "")
  Console.log(out)
  if updated.status != Nullable.make(0) {
    if !(out->String.includes("ERR_PNPM_NO_MATURE_MATCHING_VERSION")) {
      Node.exit(1)
    }
    Console.log(
      "held by the supply-chain delay, nothing moved in the pnpm half; run again once it has aged",
    )
  }
}

if Node.isMain {
  if Node.args()->Array.includes("--json") {
    machine()->Promise.thenResolve(_ => Node.exit(0))->Promise.catch(_ => Node.exit(1))->ignore
  } else {
    human()
    ->Promise.catch(error => {
      switch error {
      | Registry.Refused(why) => Console.error(`error: ${why}`)
      | _ => Console.error("error: update failed")
      }
      Node.exit(1)
    })
    ->ignore
  }
}
