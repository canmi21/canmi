open Testing

let payload = (cwd, command): Payload.t =>
  Dict.fromArray([
    ("cwd", JSON.String(cwd)),
    ("tool_input", JSON.Object(Dict.fromArray([("command", JSON.String(command))]))),
  ])

let jj = (cwd, args) => Node.spawnSync("jj", args, {cwd, encoding: "utf8"}).status->ignore
let long = Array.fromInitializer(~length=1100, at => Int.toString(at))->Array.join("\n") ++ "\n"
let everywhere = _ => true

describe("the words of a commit that name files", () => {
  test("are the ones past the flags and the values they take", () => {
    expect(Form.filesets(["-m", "docs: a", "a.md", "--author", "x <y>", "b/"]))->toEqual([
      "a.md",
      "b/",
    ])
    expect(Form.filesets(["--message=x"]))->toEqual([])
  })
})

describe("the form gate", () => {
  let root = temporaryRoot("form-gate-")
  let commit = "jj commit -m 'chore: a'"
  let main = () => {
    let repo = root.contents
    jj(repo, ["git", "init", "--quiet"])
    tree(repo, [("ok.md", "one\n"), ("big.txt", long)])
    Node.realpathSync(repo)
  }

  test("refuses a commit onto a main checkout while the tree holds a finding", () => {
    let repo = main()
    expect(Form.handle(payload(repo, commit), ~owned=everywhere))->toBe(2)
    expect(Form.handle(payload(repo, "jj describe -m 'chore: a'"), ~owned=everywhere))->toBe(0)
    tree(repo, [("big.txt", "short\n")])
    expect(Form.handle(payload(repo, commit), ~owned=everywhere))->toBe(0)
  })

  test("is passed by SKIP=form and by a repository the workspace does not own", () => {
    let repo = main()
    expect(Form.handle(payload(repo, `SKIP=form ${commit}`), ~owned=everywhere))->toBe(0)
    expect(Form.handle(payload(repo, commit)))->toBe(0)
  })

  test("only warns in a lane, a jj workspace beside the main checkout", () => {
    let repo = main()
    let lane = repo ++ "-lane"
    jj(repo, ["workspace", "add", "--quiet", lane])
    tree(lane, [("big.txt", long)])
    expect(Form.mainCheckout(Node.realpathSync(lane)))->toBe(false)
    expect(Form.mainCheckout(repo))->toBe(true)
    expect(Form.handle(payload(lane, commit), ~owned=everywhere))->toBe(0)
    Node.rmSync(lane, {recursive: true, force: true})
  })

  test("judges a commit by path on what it commits, not on the edits left out", () => {
    let repo = main()
    expect(Form.handle(payload(repo, `${commit} ok.md`), ~owned=everywhere))->toBe(0)
    expect(Form.handle(payload(repo, `${commit} big.txt`), ~owned=everywhere))->toBe(2)
    expect(Form.handle(payload(repo, `${commit} ok.md big.txt`), ~owned=everywhere))->toBe(2)
  })

  test("names the file and the rule it refuses on", () => {
    let repo = main()
    let answer = Node.spawnSync(
      "node",
      [Form.program, repo, repo],
      {encoding: "utf8", maxBuffer: 268435456},
    )
    let said = Form.findings(answer.stdout->Nullable.getOr(""))->Array.join("\n")
    expect(answer.status->Nullable.toOption)->toEqual(Some(1))
    expect(said->String.includes("big.txt"))->toBe(true)
    expect(said->String.includes("file-short"))->toBe(true)
  })
})
