open Testing

let payload = (cwd, command): Payload.t =>
  Dict.fromArray([
    ("cwd", JSON.String(cwd)),
    ("tool_input", JSON.Object(Dict.fromArray([("command", JSON.String(command))]))),
  ])

let jj = (cwd, args) => Node.spawnSync("jj", args, {cwd, encoding: "utf8"}).status->ignore

describe("the words a restore or abandon names", () => {
  test("are the paths past the flags and the values they take", () => {
    expect(Lose.operands(["--from", "x@", "a.md"], ~valued=Lose.restoreValued))->toEqual(["a.md"])
    expect(Lose.operands(["--from=x@", "--", "-a"], ~valued=Lose.restoreValued))->toEqual(["-a"])
  })

  test("are the target of a restore without a path, the working copy by default", () => {
    expect(Lose.targets("restore", ["--from", "x@"]))->toEqual(["@"])
    expect(Lose.targets("restore", ["--into=y", "-f", "x"]))->toEqual(["y"])
    expect(Lose.targets("restore", ["-c", "r"]))->toEqual(["r"])
    expect(Lose.targets("restore", ["--from", "x@", "'a b'"]))->toEqual([])
    expect(Lose.targets("abandon", []))->toEqual(["@"])
    expect(Lose.targets("abandon", ["-r", "a", "b"]))->toEqual(["a", "b"])
  })
})

describe("the lose gate", () => {
  let root = temporaryRoot("lose-gate-")
  let main = () => {
    let repo = root.contents
    jj(repo, ["git", "init", "--quiet"])
    Node.realpathSync(repo)
  }

  test("refuses a pathless restore and an abandon of a commit holding changes", () => {
    let repo = main()
    expect(Lose.handle(payload(repo, "jj restore --from main@")))->toBe(0)
    tree(repo, [("a.md", "one\n")])
    expect(Lose.handle(payload(repo, "jj restore --from main@")))->toBe(2)
    expect(Lose.handle(payload(repo, "jj restore --to @ -f 'root()'")))->toBe(2)
    expect(Lose.handle(payload(repo, "jj abandon")))->toBe(2)
    expect(Lose.handle(payload(repo, "jj abandon @")))->toBe(2)
    expect(Lose.handle(payload(repo, "jj abandon -r @")))->toBe(2)
    expect(Lose.handle(payload("/tmp", `jj -R ${repo} abandon @`)))->toBe(2)
  })

  test(
    "passes a restore of named paths, an empty commit, SKIP=restore and a jj that cannot answer",
    () => {
      let repo = main()
      tree(repo, [("a.md", "one\n")])
      expect(Lose.handle(payload(repo, "jj restore --from 'root()' 'a.md'")))->toBe(0)
      expect(Lose.handle(payload(repo, "SKIP=restore jj restore")))->toBe(0)
      expect(Lose.handle(payload(repo, "jj new -m x && jj abandon 'root()'")))->toBe(0)
      expect(Lose.handle(payload(repo, "jj abandon @"), ~holds=(_, _) => Error("no jj")))->toBe(0)
      expect(Lose.handle(payload(repo, "jj log")))->toBe(0)
    },
  )
})
