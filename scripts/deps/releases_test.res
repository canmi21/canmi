open Testing

let release = JSON.parseOrThrow(`{"tag_name": "2026.10.22", "draft": false, "assets": [
  {"name": "workerd-1.20261021.1-linux-x86_64.tar", "browser_download_url": "https://x/workerd-1.20261021.1-linux-x86_64.tar"},
  {"name": "workerd-1.20261021.1-linux-aarch64.tar", "browser_download_url": "https://x/workerd-1.20261021.1-linux-aarch64.tar"},
  {"name": "manifest.json", "browser_download_url": "https://x/manifest.json"}
]}`)

let manifest = JSON.parseOrThrow(`{"release": "2026.10.22", "runtimes": [
  {"runtime": "workerd", "version": "1.20261021.1", "assets": [
    {"target": "linux-x86_64", "file": "workerd-1.20261021.1-linux-x86_64.tar", "sha256": "aa"},
    {"target": "linux-aarch64", "file": "workerd-1.20261021.1-linux-aarch64.tar", "sha256": "bb"}
  ]},
  {"runtime": "wasmtime", "version": "50.0.0", "assets": []}
]}`)

describe("a pin", () => {
  test("names each system as Nix does, the machine before the system", () => {
    expect(Releases.system("linux-x86_64"))->toEqual(Some("x86_64-linux"))
    expect(Releases.system("linux-aarch64"))->toEqual(Some("aarch64-linux"))
    expect(Releases.system("x86_64"))->toEqual(None)
  })

  test("moves to the highest version an archive is named by, not the latest uploaded", () => {
    let names = [
      "workerd-1.20261021.1-linux-x86_64.tar",
      "workerd-1.20261022.1-linux-aarch64.tar",
      "workerd-1.20261020.1-linux-x86_64.tar",
      "workerd-1.20261021.1.json",
      "manifest.json",
    ]
    expect(Releases.newest(names, ~name="workerd"))->toEqual(Some("1.20261022.1"))
    expect(Releases.newest(names, ~name="wasmtime"))->toEqual(None)
  })

  test("takes each system's address from the release and its SHA-256 from the manifest", () => {
    let entry = Releases.entryOf(manifest, ~name="workerd", ~version="1.20261021.1")
    expect(entry->Option.isSome)->toBe(true)
    expect(Releases.entryOf(manifest, ~name="workerd", ~version="1.20261020.1"))->toEqual(None)
    expect(Releases.pinned(~version="1.20261021.1", ~release, entry->Option.getOrThrow))->toEqual(
      JSON.parseOrThrow(`{"version": "1.20261021.1", "release": "2026.10.22",
        "x86_64-linux": {"url": "https://x/workerd-1.20261021.1-linux-x86_64.tar", "sha256": "aa"},
        "aarch64-linux": {"url": "https://x/workerd-1.20261021.1-linux-aarch64.tar", "sha256": "bb"}}`),
    )
  })

  test("reads a manifest of the one shape as it reads runtime's first", () => {
    let one = JSON.parseOrThrow(`{"release": "2026.10.23", "artifacts": [
      {"name": "driver-machine", "version": "0.1.0", "assets": [
        {"target": "linux-x86_64", "kind": "binary", "file": "driver-machine-0.1.0-linux-x86_64.tar.gz", "sha256": "cc"}
      ]}
    ]}`)
    expect(Releases.entryOf(one, ~name="driver-machine", ~version="0.1.0")->Option.isSome)->toBe(
      true,
    )
    expect(
      Releases.newest(["driver-machine-0.1.0-linux-x86_64.tar.gz"], ~name="driver-machine"),
    )->toEqual(Some("0.1.0"))
  })

  test("is written as TOML, its head saying who writes it and its release linked above it", () => {
    let pin = JSON.parseOrThrow(`{"version": "50.0.0", "release": "2026.10.22",
      "x86_64-linux": {"url": "https://x/a", "sha256": "aa"},
      "aarch64-linux": {"url": "https://x/b", "sha256": "bb"}}`)
    let text = Releases.written(
      ~source="monoflake/runtime",
      ~manifest="manifest.toml",
      [("wasmtime", pin)],
    )
    expect(
      text,
    )->toBe(`# Written by \`mise run update\` from manifest.toml and monoflake/runtime's releases, the workspace's
# scripts/deps/releases.res; edited by hand, it is written over at the next update.
source = "monoflake/runtime"

# https://github.com/monoflake/runtime/releases/tag/2026.10.22
[wasmtime]
version = "50.0.0"
release = "2026.10.22"

[wasmtime.x86_64-linux]
url = "https://x/a"
sha256 = "aa"

[wasmtime.aarch64-linux]
url = "https://x/b"
sha256 = "bb"
`)
    expect(Toml.parse(text)->JSON.stringify)->toBe(
      JSON.parseOrThrow(`{"source": "monoflake/runtime", "wasmtime": {"version": "50.0.0", "release": "2026.10.22",
        "x86_64-linux": {"url": "https://x/a", "sha256": "aa"},
        "aarch64-linux": {"url": "https://x/b", "sha256": "bb"}}}`)->JSON.stringify,
    )
  })

  test("is locked beside its manifest, the manifest's one list naming what to lock", () => {
    expect(Releases.lockOf("system/containers/manifest.toml"))->toBe(
      "system/containers/manifest.lock",
    )
    expect(Releases.lockOf("pins"))->toBe("pins.lock")
    let manifest = text => Releases.named(Toml.parse(text))
    expect(manifest(`source = "monoflake/runtime"\nimages = ["workerd", "wasmtime"]`))->toEqual(
      Ok(["workerd", "wasmtime"]),
    )
    expect(manifest(`source = "monoflake/driver"\nbinaries = ["driver"]`))->toEqual(Ok(["driver"]))
    expect(manifest(`source = "x"`)->Result.isError)->toBe(true)
    expect(manifest(`source = "x"\na = ["b"]\nc = ["d"]`)->Result.isError)->toBe(true)
  })
})

