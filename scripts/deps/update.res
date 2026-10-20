/**
 * A repository's `update`: its own `[tools]` within their pins, its crates and its packages within
 * their ranges, and with `--major` across them for what outdated.res calls behind -- a package
 * `versions.toml` allows at two majors left on both. See docs/toolchain.md, "Dependencies move the
 * way tools do". `--dry-run` says what would move and writes nothing.
 */
let args = Node.args()
let dry =
  args->Array.includes("--dry-run") ||
  args->Array.includes("-n") ||
  Node.envIs("usage_dry_run", "true")
let major = args->Array.includes("--major") || Node.envOn("usage_major")
let n = dry ? ["--dry-run"] : []
let toolName = /^([a-z0-9-]*) *=/

/** The tools this repository's own `mise.toml` declares, by name. */
let ownTools = () => {
  let names = []
  let inside = ref(false)
  Node.readFileSync("mise.toml")
  ->String.split("\n")
  ->Array.forEach(line =>
    if line->String.startsWith("[") {
      inside := line->String.startsWith("[tools]")
    } else if inside.contents {
      switch toolName->RegExp.exec(line) {
      | Some(result) =>
        switch result->RegExp.Result.matches {
        | [Some(name)] => names->Array.push(name)
        | _ => ()
        }
      | None => ()
      }
    }
  )
  names
}

let own = ownTools()
Console.log(`$ mise upgrade ${own->Array.join("\n")}${dry ? " --dry-run" : ""}`)
Node.run("mise", Array.concat(Array.concat(["upgrade"], own), n))->ignore
Console.log("")
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
Console.log("")
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
