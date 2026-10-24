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
    expect(declared("[push]\nvisibility = \"public\"\nci = true\n")->Result.isError)->toBe(true)
  })
})