describe("the driver", () => {
  test("is locked from its own source, one GitHub URL and one hash for each system", () => {
    let release = JSON.parseOrThrow(`{"tag_name":"2026.10.27","assets":[
      {"name":"driver-machine-0.1.0-linux-x86_64.tar.gz","browser_download_url":"https://github.com/monoflake/driver/releases/download/2026.10.27/driver-machine-0.1.0-linux-x86_64.tar.gz"},
      {"name":"driver-machine-0.1.0-linux-aarch64.tar.gz","browser_download_url":"https://github.com/monoflake/driver/releases/download/2026.10.27/driver-machine-0.1.0-linux-aarch64.tar.gz"}
    ]}`)
    let entry = JSON.parseOrThrow(`{"name":"driver-machine","version":"0.1.0","assets":[
      {"target":"linux-x86_64","file":"driver-machine-0.1.0-linux-x86_64.tar.gz","sha256":"aa"},
      {"target":"linux-aarch64","file":"driver-machine-0.1.0-linux-aarch64.tar.gz","sha256":"bb"}
    ]}`)
    let pin = Releases.pinned(~source="monoflake/driver", ~version="0.1.0", ~release, entry)
    expect(pin)->toEqual(
      JSON.parseOrThrow(`{"version": "0.1.0", "source": "monoflake/driver", "release": "2026.10.27",
        "x86_64-linux": {"url": "https://github.com/monoflake/driver/releases/download/2026.10.27/driver-machine-0.1.0-linux-x86_64.tar.gz", "sha256": "aa"},
        "aarch64-linux": {"url": "https://github.com/monoflake/driver/releases/download/2026.10.27/driver-machine-0.1.0-linux-aarch64.tar.gz", "sha256": "bb"}}`),
    )
    let lock = Releases.written(
      ~source="monoflake/runtime",
      ~manifest="manifest.toml",
      [("driver-machine", pin)],
    )
    expect(lock)->toContain(`# https://github.com/monoflake/driver/releases/tag/2026.10.27
[driver-machine]
version = "0.1.0"
release = "2026.10.27"
source = "monoflake/driver"

[driver-machine.x86_64-linux]
url = "https://github.com/monoflake/driver/releases/download/2026.10.27/driver-machine-0.1.0-linux-x86_64.tar.gz"
sha256 = "aa"
`)
    expect(Toml.parse(lock)->Releases.field("driver-machine"))->toEqual(Some(pin))
  })
})

