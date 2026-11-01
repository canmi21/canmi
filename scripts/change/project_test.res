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
