@module("vitest") external test: (string, unit => promise<unit>) => unit = "test"
@module("node:assert/strict") external equal: ('a, 'a) => unit = "deepStrictEqual"

let release = (name, version) =>
  JSON.parseOrThrow(
    `{"tag_name":"new","assets":[
		{"name":"${name}-${version}-linux-x86_64.tar","browser_download_url":"https://example.com/${name}.tar"},
		{"name":"manifest.json","browser_download_url":"https://example.com/${name}.json"}
	]}`,
  )

let manifest = (name, version) =>
  JSON.parseOrThrow(
    `{"artifacts":[{"name":"${name}","version":"${version}","assets":[
		{"target":"linux-x86_64","file":"${name}-${version}-linux-x86_64.tar","sha256":"new"}
	]}]}`,
  )

test("a held source keeps every name and emits no proposed moves in either order", async () => {
  let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "held-source-"]))
  let file = Node.join([root, "manifest.toml"])
  let lock = Releases.lockOf(file)
  let locked = Toml.parse(`source = "owner/held"
[alpha]
version = "1.0.0"
release = "old"
[beta]
version = "2.0.0"
release = "old"
[broken]
version = "1.0.0"
release = "old"
[healthy]
version = "1.0.0"
release = "old"
source = "owner/healthy"
`)
  let fetch = async url =>
    if url->String.endsWith("&page=2") {
      Ok(JSON.Encode.array([]))
    } else if url->String.includes("/owner/held/releases?") {
      Ok(
        ["alpha", "beta", "broken", "fresh"]
        ->Array.map(name => release(name, "2.0.0"))
        ->JSON.Encode.array,
      )
    } else if url->String.includes("/owner/healthy/releases?") {
      Ok(JSON.Encode.array([release("healthy", "2.0.0")]))
    } else if url == "https://example.com/broken.json" {
      Error("answered 502")
    } else {
      let name = url->String.split("/")->Array.at(-1)->Option.getOrThrow
      Ok(manifest(name->String.replace(".json", ""), "2.0.0"))
    }
  for order in 0 to 1 {
    let names =
      order == 0 ? ["alpha", "beta", "broken", "fresh"] : ["fresh", "broken", "beta", "alpha"]
    Node.writeFileSync(
      file,
      `source = "owner/held"\nimages = ${names->JSON.stringifyAny->Option.getOrThrow}
[other]
source = "owner/healthy"
images = ["healthy"]
`,
    )
    Node.writeFileSync(
      lock,
      Releases.written(
        ~source="owner/held",
        ~manifest="manifest.toml",
        ["alpha", "beta", "broken", "healthy"]->Array.map(name => (
          name,
          locked->Releases.field(name)->Option.getOrThrow,
        )),
      ),
    )
    let before = Releases.items->Array.length
    let code = await Releases.update(file, ~dry=false, ~fetch)
    equal(code, Releases.partly)
    let written = Node.readFileSync(lock)->Toml.parse
    // A partial write used to keep only the failed name and move its siblings.
    ["alpha", "beta", "broken"]->Array.forEach(name =>
      equal(written->Releases.field(name), locked->Releases.field(name))
    )
    equal(written->Releases.field("fresh"), None)
    equal(
      written->Releases.field("healthy")->Option.flatMap(pin => pin->Releases.text("version")),
      Some("2.0.0"),
    )
    equal(Releases.items->Array.slice(~start=before)->Array.length, 1)
  }
  equal(Node.run("trash", [root]), 0)
})