describe("the intake's sources", () => {
  test("are runtime's alone for runtime's one-source manifest", () => {
    let manifest = Toml.parse(`source = "monoflake/runtime"\nimages = ["workerd", "wasmtime"]`)
    expect(Releases.sources(manifest))->toEqual(
      Ok([{Releases.repository: "monoflake/runtime", names: ["workerd", "wasmtime"], own: true}]),
    )
  })

  test("take the driver from the table naming its own source, after runtime's", () => {
    let manifest = Toml.parse(`source = "monoflake/runtime"
images = ["workerd", "wasmtime"]

[driver]
source = "monoflake/driver"
binaries = ["driver-machine"]
`)
    expect(Releases.sources(manifest))->toEqual(
      Ok([
        {Releases.repository: "monoflake/runtime", names: ["workerd", "wasmtime"], own: true},
        {Releases.repository: "monoflake/driver", names: ["driver-machine"], own: false},
      ]),
    )
    expect(
      Releases.sources(Toml.parse(`source = "x"\na = ["b"]\n[t]\nsource = "y"`))->Result.isError,
    )->toBe(true)
  })
})

describe("the dependency updater", () => {
  let root = temporaryRoot("release-update-")
  let script = Node.join([Node.cwd(), "scripts/deps/update.res.mjs"])
  let run = (~driver, ~moves, ~dry=false, ()) => {
    tree(
      root.contents,
      [
        ("mise.toml", ""),
        ("Cargo.toml", "[workspace]"),
        ("Cargo.lock", "old"),
        (
          "bin/cargo",
          `#!/bin/sh
printf '%s\\n' "cargo $*" >> calls
${moves ? "case \"$*\" in *--dry-run*) ;; *) printf new > Cargo.lock ;; esac" : ":"}
`,
        ),
        ("bin/mise", "#!/bin/sh\nprintf '%s\\n' \"mise $*\" >> calls\n"),
      ],
    )
    if driver {
      tree(root.contents, [(".github/release/bump.res", "")])
    }
    Node.run(
      "chmod",
      ["+x", Node.join([root.contents, "bin/cargo"]), Node.join([root.contents, "bin/mise"])],
    )->ignore
    let path = Node.env->Dict.get("PATH")->Option.getOr("")
    Node.env->Dict.set("PATH", Node.join([root.contents, "bin"]) ++ ":" ++ path)
    let result = Node.spawnSync(
      "node",
      [script, ...dry ? ["--dry-run"] : []],
      {cwd: root.contents, encoding: "utf8"},
    )
    Node.env->Dict.set("PATH", path)
    expect(result.status)->toEqual(Nullable.make(0))
    Node.readFileSync(Node.join([root.contents, "calls"]))
  }
  test("bumps the driver after its lock moves", () => {
    expect(run(~driver=true, ~moves=true, ()))->toBe("cargo update\nmise run bump\n")
  })
  test("runs cargo update alone in a cargo repository without bump.res", () => {
    expect(run(~driver=false, ~moves=true, ()))->toBe("cargo update\n")
  })
  test("does not bump an unchanged lock", () => {
    expect(run(~driver=true, ~moves=false, ()))->toBe("cargo update\n")
  })
  test("does not bump or move a lock in a dry run", () => {
    expect(run(~driver=true, ~moves=true, ~dry=true, ()))->toBe("cargo update --dry-run\n")
    expect(Node.readFileSync(Node.join([root.contents, "Cargo.lock"])))->toBe("old")
  })
})

