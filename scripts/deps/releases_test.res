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
