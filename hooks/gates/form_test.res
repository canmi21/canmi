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

describe("the form gate over a main that already carries a finding", () => {
  let root = temporaryRoot("form-gate-parent-")
  let commit = "jj commit -m 'chore: a'"
  let block = Array.fromInitializer(~length=Code.openingLines + 1, _ => "// words")
  let wide = Array.fromInitializer(~length=Layout.widest + 1, at => (`d/${Int.toString(at)}`, "x"))
  let clean = [("ok.md", "one\n")]
  let cases = [
    ("lines", [("sys/src/f.txt", long)], [("sys/src/f.txt", "short\n")]),
    (
      "comments",
      [("sys/src/f.res", block->Array.join("\n") ++ "\nlet x = 1\n")],
      [("sys/src/f.res", "let x = 1\n")],
    ),
    ("shape", wide, []),
  ]
  let carrying = found => {
    let repo = root.contents
    jj(repo, ["git", "init", "--quiet"])
    tree(repo, Array.concat(clean, found))
    jj(repo, ["commit", "-m", "chore: parent"])
    Node.realpathSync(repo)
  }

  cases->Array.forEach(((part, found, fixed)) => {
    test(
      `passes a commit that fixes a ${part} finding the parent carries`,
      () => {
        let repo = carrying(found)
        found->Array.forEach(
          ((path, _)) => Node.rmSync(Node.join([repo, path]), {recursive: true, force: true}),
        )
        tree(repo, fixed)
        tree(repo, [("ok.md", "two\n"), ("new.md", "n\n")])
        expect(Form.handle(payload(repo, commit), ~owned=everywhere))->toBe(0)
        fixed->Array.forEach(
          ((path, _)) =>
            expect(
              Form.handle(
                payload(repo ++ "/sys", `${commit} ${path->String.replace("sys/", "")}`),
                ~owned=everywhere,
              ),
            )->toBe(0),
        )
      },
    )

    test(
      `refuses a commit that adds a ${part} finding to a clean parent`,
      () => {
        let repo = carrying([])
        tree(repo, found)
        expect(Form.handle(payload(repo, commit), ~owned=everywhere))->toBe(2)
      },
    )
  })
})

describe("the form gate over edits jj has not snapshotted", () => {
  let root = temporaryRoot("form-gate-unsnapshotted-")
  let commit = "jj commit -m 'chore: a'"
  let block = Array.fromInitializer(~length=Code.openingLines + 1, _ => "// words")
  let wide = Array.fromInitializer(~length=Layout.widest + 1, at => (`d/${Int.toString(at)}`, "x"))
  let sixty = String.repeat("w", 120)
  let cases = [
    ("lines", [("sys/src/f.txt", long)], [("sys/src/f.txt", "short\n")]),
    (
      "comments",
      [("sys/src/f.res", block->Array.join("\n") ++ "\nlet x = 1\n")],
      [("sys/src/f.res", "let x = 1\n")],
    ),
    (
      "comments",
      [("sys/src/g.res", `// ${sixty}\n// ${sixty}\nlet x = 1\n`)],
      [("sys/src/g.res", "let x = 1\n")],
    ),
    ("shape", wide, []),
  ]
  let start = () => {
    let repo = root.contents
    jj(repo, ["git", "init", "--quiet"])
    tree(repo, [("ok.md", "one\n")])
    jj(repo, ["commit", "-m", "chore: parent"])
    Node.realpathSync(repo)
  }

  cases->Array.forEach(((part, found, fixed)) => {
    test(
      `refuses a ${part} finding written since the last snapshot`,
      () => {
        let repo = start()
        tree(repo, found)
        expect(Form.handle(payload(repo, commit), ~owned=everywhere))->toBe(2)
      },
    )

    test(
      `passes a ${part} finding fixed since the last snapshot`,
      () => {
        let repo = start()
        tree(repo, found)
        jj(repo, ["status"])
        found->Array.forEach(
          ((path, _)) => Node.rmSync(Node.join([repo, path]), {recursive: true, force: true}),
        )
        tree(repo, fixed)
        expect(Form.handle(payload(repo, commit), ~owned=everywhere))->toBe(0)
      },
    )
  })
})

describe("the form gate over a main checkout another workspace has made stale", () => {
  let root = temporaryRoot("form-gate-stale-")
  let commit = "jj commit -m 'chore: a'"

  test("judges the edits on disk and never passes for want of a snapshot", () => {
    let repo = root.contents
    jj(repo, ["git", "init", "--quiet"])
    tree(repo, [("ok.md", "one\n")])
    jj(repo, ["commit", "-m", "chore: parent"])
    let lane = repo ++ "-lane"
    jj(repo, ["workspace", "add", "--quiet", lane])
    jj(lane, ["describe", "default@", "-m", "chore: rewritten from the lane"])
    tree(repo, [("big.txt", long)])
    expect(Form.handle(payload(Node.realpathSync(repo), commit), ~owned=everywhere))->toBe(2)
    Node.rmSync(lane, {recursive: true, force: true})
  })
})

describe("the form gate over a program that does not finish", () => {
  test("refuses and never passes for want of an answer", () => {
    let repo = Node.mkdtempSync(Node.join([Node.tmpdir(), "form-gate-broken-"]))
    jj(repo, ["git", "init", "--quiet"])
    Node.rmSync(Node.join([repo, ".jj", "working_copy"]), {recursive: true, force: true})
    expect(
      Form.handle(payload(Node.realpathSync(repo), "jj commit -m 'chore: a'"), ~owned=everywhere),
    )->toBe(2)
    Node.rmSync(repo, {recursive: true, force: true})
  })
})
