open Testing

let root = temporaryRoot("project-")

let declared = toml => {
  tree(root.contents, [("workspace.toml", toml)])
  Project.visibilityAt(root.contents)
}

describe("a repository's [push]", () => {
  test("no workspace.toml is public", () => {
    expect(Project.visibilityAt(root.contents))->toEqual(Ok("public"))
  })

  test("a workspace.toml declaring no [push] is public", () => {
    expect(declared("[rules]\nlines = true\n"))->toEqual(Ok("public"))
  })

  test("a declared visibility is read", () => {
    expect(declared("[push]\nvisibility = \"private\"\n"))->toEqual(Ok("private"))
  })

  test("a visibility outside the model's is refused", () => {
    expect(declared("[push]\nvisibility = \"internal\"\n")->Result.isError)->toBe(true)
  })

  test("a key push does not read is refused", () => {
    expect(declared("[push]\nvisibility = \"public\"\ndeploy = true\n")->Result.isError)->toBe(true)
  })

  test("the workflows a push starts and releases with are read", () => {
    let toml = "[push]\nvisibility = \"public\"\nci = [\"verify.yml\"]\nrelease = [\"publish.yml\"]\n"
    tree(root.contents, [("workspace.toml", toml)])
    let push = Project.read(root.contents)->Result.map(declared => declared.push)
    expect(push->Result.map(push => (push.stated, push.ci, push.release)))->toEqual(
      Ok((true, Some(["verify.yml"]), ["publish.yml"])),
    )
  })

  test("a ci that is not a list of file names is refused", () => {
    expect(declared("[push]\nci = true\n")->Result.isError)->toBe(true)
  })
})

describe("a repository's [boundary]", () => {
  let boundary = toml => {
    tree(root.contents, [("workspace.toml", toml)])
    Project.read(root.contents)->Result.map(declared => declared.boundary)
  }

  test("declares none by default", () => {
    expect(boundary("[rules]\nlines = true\n"))->toEqual(Ok({exports: [], depends: []}))
  })

  test("reads what it exports and what it depends on", () => {
    let toml = "[boundary]\nexports = [\"contracts\"]\ndepends = [\"monoflake/platform:contracts\"]\n"
    expect(boundary(toml))->toEqual(
      Ok({exports: ["contracts"], depends: ["monoflake/platform:contracts"]}),
    )
  })

  test("refuses an item-like name, a bare dependency and an unknown key", () => {
    expect(boundary("[boundary]\nexports = [\"Some Item\"]\n")->Result.isError)->toBe(true)
    expect(boundary("[boundary]\ndepends = [\"contracts\"]\n")->Result.isError)->toBe(true)
    expect(boundary("[boundary]\nneeds = []\n")->Result.isError)->toBe(true)
  })
})
