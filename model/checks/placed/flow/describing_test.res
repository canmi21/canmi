open Testing

let listing = "Usage: tool [OPTIONS] [COMMAND]\n\nCommands:\n  commit    Update\n  log       Show\n  new       Create\n\nOptions:\n  -h, --help\n"

describe("the subcommands that take -m", () => {
  test("reads the commands under the heading", () => {
    expect(Describing.commands(listing))->toEqual(["commit", "log", "new"])
  })

  test("tells an option -m from one that only mentions it", () => {
    expect(Describing.takesMessage("Options:\n  -m, --message <MESSAGE>\n"))->toBe(true)
    expect(Describing.takesMessage("Options:\n      --no-edit  Skip the -m prompt\n"))->toBe(false)
  })

  test("names a command missing from the list and a name that is none", () => {
    expect(Describing.problems(~takes=["commit", "revert"], ~unknown=["gone"]))->toEqual([
      "revert takes -m, and Commits.describing does not list it",
      "Commits.describing lists gone, which is no subcommand",
    ])
    expect(Describing.problems(~takes=["commit"], ~unknown=[]))->toEqual([])
  })
})
