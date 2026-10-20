open Testing

let root = temporaryRoot("names-")
let layout = (): Graph.layout => {
  root: root.contents,
  packageDirectories: [],
  appRoots: ["apps/control", "apps/data"],
}

describe("an app", () => {
  test("named as its directory passes, and a directory with no declaration is not an app", () => {
    tree(
      root.contents,
      [
        ("apps/control/registry/service.toml", "version = 1\nname = \"registry\"\n"),
        ("apps/data/store/README.md", ""),
      ],
    )
    expect(Names.misnamed(layout()))->toEqual([])
  })

  test("named otherwise, or not named at all, is refused by its path", () => {
    tree(
      root.contents,
      [
        ("apps/control/deployer/service.toml", "name = \"deploy\"\n"),
        ("apps/data/store/service.toml", "version = 1\n"),
      ],
    )
    expect(Names.misnamed(layout()))->toEqual([
      "apps/control/deployer/service.toml: name is \"deploy\", its directory deployer",
      "apps/data/store/service.toml: name is undefined, its directory store",
    ])
  })

  test("whose declaration does not parse is refused too", () => {
    tree(root.contents, [("apps/data/store/service.toml", "name = \n")])
    expect(Names.misnamed(layout())[0]->Option.getOr(""))->toMatch(
      /^apps\/data\/store\/service.toml: does not parse/,
    )
  })
})