let runtimeLock = `# Written by \`mise run update\` from manifest.toml and monoflake/runtime's releases, the workspace's
# scripts/deps/releases.res; edited by hand, it is written over at the next update.
source = "monoflake/runtime"

# https://github.com/monoflake/runtime/releases/tag/2026.10.26
[workerd]
version = "1.20261025.1"
release = "2026.10.26"

[workerd.x86_64-linux]
url = "https://github.com/monoflake/runtime/releases/download/2026.10.26/workerd-1.20261025.1-linux-x86_64.tar"
sha256 = "c5975d2dc6b69fc93fe7fac6260bb5693499d77922bfcbf45454cf29f57b2982"

[workerd.aarch64-linux]
url = "https://github.com/monoflake/runtime/releases/download/2026.10.26/workerd-1.20261025.1-linux-aarch64.tar"
sha256 = "4a76525b92fddc09bd97483bd28c0d088db52f94c525443b00bb4da8d2cc4463"

# https://github.com/monoflake/runtime/releases/tag/2026.10.22
[wasmtime]
version = "50.0.0"
release = "2026.10.22"

[wasmtime.x86_64-linux]
url = "https://github.com/monoflake/runtime/releases/download/2026.10.22/wasmtime-50.0.0-linux-x86_64.tar"
sha256 = "a63a254940f7edc185db0e2c3608d82bae1fc5240a5b3634b615b0cd643b9c2c"

[wasmtime.aarch64-linux]
url = "https://github.com/monoflake/runtime/releases/download/2026.10.22/wasmtime-50.0.0-linux-aarch64.tar"
sha256 = "51ba585ebd0e50ea4ce501dc0e6717f30edb0404cfbc49cd496174908536d18a"
`

/** A release of `repository` under `tag`, each file an asset, its manifest.json listing
 * `entries`. */
let releaseOf = (repository, tag, files) => {
  let at = file => `https://github.com/${repository}/releases/download/${tag}/${file}`
  JSON.Encode.object(
    dict{
      "tag_name": JSON.Encode.string(tag),
      "draft": JSON.Encode.bool(false),
      "assets": [...files, "manifest.json"]
      ->Array.map(file =>
        JSON.Encode.object(
          dict{
            "name": JSON.Encode.string(file),
            "browser_download_url": JSON.Encode.string(at(file)),
          },
        )
      )
      ->JSON.Encode.array,
    },
  )
}

/** A manifest.json listing each `(name, version, [(target, file, sha256)])`. */
let manifestOf = (tag, entries) =>
  JSON.Encode.object(
    dict{
      "release": JSON.Encode.string(tag),
      "artifacts": entries
      ->Array.map(((name, version, assets)) =>
        JSON.Encode.object(
          dict{
            "name": JSON.Encode.string(name),
            "version": JSON.Encode.string(version),
            "assets": assets
            ->Array.map(((target, file, sha256)) =>
              JSON.Encode.object(
                dict{
                  "target": JSON.Encode.string(target),
                  "file": JSON.Encode.string(file),
                  "sha256": JSON.Encode.string(sha256),
                },
              )
            )
            ->JSON.Encode.array,
          },
        )
      )
      ->JSON.Encode.array,
    },
  )

let listing = repository =>
  `https://api.github.com/repos/${repository}/releases?per_page=100&page=1`
let downloaded = (repository, tag) =>
  `https://github.com/${repository}/releases/download/${tag}/manifest.json`

/** Runtime's two releases as its current lock was written from them. */
let runtimeAnswers = () => {
  let assets = (name, version, x86, arm) => (
    name,
    version,
    [
      ("linux-x86_64", `${name}-${version}-linux-x86_64.tar`, x86),
      ("linux-aarch64", `${name}-${version}-linux-aarch64.tar`, arm),
    ],
  )
  let workerd = assets(
    "workerd",
    "1.20261025.1",
    "c5975d2dc6b69fc93fe7fac6260bb5693499d77922bfcbf45454cf29f57b2982",
    "4a76525b92fddc09bd97483bd28c0d088db52f94c525443b00bb4da8d2cc4463",
  )
  let wasmtime = assets(
    "wasmtime",
    "50.0.0",
    "a63a254940f7edc185db0e2c3608d82bae1fc5240a5b3634b615b0cd643b9c2c",
    "51ba585ebd0e50ea4ce501dc0e6717f30edb0404cfbc49cd496174908536d18a",
  )
  let files = ((_, _, assets)) => assets->Array.map(((_, file, _)) => file)
  let runtime = "monoflake/runtime"
  Dict.fromArray([
    (
      listing(runtime),
      Ok(
        JSON.Encode.array([
          releaseOf(runtime, "2026.10.26", files(workerd)),
          releaseOf(runtime, "2026.10.22", files(wasmtime)),
        ]),
      ),
    ),
    (downloaded(runtime, "2026.10.26"), Ok(manifestOf("2026.10.26", [workerd]))),
    (downloaded(runtime, "2026.10.22"), Ok(manifestOf("2026.10.22", [wasmtime]))),
  ])
}

