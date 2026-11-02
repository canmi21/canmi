open Testing

describe("a repository's verb tasks", () => {
  let root = temporaryRoot("verbs-")
  let found = files => {
    tree(root.contents, files)
    Verbs.found(~root=root.contents, ~label="x")
  }

  test("passes a task declaring --dry-run in its usage", () => {
    let toml = "[tasks.fmt]\nusage = 'flag \"-n --dry-run\" help=\"x\"'\nrun = \"true\"\n"
    expect(found([("mise.toml", toml)]))->toEqual([])
  })

  test("names a verb task that declares none, and a verify that need not", () => {
    let toml = "[tasks.clean]\nrun = \"true\"\n[tasks.verify]\nrun = \"true\"\n"
    expect(found([("mise.toml", toml)]))->toEqual(["x: the task clean takes no --dry-run flag"])
  })

  test("reads a file task's header", () => {
    expect(
      found([(".mise/tasks/update", "#!/bin/sh\n#USAGE flag \"-n --dry-run\"\n")]),
    )->toEqual([])
    expect(found([(".mise/tasks/update", "#!/bin/sh\necho flag --dry-run\n")]))->toEqual([
      "x: the task update takes no --dry-run flag",
    ])
  })
})
