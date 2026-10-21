open Testing

// Two documents as pnpm writes them, its own config's importer first and then the repository's.
let lock = `lockfileVersion: '9.0'

importers:

  .:
    configDependencies: {}
---
lockfileVersion: '9.0'

importers:

  .:
    devDependencies:
      vitest:
        specifier: ^5.0.3
        version: 5.0.3

  apps/compute/executor:
    dependencies:
      '@monoflake/replay':
        specifier: workspace:*
        version: link:../../../libs/replay

  libs/empty: {}

  'libs/odd name':
    dependencies:
      hono:
        specifier: ^4.0.0
        version: 4.13.12

packages:

  hono@4.13.12:
    resolution: {integrity: sha512-x}
`

let executor = /\n {2}apps\/compute\/executor:\n(?: {4}.*\n)+/

describe("the importers", () => {
  test("are each directory, every document of it together, and nothing past them", () => {
    let found = Lockfile.importers(lock)
    expect(found->Graph.keysOf)->toEqual([
      ".",
      "apps/compute/executor",
      "libs/empty",
      "libs/odd name",
    ])
    expect(found->Map.get("libs/empty"))->toEqual(Some("{}"))
    expect(found->Map.get(".")->Option.getOr(""))->toContain("configDependencies")
    expect(found->Map.get(".")->Option.getOr(""))->toContain("vitest")
    expect(found->Map.get("libs/odd name")->Option.getOr(""))->negated->toContain("resolution")
  })

  test("moved are those whose section differs, and one that comes or goes", () => {
    let bumped =
      lock->String.replace("version: 4.13.12\n\npackages", "version: 4.13.13\n\npackages")
    expect(Lockfile.movedImporters(lock, bumped))->toEqual(Set.fromArray(["libs/odd name"]))
    // What the packages section resolves to is not an importer's.
    expect(Lockfile.movedImporters(lock, lock->String.replace("sha512-x", "sha512-y")))->toEqual(
      Set.make(),
    )
    let gone = lock->String.replaceRegExp(executor, "\n")
    expect(Lockfile.movedImporters(lock, gone))->toEqual(Set.fromArray(["apps/compute/executor"]))
  })
})
