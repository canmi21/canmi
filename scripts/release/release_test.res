open Testing

let old = JSON.parseOrThrow(`{"release": "2026.10.22", "runtimes": [
  {"runtime": "workerd", "version": "1.20261021.1", "commit": "c1",
    "upstream": {"repository": "cloudflare/workerd", "tag": "v1.20261021.1", "commit": "u1"},
    "assets": [{"target": "linux-x86_64", "kind": "oci", "file": "workerd-1.20261021.1-linux-x86_64.tar", "size": 3, "sha256": "aa", "digest": "sha256:aa"}]}
]}`)

let driver = JSON.parseOrThrow(`{"name": "driver-machine", "version": "0.1.0", "commit": "c2",
  "interfaces": {"management": 2, "deployments": 2},
  "assets": [{"target": "linux-x86_64", "kind": "binary", "path": "target/archives/driver-machine-0.1.0-linux-x86_64.tar.gz"}],
  "row": ["driver-machine", "0.1.0", "c2", "[x](https://x/releases/download/{release}/a)"]}`)

let columns = ["Program", "Version", "Commit", "Download"]

describe("a release", () => {
  test("is named by the UTC day, each part padded so its name sorts by date", () => {
    expect(Manifest.day(Date.fromString("2026-09-05T23:59:00Z")->Date.getTime))->toBe("2026.09.05")
    expect(Manifest.day(Date.fromString("2026-10-22T00:00:00Z")->Date.getTime))->toBe("2026.10.22")
  })

  test("reads runtime's first manifest as the one shape, its runtime taken as the name", () => {
    let read = Manifest.artifacts(old)
    expect(read->Array.map(entry => entry->Manifest.text("name")))->toEqual([Some("workerd")])
    expect(read->Array.getUnsafe(0)->Manifest.field("runtime"))->toEqual(None)
    expect(Manifest.lists(old, ~name="workerd", ~version="1.20261021.1"))->toBe(true)
    expect(Manifest.lists(old, ~name="workerd", ~version="1.20261022.1"))->toBe(false)
  })

  test("lists an artifact by its name, version, commit and assets, then its own fields", () => {
    let measured: Manifest.measured = {
      target: "linux-x86_64",
      kind: "binary",
      file: "driver-machine-0.1.0-linux-x86_64.tar.gz",
      size: 5.,
      sha256: "cc",
    }
    let entry = Manifest.entry(driver, [(measured, None)])
    expect(entry->JSON.Decode.object->Option.getOrThrow->Dict.keysToArray)->toEqual([
      "name",
      "version",
      "commit",
      "assets",
      "interfaces",
    ])
    expect(entry->Manifest.list("assets"))->toEqual([
      JSON.parseOrThrow(`{"target": "linux-x86_64", "kind": "binary",
        "file": "driver-machine-0.1.0-linux-x86_64.tar.gz", "size": 5, "sha256": "cc"}`),
    ])
  })

  test(
    "merges a later run's artifacts into one manifest of the one shape, its own replaced",
    () => {
      let entry = JSON.parseOrThrow(`{"name": "wasmtime", "version": "50.0.0", "assets": []}`)
      let once = Manifest.merged(Some(old), ~release="2026.10.22", [entry])->JSON.parseOrThrow
      expect(once->Manifest.field("runtimes"))->toEqual(None)
      expect(once->Manifest.list("artifacts")->Array.map(e => e->Manifest.text("name")))->toEqual([
        Some("workerd"),
        Some("wasmtime"),
      ])
      let twice = Manifest.merged(Some(once), ~release="2026.10.22", [entry])->JSON.parseOrThrow
      expect(twice->Manifest.list("artifacts")->Array.length)->toBe(2)
    },
  )

  test("counts only a published release carrying the version's files", () => {
    let release = (draft, file) =>
      JSON.parseOrThrow(`{"draft": ${draft ? "true" : "false"}, "assets": [{"name": "${file}"}]}`)
    let file = "driver-machine-0.1.0-linux-x86_64.tar.gz"
    expect(Manifest.holds(release(false, file), ~name="driver-machine", ~version="0.1.0"))->toBe(
      true,
    )
    expect(Manifest.holds(release(true, file), ~name="driver-machine", ~version="0.1.0"))->toBe(
      false,
    )
    expect(Manifest.holds(release(false, file), ~name="driver-machine", ~version="0.1"))->toBe(
      false,
    )
  })

  test("keeps its notes a table of the declared columns, each row added once", () => {
    let head = Manifest.header(columns)->Array.join("\n")
    expect(head)->toBe("| Program | Version | Commit | Download |\n| --- | --- | --- | --- |")
    expect(Manifest.appended("", ~columns, "| a |"))->toBe(`${head}\n| a |`)
    expect(Manifest.appended(`${head}\n| a |\n`, ~columns, "| a |"))->toBe(`${head}\n| a |`)
    expect(Manifest.filled("download/{release}/a", ~release="2026.10.22"))->toBe(
      "download/2026.10.22/a",
    )
  })

  test("refuses an artifact missing a field, a cell or its name in a file", () => {
    expect(Manifest.refused(driver, ~columns))->toEqual(None)
    expect(Manifest.refused(driver, ~columns=["Program"])->Option.isSome)->toBe(true)
    let renamed =
      driver
      ->JSON.stringify
      ->String.replace("target/archives/driver-machine-0.1.0", "target/archives/other-0.1.0")
      ->JSON.parseOrThrow
    expect(Manifest.refused(renamed, ~columns)->Option.isSome)->toBe(true)
  })
})

