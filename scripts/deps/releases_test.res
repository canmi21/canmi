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
      JSON.parseOrThrow(`{"version": "1.20261021.1",
        "x86_64-linux": {"url": "https://x/workerd-1.20261021.1-linux-x86_64.tar", "sha256": "aa"},
        "aarch64-linux": {"url": "https://x/workerd-1.20261021.1-linux-aarch64.tar", "sha256": "bb"}}`),
    )
  })
})
