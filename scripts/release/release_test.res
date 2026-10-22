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