let fake = (answers: dict<result<JSON.t, string>>) =>
  async url =>
    url->String.includes("&page=") && !(url->String.endsWith("&page=1"))
      ? Ok(JSON.Encode.array([]))
      : answers->Dict.get(url)->Option.getOr(Error(`${url} answered 404`))

let driverPin = `# https://github.com/monoflake/driver/releases/tag/2026.10.27
[driver-machine]
version = "0.1.0"
release = "2026.10.27"
source = "monoflake/driver"

[driver-machine.x86_64-linux]
url = "https://github.com/monoflake/driver/releases/download/2026.10.27/driver-machine-0.1.0-linux-x86_64.tar.gz"
sha256 = "aa"

[driver-machine.aarch64-linux]
url = "https://github.com/monoflake/driver/releases/download/2026.10.27/driver-machine-0.1.0-linux-aarch64.tar.gz"
sha256 = "bb"
`

describe("the intake", () => {
  let root = temporaryRoot("releases-intake-")
  let runtimeManifest = `source = "monoflake/runtime"\nimages = ["workerd", "wasmtime"]\n`
  let both = `${runtimeManifest}\n[driver]\nsource = "monoflake/driver"\nbinaries = ["driver-machine"]\n`
  let at = file => Node.join([root.contents, file])

  testAsync("writes runtime's current lock again byte for byte from its releases", async () => {
    tree(root.contents, [("manifest.toml", runtimeManifest), ("manifest.lock", runtimeLock)])
    let code = await Releases.update(at("manifest.toml"), ~dry=false, ~fetch=fake(runtimeAnswers()))
    expect(code)->toBe(0)
    expect(Node.readFileSync(at("manifest.lock")))->toBe(runtimeLock)
  })

  testAsync("leaves runtime's lock alone and fails where its one source is not read", async () => {
    tree(root.contents, [("manifest.toml", runtimeManifest), ("manifest.lock", "# by hand\n")])
    let code = await Releases.update(at("manifest.toml"), ~dry=false, ~fetch=fake(dict{}))
    expect(code)->toBe(1)
    expect(Node.readFileSync(at("manifest.lock")))->toBe("# by hand\n")
  })

  testAsync(
    "writes the sources it read, keeps a held one's pins as they were, and exits 2 naming it",
    async () => {
      let older = `${runtimeLock}\n${driverPin}`->String.replaceAll("1.20261025.1", "1.20261020.1")
      tree(root.contents, [("manifest.toml", both), ("manifest.lock", older), ("output", "")])
      let answers = runtimeAnswers()
      answers->Dict.set(listing("monoflake/driver"), Error("answered 403"))
      let output = Node.env->Dict.get("GITHUB_OUTPUT")
      Node.env->Dict.set("GITHUB_OUTPUT", at("output"))
      let code = await Releases.update(at("manifest.toml"), ~dry=false, ~fetch=fake(answers))
      switch output {
      | Some(output) => Node.env->Dict.set("GITHUB_OUTPUT", output)
      | None => Node.env->Dict.delete("GITHUB_OUTPUT")
      }
      expect(code)->toBe(2)
      expect(Node.readFileSync(at("output")))->toBe("held=monoflake/driver\n")
      let written = Node.readFileSync(at("manifest.lock"))
      let locked = Toml.parse(written)
      expect(
        locked->Releases.field("workerd")->Option.flatMap(pin => pin->Releases.text("version")),
      )->toEqual(Some("1.20261025.1"))
      expect(locked->Releases.field("driver-machine"))->toEqual(
        Toml.parse(older)->Releases.field("driver-machine"),
      )
      expect(written)->toContain(driverPin)
      expect(written)->toContain(
        "# workspace's scripts/deps/releases.res; edited by hand, it is written over at the next\n# update. Its sources are monoflake/runtime and monoflake/driver.\n",
      )
    },
  )

  testAsync("holds back a source one of whose names could not be read, and exits 2", async () => {
    tree(
      root.contents,
      [("manifest.toml", both), ("manifest.lock", `${runtimeLock}\n${driverPin}`)],
    )
    let answers = runtimeAnswers()
    let driver = "monoflake/driver"
    answers->Dict.set(
      listing(driver),
      Ok(
        JSON.Encode.array([
          releaseOf(driver, "2026.10.28", ["driver-machine-0.1.1-linux-x86_64.tar.gz"]),
        ]),
      ),
    )
    answers->Dict.set(downloaded(driver, "2026.10.28"), Error("answered 502"))
    let code = await Releases.update(at("manifest.toml"), ~dry=false, ~fetch=fake(answers))
    expect(code)->toBe(2)
    expect(Node.readFileSync(at("manifest.lock")))->toContain(driverPin)
  })

  testAsync("writes nothing and exits 1 where no source was read in whole", async () => {
    tree(root.contents, [("manifest.toml", both), ("manifest.lock", "# by hand\n")])
    let code = await Releases.update(at("manifest.toml"), ~dry=false, ~fetch=fake(dict{}))
    expect(code)->toBe(1)
    expect(Node.readFileSync(at("manifest.lock")))->toBe("# by hand\n")
  })

  test("names each source held back on the line it ends with, as the dispatcher reads it", () => {
    let line = Releases.heldLine("manifest.toml", ["monoflake/driver", "monoflake/other"])
    expect(Releases.heldIn(`releases: a -> b\n${line}\n`))->toEqual([
      "monoflake/driver",
      "monoflake/other",
    ])
    expect(Releases.heldIn("releases: manifest.toml workerd 1 -> 2\n"))->toEqual([])
  })

  testAsync("leaves out a name never locked whose resolve fails, and fails", async () => {
    let manifest = `source = "monoflake/runtime"\nimages = ["workerd", "wasmtime", "fresh"]\n`
    tree(root.contents, [("manifest.toml", manifest), ("manifest.lock", runtimeLock)])
    let answers = runtimeAnswers()
    let runtime = "monoflake/runtime"
    let listed =
      answers
      ->Dict.get(listing(runtime))
      ->Option.flatMap(answer => answer->Result.mapOr(None, listed => Some(listed)))
      ->Option.flatMap(JSON.Decode.array)
      ->Option.getOr([])
    answers->Dict.set(
      listing(runtime),
      Ok(
        JSON.Encode.array(
          [releaseOf(runtime, "2026.10.27", ["fresh-1.0.0-linux-x86_64.tar"]), ...listed],
        ),
      ),
    )
    answers->Dict.set(downloaded(runtime, "2026.10.27"), Error("answered 502"))
    let code = await Releases.update(at("manifest.toml"), ~dry=false, ~fetch=fake(answers))
    expect(code)->toBe(1)
    expect(Node.readFileSync(at("manifest.lock")))->toBe(runtimeLock)
  })

  testAsync("leaves out a name never locked that nothing has released yet", async () => {
    tree(root.contents, [("manifest.toml", both), ("manifest.lock", runtimeLock)])
    let answers = runtimeAnswers()
    answers->Dict.set(listing("monoflake/driver"), Ok(JSON.Encode.array([])))
    let code = await Releases.update(at("manifest.toml"), ~dry=false, ~fetch=fake(answers))
    expect(code)->toBe(0)
    expect(
      Toml.parse(Node.readFileSync(at("manifest.lock")))->Releases.field("driver-machine"),
    )->toEqual(None)
  })
})
