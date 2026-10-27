open Testing

/** Why `parse` refused what was typed, or None where it took it. */
let refused = argv =>
  try {
    Repos.parse(argv)->ignore
    None
  } catch {
  | Registry.Refused(why) => Some(why)
  }

describe("what a verb was asked", () => {
  test("a bare verb is the workspace alone, a name that repository", () => {
    let bare = Repos.parse(["pull"])
    expect((bare.name, bare.everything))->toEqual((None, false))
    let named = Repos.parse(["push", "apps/rdm", "--dry-run"])
    expect((named.name, named.dry))->toEqual((Some("apps/rdm"), true))
  })

  test("the workspace's own check takes its parts and --pending", () => {
    expect(Repos.parse(["verify", "workspace", "words", "names"]).parts)->toEqual([
      "words",
      "names",
    ])
    expect(Repos.parse(["verify", "workspace", "--pending"]).parts)->toEqual(["--pending"])
  })

  test("what the verb would not act on is refused rather than dropped", () => {
    expect(refused(["fmt", "a", "b"]))->toEqual(Some("one name at most; b would have been ignored"))
    expect(refused(["verify", "apps/rdm", "words"])->Option.isSome)->toBe(true)
    expect(refused(["pull", "--major"])->Option.isSome)->toBe(true)
    expect(refused(["list", "--all"])->Option.isSome)->toBe(true)
    expect(refused(["fmt", "--dry"]))->toEqual(Some("unknown option --dry"))
    expect(refused(["verify", "--pending"])->Option.isSome)->toBe(true)
  })

  test("publish hands what follows the name on unread, -n spelled out", () => {
    expect(Repos.parse(["publish", "canmi/web", "--live", "-n"]).passed)->toEqual([
      "--live",
      "--dry-run",
    ])
  })
})

describe("an update's movers", () => {
  let root = temporaryRoot("repos-update-")
  let mover = (name, code, said) => {
    let path = Node.join([root.contents, name, "releases.res.mjs"])
    tree(
      root.contents,
      [(`${name}/releases.res.mjs`, `console.log(${said}); process.exit(${Int.toString(code)})`)],
    )
    path
  }
  let held = Releases.heldLine("manifest.toml", ["monoflake/driver"])
  let quoted = JSON.stringifyAny(held)->Option.getOr(`""`)

  testAsync("keep exit 2 from the releases mover and the source it held back", async () => {
    let sources = []
    let code = await Repos.moved(root.contents, [[mover("partly", 2, quoted)]], ~held=sources)
    expect(code)->toBe(Releases.partly)
    expect(sources)->toEqual(["monoflake/driver"])
  })

  testAsync("fail where any mover failed outright", async () => {
    let both = [[mover("partly", 2, quoted)], [mover("failed", 1, `"releases: no"`)]]
    expect(await Repos.moved(root.contents, both))->toBe(1)
    expect(await Repos.moved(root.contents, [[mover("failed", 1, `"releases: no"`)]]))->toBe(1)
  })

  test("keep a runtime-only change on exit 2 and put it back on exit 1, as before", () => {
    let config = Node.mkdtempSync(Node.join([Node.tmpdir(), "jj-config-"]))
    let environment =
      ["JJ_CONFIG", "JJ_USER", "JJ_EMAIL"]->Array.map(name => (name, Node.env->Dict.get(name)))
    Node.env->Dict.set("JJ_CONFIG", config)
    Node.env->Dict.set("JJ_USER", "test")
    Node.env->Dict.set("JJ_EMAIL", "test@example.com")
    let repo = root.contents
    let lock = Node.join([repo, "manifest.lock"])
    Node.writeFileSync(lock, "[workerd]\nversion = \"1.20261020.1\"\n")
    expect(Node.run(~cwd=repo, "jj", ["git", "init", "--quiet"]))->toBe(0)
    let settle = code => {
      let before = Stamp.snapshot(repo)
      Node.writeFileSync(lock, "[workerd]\nversion = \"1.20261025.1\"\n")
      let after = Stamp.snapshot(repo)
      let paths =
        Node.output(
          ~cwd=repo,
          "jj",
          ["diff", "--from", before, "--to", after, "--name-only"],
        )->Repos.lines
      expect(paths)->toEqual(["manifest.lock"])
      let kept = Repos.settled(repo, ~code, ~before, ~paths)
      (kept, Node.readFileSync(lock))
    }
    expect(settle(2))->toEqual((true, "[workerd]\nversion = \"1.20261025.1\"\n"))
    Node.writeFileSync(lock, "[workerd]\nversion = \"1.20261020.1\"\n")
    expect(settle(1))->toEqual((false, "[workerd]\nversion = \"1.20261020.1\"\n"))
    environment->Array.forEach(
      ((name, value)) =>
        switch value {
        | Some(value) => Node.env->Dict.set(name, value)
        | None => Node.env->Dict.delete(name)
        },
    )
    Node.rmSync(config, {recursive: true, force: true})
  })
})
