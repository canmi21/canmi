open Testing

let payload = (cwd, command): Payload.t =>
  Dict.fromArray([
    ("cwd", JSON.String(cwd)),
    ("tool_input", JSON.Object(Dict.fromArray([("command", JSON.String(command))]))),
  ])

describe("a jj command line", () => {
  test("names the gates its own assignments skip, comma-separated", () => {
    expect(Jj_command.skipped("SKIP=verify,other jj commit -m x"))->toEqual(["verify", "other"])
    expect(Jj_command.skipped("env SKIP=verify jj commit"))->toEqual(["verify"])
    expect(Jj_command.skipped("SKIP=verify echo && jj commit"))->toEqual([])
  })

  test("names the repository -R gives before its subcommand", () => {
    expect(Jj_command.repository("jj -R repos/seam commit -m x"))->toEqual(Some("repos/seam"))
    expect(Jj_command.repository("jj --repository=a log"))->toEqual(Some("a"))
    expect(Jj_command.repository("jj commit -m x"))->toEqual(None)
  })
})

describe("the verify gate", () => {
  let root = temporaryRoot("verified-")
  test(
    "refuses a commit until verify passed at this working copy, and SKIP names the escape",
    () => {
      let repo = root.contents
      Node.run(~cwd=repo, "jj", ["git", "init", "--quiet"])->ignore
      tree(repo, [("a.md", "one\n")])
      let commit = "jj commit -m 'chore: a'"
      expect(Verified.handle(payload(repo, commit)))->toBe(2)
      expect(Verified.handle(payload(repo, "jj describe -m 'chore: a'")))->toBe(0)
      expect(Verified.handle(payload(repo, `SKIP=verify ${commit}`)))->toBe(0)
      let at = Node.realpathSync(repo)
      Stamp.write(at, Stamp.snapshot(at))
      expect(Verified.handle(payload(repo, commit)))->toBe(0)
      // Describing keeps what passed; changing a file does not.
      Node.run(~cwd=repo, "jj", ["describe", "-m", "chore: a", "--quiet"])->ignore
      expect(Verified.handle(payload(repo, commit)))->toBe(0)
      tree(repo, [("a.md", "two\n")])
      expect(Verified.handle(payload(repo, commit)))->toBe(2)
    },
  )
})
