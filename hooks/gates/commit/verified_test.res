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

describe("where a commit runs", () => {
  test("follows each cd before it, then -R", () => {
    expect(
      Jj_command.placed(
        "cd a && jj commit -m x && cd ../b && jj -R c ci",
        ~cwd="/w",
        ["commit", "ci"],
      ),
    )->toEqual(["/w/a", "/w/b/c"])
    expect(Jj_command.placed("jj log", ~cwd="/w", ["commit"]))->toEqual([])
    expect(Jj_command.placed("echo 'jj commit -m x'", ~cwd="/w", ["commit"]))->toEqual([])
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

  let moved = temporaryRoot("verified-path-")
  test("keeps what passed when a commit by path moves files to the parent", () => {
    let repo = moved.contents
    Node.run(~cwd=repo, "jj", ["git", "init", "--quiet"])->ignore
    tree(repo, [("a.md", "one\n"), ("b.md", "two\n")])
    let at = Node.realpathSync(repo)
    Stamp.write(at, Stamp.snapshot(at))
    let first = payload(repo, "jj commit 'root:\"a.md\"' -m 'chore: a'")
    let rest = payload(repo, "jj commit -m 'chore: b'")
    expect(Verified.handle(first))->toBe(0)
    Node.run(~cwd=repo, "jj", ["commit", "root:\"a.md\"", "-m", "chore: a", "--quiet"])->ignore
    expect(Verified.handle(rest))->toBe(0)
    Node.run(~cwd=repo, "jj", ["commit", "-m", "chore: b", "--quiet"])->ignore
    tree(repo, [("b.md", "three\n")])
    expect(Verified.handle(rest))->toBe(2)
  })
})

describe("the verify refusal", () => {
  let answer = (~status, ~stdout="", ~stderr="", ~error=?): Node.spawned => {
    status: Nullable.fromOption(status),
    error: Nullable.fromOption(error),
    stdout: Nullable.make(stdout),
    stderr: Nullable.make(stderr),
  }
  let timedOut: JsExn.t = %raw(`Object.assign(new Error("spawnSync jj ETIMEDOUT"), {code: "ETIMEDOUT"})`)

  test("names the paths changed since the stamp, five at most", () => {
    let said = Stamp.judge(answer(~status=Some(0), ~stdout="M a.md\nA dir/b.md\n"))
    expect(said)->toEqual(Stamp.Changed(["a.md", "dir/b.md"]))
    expect(Verified.reason(said))->toBe("has changed since verify passed, a.md, dir/b.md")
    let many = Stamp.Changed(["1", "2", "3", "4", "5", "6", "7"])
    expect(Verified.reason(many))->toBe(
      "has changed since verify passed, 1, 2, 3, 4, 5, and 2 more",
    )
  })

  test("says jj diff failed with its exit and first stderr line", () => {
    let said = Stamp.judge(answer(~status=Some(1), ~stderr="Error: no such revision\nmore\n"))
    expect(said)->toEqual(Stamp.Failed(1, "Error: no such revision"))
    expect(Verified.reason(said))->toBe(
      "could not be compared with the stamp, jj diff exited 1: Error: no such revision",
    )
  })

  test("says jj diff timed out with the timeout", () => {
    let said = Stamp.judge(answer(~status=None, ~error=timedOut))
    expect(said)->toEqual(Stamp.TimedOut(Stamp.timeout))
    expect(Verified.reason(said))->toBe(
      "could not be compared with the stamp, jj diff timed out after 30000 ms",
    )
  })

  test("holds on an empty summary", () => {
    expect(Stamp.judge(answer(~status=Some(0), ~stdout="\n")))->toEqual(Stamp.Held)
  })
})