/** The release as GitHub holds it, its notes, its manifest and its files' names. */
type held = {mutable body: string, mutable manifest: string, mutable files: array<string>}

/** A gh that logs each call, fails the one step FAIL names, and keeps the manifest it uploads. */
let gh = `#!/usr/bin/env node
const fs = require("node:fs"), path = require("node:path");
const args = process.argv.slice(2);
const sent = args.find(arg => path.basename(arg) === "manifest.json");
const step = args[1] === "edit" ? "notes" : sent && args[1] === "upload" ? "manifest" : "files";
fs.appendFileSync(path.join(__dirname, "calls"), JSON.stringify(args) + "\\n");
if (process.env.FAIL === step) process.exit(1);
if (step === "manifest") fs.copyFileSync(sent, path.join(__dirname, "uploaded"));
`

describe("a day's release", () => {
  let root = temporaryRoot("release-day-")
  let tag = Manifest.day(Date.now())
  let columns = ["Driver", "Version", "Commit", "Architecture"]
  let head = Manifest.header(columns)->Array.join("\n")
  let named = ["--repo", "monoflake/driver"]
  let file = name => Node.join([root.contents, name])
  let archive = () => file("driver-machine-0.1.0-linux-x86_64.tar.gz")
  let manifest = () => file("manifest.json")
  let artifact = commit =>
    JSON.Encode.object(
      dict{
        "name": JSON.Encode.string("driver-machine"),
        "version": JSON.Encode.string("0.1.0"),
        "commit": JSON.Encode.string(commit),
        "assets": JSON.Encode.array([
          JSON.Encode.object(
            dict{
              "target": JSON.Encode.string("linux-x86_64"),
              "kind": JSON.Encode.string("binary"),
              "path": JSON.Encode.string(archive()),
            },
          ),
        ]),
        "row": ["machine", "0.1.0", commit, "[x86_64](https://x/releases/download/{release}/a)"]
        ->Array.map(JSON.Encode.string)
        ->JSON.Encode.array,
      },
    )
  let row = commit =>
    `| machine | 0.1.0 | ${commit} | [x86_64](https://x/releases/download/${tag}/a) |`
  // A day's release made before entries carried their rows, its one row in its notes alone.
  let workerdRow = "| workerd | 1.20261021.1 | c0 | [x86_64](https://x/a) |"
  let workerd = JSON.parseOrThrow(
    `{"release": "${tag}", "artifacts": [{"name": "workerd",
    "version": "1.20261021.1", "commit": "c0", "assets": []}]}`,
  )
  let calls = () =>
    Node.readFileSync(Node.join([root.contents, "bin", "calls"]))
    ->String.split("\n")
    ->Array.filter(line => line != "")
    ->Array.map(line =>
      JSON.parseOrThrow(line)
      ->JSON.Decode.array
      ->Option.getOr([])
      ->Array.filterMap(JSON.Decode.string)
    )
  // What `body` runs with the fake gh first on the path, a server answering with `served`.
  let faked = async (~served=() => "{}", body) => {
    tree(
      root.contents,
      [
        ("bin/gh", gh),
        ("bin/calls", ""),
        ("driver-machine-0.1.0-linux-x86_64.tar.gz", "archive"),
        ("workerd-1.20261022.1-linux-x86_64.tar", "image"),
      ],
    )
    Node.run("chmod", ["+x", Node.join([root.contents, "bin/gh"])])->ignore
    let server = Testing.createServer((_, response) =>
      response
      ->Testing.writeHead(200, dict{"content-type": "application/json"})
      ->Testing.endResponse(served())
    )
    await Promise.make((resolve, _) => server->Testing.listen(0, () => resolve()))
    let address = `http://localhost:${(
        server->Testing.serverAddress
      ).port->Int.toString}/manifest.json`
    let path = Node.env->Dict.get("PATH")->Option.getOr("")
    Node.env->Dict.set("PATH", Node.join([root.contents, "bin"]) ++ ":" ++ path)
    let result = await body(address)
    Node.env->Dict.set("PATH", path)
    await Promise.make((resolve, _) => server->Testing.close(() => resolve()))
    result
  }
  let standing = (~address, ~body, ~files) =>
    JSON.Encode.object(
      dict{
        "tag_name": JSON.Encode.string(tag),
        "draft": JSON.Encode.bool(false),
        "body": JSON.Encode.string(body),
        "assets": [...files, "manifest.json"]
        ->Array.map(name =>
          JSON.Encode.object(
            dict{
              "name": JSON.Encode.string(name),
              "browser_download_url": JSON.Encode.string(address),
            },
          )
        )
        ->JSON.Encode.array,
      },
    )

  testAsync(
    "rows each artifact once, whichever step a run before failed at, and repairs its notes",
    async () => {
      let state = {body: "", manifest: "", files: []}
      await faked(
        ~served=() => state.manifest,
        async address => {
          // One run as main makes it, GitHub keeping what each call that passed sent.
          let attempt = async (commit, ~failing) => {
            Node.writeFileSync(Node.join([root.contents, "bin", "calls"]), "")
            failing->Option.forEach(step => Node.env->Dict.set("FAIL", step))
            ignore(
              await Release.releasing(
                [artifact(commit)],
                ~releases=[standing(~address, ~body=state.body, ~files=state.files)],
                ~repository="monoflake/driver",
                ~columns,
                ~directory=root.contents,
              ),
            )
            Node.env->Dict.delete("FAIL")
            calls()->Array.forEach(
              args =>
                switch (args[1], args[3], args[4]) {
                | (Some("edit"), Some("--notes"), Some(notes)) if failing != Some("notes") =>
                  state.body = notes
                | (Some("upload"), _, _)
                  if !(args->Array.includes(manifest())) && failing != Some("files") =>
                  state.files = [...state.files, Node.basename(archive())]
                | _ => ()
                },
            )
            let uploaded = Node.join([root.contents, "bin", "uploaded"])
            if Node.existsSync(uploaded) {
              state.manifest = Node.readFileSync(uploaded)
              Node.rmSync(uploaded, {recursive: false, force: true})
            }
          }
          let failures = ["files", "manifest", "notes"]
          for index in 0 to failures->Array.length - 1 {
            let failed = failures->Array.getUnsafe(index)
            state.body = `${head}\n${workerdRow}`
            state.manifest = workerd->JSON.stringify
            state.files = []
            await attempt("c1", ~failing=Some(failed))
            await attempt("c2", ~failing=None)
            await attempt("c3", ~failing=None)
            let rows =
              state.body
              ->String.split("\n")
              ->Array.filter(line => line->String.startsWith("| machine | 0.1.0 |"))
            let listed =
              JSON.parseOrThrow(state.manifest)
              ->Manifest.artifacts
              ->Array.filter(entry => entry->Manifest.text("name") == Some("driver-machine"))
            expectAs(rows->Array.length, `rows after a failed ${failed} step`)->toBe(1)
            expectAs(listed->Array.length, `entries after a failed ${failed} step`)->toBe(1)
            expectAs(state.body, `notes after a failed ${failed} step`)->toBe(
              `${head}\n${workerdRow}\n${rows->Array.getUnsafe(0)}`,
            )
          }
        },
      )
    },
  )

  testAsync("renders notes a failed edit left short again on a run with nothing new", async () => {
    let state = {body: "", manifest: "", files: []}
    await faked(
      ~served=() => state.manifest,
      async address => {
        state.body = `${head}\n${workerdRow}`
        state.manifest = workerd->JSON.stringify
        Node.env->Dict.set("FAIL", "notes")
        let first = await Release.releasing(
          [artifact("c1")],
          ~releases=[standing(~address, ~body=state.body, ~files=[])],
          ~repository="monoflake/driver",
          ~columns,
          ~directory=root.contents,
        )
        Node.env->Dict.delete("FAIL")
        expect(first->Result.isError)->toBe(true)
        state.manifest = Node.readFileSync(Node.join([root.contents, "bin", "uploaded"]))
        Node.writeFileSync(Node.join([root.contents, "bin", "calls"]), "")
        let again = await Release.releasing(
          [artifact("c1")],
          ~releases=[standing(~address, ~body=state.body, ~files=[Node.basename(archive())])],
          ~repository="monoflake/driver",
          ~columns,
          ~directory=root.contents,
        )
        expect(again)->toEqual(Ok())
        expect(calls())->toEqual([
          ["release", "edit", tag, "--notes", `${head}\n${workerdRow}\n${row("c1")}`, ...named],
        ])
      },
    )
  })

  testAsync(
    "replaces an entry of the same version whole, its sha256 and commit the files'",
    async () => {
      let older = JSON.parseOrThrow(
        `{"release": "${tag}", "artifacts": [{"name": "driver-machine",
      "version": "0.1.0", "commit": "c1", "assets": [{"target": "linux-x86_64", "kind": "binary",
      "file": "driver-machine-0.1.0-linux-x86_64.tar.gz", "size": 1, "sha256": "old"}],
      "row": ["machine", "0.1.0", "c1", "a"]}]}`,
      )
      await faked(
        ~served=() => older->JSON.stringify,
        async address => {
          let done = await Release.release(
            [artifact("c2")],
            ~releases=[
              standing(~address, ~body=`${head}\n| machine | 0.1.0 | c1 | a |`, ~files=[]),
            ],
            ~repository="monoflake/driver",
            ~columns,
            ~directory=root.contents,
          )
          expect(done)->toEqual(Ok())
          let entries = JSON.parseOrThrow(Node.readFileSync(manifest()))->Manifest.artifacts
          expect(entries->Array.map(entry => entry->Manifest.text("commit")))->toEqual([Some("c2")])
          expect(
            entries
            ->Array.flatMap(entry => entry->Manifest.list("assets"))
            ->Array.map(asset => asset->Manifest.text("sha256")),
          )->toEqual([
            Some(
              Net.createHash("sha256")->Net.updateBytes(Node.readBytes(archive()))->Net.hexDigest,
            ),
          ])
          let notes = calls()->Array.at(-1)->Option.flatMap(args => args[4])
          expect(notes)->toEqual(Some(`${head}\n${row("c2")}`))
        },
      )
    },
  )

  testAsync("makes a new day's release as before, drafted whole and then published", async () => {
    await faked(
      async _ => {
        let done = await Release.release(
          [artifact("c1")],
          ~releases=[],
          ~repository="monoflake/driver",
          ~columns,
          ~directory=root.contents,
        )
        expect(done)->toEqual(Ok())
        let notes = `${head}\n${row("c1")}`
        expect(calls())->toEqual([
          [
            "release",
            "create",
            tag,
            "--draft",
            "--title",
            tag,
            "--notes",
            notes,
            archive(),
            manifest(),
            ...named,
          ],
          ["release", "edit", tag, "--draft=false", ...named],
        ])
      },
    )
  })

  testAsync("takes runtime's image, its kind, digest and upstream, by either path", async () => {
    let columns = ["Runtime", "Version", "Commit", "Architecture"]
    let head = Manifest.header(columns)->Array.join("\n")
    let image = file("workerd-1.20261022.1-linux-x86_64.tar")
    let runtime = JSON.Encode.object(
      dict{
        "name": JSON.Encode.string("workerd"),
        "version": JSON.Encode.string("1.20261022.1"),
        "commit": JSON.Encode.string("c9"),
        "upstream": JSON.parseOrThrow(`{"repository": "cloudflare/workerd", "tag": "v1.20261022.1", "commit": "u9"}`),
        "assets": JSON.Encode.array([
          JSON.Encode.object(
            dict{
              "target": JSON.Encode.string("linux-x86_64"),
              "kind": JSON.Encode.string("oci"),
              "path": JSON.Encode.string(image),
              "digest": JSON.Encode.string("sha256:dd"),
            },
          ),
        ]),
        "row": [
          "workerd",
          "1.20261022.1",
          "c9",
          "[x86_64](https://x/releases/download/{release}/w)",
        ]
        ->Array.map(JSON.Encode.string)
        ->JSON.Encode.array,
      },
    )
    let line = `| workerd | 1.20261022.1 | c9 | [x86_64](https://x/releases/download/${tag}/w) |`
    let wasmtime = "| wasmtime | 50.0.0 | c8 | [x86_64](https://x/v) |"
    let old = JSON.parseOrThrow(
      `{"release": "${tag}", "runtimes": [{"runtime": "wasmtime",
      "version": "50.0.0", "commit": "c8", "assets": []}]}`,
    )
    await faked(
      ~served=() => old->JSON.stringify,
      async address => {
        let repo = ["--repo", "monoflake/runtime"]
        let fresh = await Release.release(
          [runtime],
          ~releases=[],
          ~repository="monoflake/runtime",
          ~columns,
          ~directory=root.contents,
        )
        expect(fresh)->toEqual(Ok())
        let written = JSON.parseOrThrow(Node.readFileSync(manifest()))->Manifest.artifacts
        expect(
          written->Array.map(
            entry => entry->JSON.Decode.object->Option.getOrThrow->Dict.keysToArray,
          ),
        )->toEqual([["name", "version", "commit", "assets", "upstream", "row"]])
        expect(
          written
          ->Array.flatMap(entry => entry->Manifest.list("assets"))
          ->Array.map(asset => (asset->Manifest.text("kind"), asset->Manifest.text("digest"))),
        )->toEqual([(Some("oci"), Some("sha256:dd"))])
        expect(calls())->toEqual([
          [
            "release",
            "create",
            tag,
            "--draft",
            "--title",
            tag,
            "--notes",
            `${head}\n${line}`,
            image,
            manifest(),
            ...repo,
          ],
          ["release", "edit", tag, "--draft=false", ...repo],
        ])
        Node.writeFileSync(Node.join([root.contents, "bin", "calls"]), "")
        let added = await Release.release(
          [runtime],
          ~releases=[standing(~address, ~body=`${head}\n${wasmtime}`, ~files=[])],
          ~repository="monoflake/runtime",
          ~columns,
          ~directory=root.contents,
        )
        expect(added)->toEqual(Ok())
        let merged = JSON.parseOrThrow(Node.readFileSync(manifest()))
        expect(merged->Manifest.field("runtimes"))->toEqual(None)
        expect(
          merged->Manifest.artifacts->Array.map(entry => entry->Manifest.text("name")),
        )->toEqual([Some("wasmtime"), Some("workerd")])
        expect(calls())->toEqual([
          ["release", "upload", tag, image, "--clobber", ...repo],
          ["release", "upload", tag, manifest(), "--clobber", ...repo],
          ["release", "edit", tag, "--notes", `${head}\n${wasmtime}\n${line}`, ...repo],
        ])
      },
    )
  })
})
