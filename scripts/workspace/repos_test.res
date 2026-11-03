open Testing

@module("node:fs") external symlinkSync: (string, string) => unit = "symlinkSync"

describe("a checkout's inherited configuration", () => {
  test("compares remote addresses without transport, credentials or a git suffix", () => {
    [
      "https://github.com/canmi21/canmi",
      "https://token@github.com/canmi21/canmi.git",
      "https://user:password@github.com/canmi21/canmi.git/",
      "git@github.com:canmi21/canmi.git",
      "ssh://git@github.com/canmi21/canmi.git",
    ]->Array.forEach(
      address => expect(Registry.normalized(address))->toEqual("github.com/canmi21/canmi"),
    )
    expect(Registry.normalized("https://github.com/another/canmi.git"))->toEqual(
      "github.com/another/canmi",
    )
  })

  test("accepts a workspace link and diagnoses a copy or shadow within the checkout alone", () => {
    let workspace = Node.mkdtempSync(Node.join([Node.tmpdir(), "inherited-"]))
    let project = Node.join([workspace, "repos", "project"])
    tree(workspace, [(".editorconfig", "root = true\n"), ("repos/project/placeholder", "")])
    symlinkSync(Node.join([workspace, ".editorconfig"]), Node.join([project, ".editorconfig"]))
    expect(
      Registry.shadowingIn(project, [".editorconfig", "../../.editorconfig"], ~workspace),
    )->toEqual([])
    let copy = Node.join([workspace, "repos", "copy"])
    tree(copy, [(".editorconfig", "root = true\n")])
    expect(Registry.shadowingIn(copy, [".editorconfig"], ~workspace))->toEqual([
      ".editorconfig is a byte-identical copy of the workspace's; link ../../.editorconfig instead",
    ])
    Node.writeFileSync(Node.join([copy, ".editorconfig"]), "root = false\n")
    expect(Registry.shadowingIn(copy, [".editorconfig"], ~workspace))->toEqual([
      ".editorconfig shadows the workspace's, which is inherited by position",
    ])
  })
})

/** Why `parse` refused what was typed, or None where it took it. */
let refused = argv =>
  try {
    Repos.parse(argv)->ignore
    None
  } catch {
  | Registry.Refused(why) => Some(why)
  }

describe("what a verb was asked", () => {
  test("JSON belongs to the update dry run", () => {
    expect(Repos.parse(["update", "--all", "--dry-run", "--json"]).json)->toBe(true)
    expect(refused(["update", "--json"]))->toEqual(Some("--json belongs to update --dry-run"))
    expect(refused(["pull", "--dry-run", "--json"]))->toEqual(
      Some("--json belongs to update --dry-run"),
    )
  })
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
    expect(Repos.parse(["verify", "apps/rdm", "own", "names"]).parts)->toEqual(["own", "names"])
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

describe("a repository's check parts", () => {
  // A fixture repository of its own, as no clone of a real one is there to read.
  let repo = Node.mkdtempSync(Node.join([Node.tmpdir(), "repos-fixture-"]))
  tree(repo, [("mise.toml", `[tasks."verify:rust"]\nrun = "true"\n`)])
  let names = parts => Repos.checkParts(repo, parts)->Array.map(((name, _)) => name)
  let every = Check.over(repo)->Array.map(((name, _)) => name)
  let refusedParts = parts =>
    try {
      Repos.checkParts(repo, parts)->ignore
      None
    } catch {
    | Registry.Refused(why) => Some(why)
    }

  test("a workspace part runs that part alone over the repository, not its verify", () => {
    expect(names(["names"]))->toEqual(["names"])
    expect(Repos.runsOwn(["names"]))->toBe(false)
    expect(Repos.rulesLine(["names"], Repos.checkParts(repo, ["names"])))->toBe(
      "would run the workspace's rules over it names",
    )
  })

  test("own runs the repository's verify whole and no workspace part", () => {
    expect(names(["own"]))->toEqual([])
    expect(Repos.runsOwn(["own"]))->toBe(true)
  })

  test("several parts run what is named alone, in the check's order", () => {
    expect(names(["own", "names", "tasks"]))->toEqual(["tasks", "names"])
    expect(Repos.runsOwn(["own", "names", "tasks"]))->toBe(true)
    expect(Repos.runsOwn(["names", "tasks"]))->toBe(false)
  })

  test("no part runs the verify and every workspace rule, as before", () => {
    expect(names([]))->toEqual(every)
    expect(Repos.runsOwn([]))->toBe(true)
    expect(Repos.rulesLine([], Repos.checkParts(repo, [])))->toBe(
      "would run the workspace's rules over it",
    )
  })

  test("only the full check writes the stamp a commit waits on", () => {
    expect(Repos.stamps("verify", ~dry=false, ~parts=[]))->toBe(true)
    expect(Repos.stamps("verify", ~dry=false, ~parts=["own"]))->toBe(false)
    expect(Repos.stamps("verify", ~dry=false, ~parts=["names"]))->toBe(false)
    expect(Repos.stamps("verify", ~dry=true, ~parts=[]))->toBe(false)
    expect(Repos.stamps("fmt", ~dry=false, ~parts=[]))->toBe(false)
  })

  test("a verify part runs the repository's own task alone, in its mise.toml's order", () => {
    let declared = Node.mkdtempSync(Node.join([Node.tmpdir(), "repos-parts-"]))
    tree(
      declared,
      [
        (
          "mise.toml",
          ["format", "nix", "rust", "tests"]
          ->Array.map(part => `[tasks."verify:${part}"]\nrun = "true"\n`)
          ->Array.join("\n"),
        ),
      ],
    )
    let parts = Repos.verifyParts(declared)
    let named = Repos.namedVerifyParts(declared, ["tests", "names", "rust"])
    Node.rmSync(declared, {recursive: true, force: true})
    expect(parts)->toEqual(["format", "nix", "rust", "tests"])
    expect(named)->toEqual(["rust", "tests"])
    expect(names(["names"]))->toEqual(["names"])
    expect(Repos.runsOwn(["rust"]))->toBe(false)
    expect(Repos.stamps("verify", ~dry=false, ~parts=["rust"]))->toBe(false)
  })

  test("a name the repository's verify and the workspace share is refused as ambiguous", () => {
    let shared = Node.mkdtempSync(Node.join([Node.tmpdir(), "repos-parts-"]))
    tree(shared, [("mise.toml", `[tasks."verify:names"]\nrun = "true"\n`)])
    let why = try {
      Repos.checkParts(shared, ["names"])->ignore
      None
    } catch {
    | Registry.Refused(why) => Some(why)
    }
    Node.rmSync(shared, {recursive: true, force: true})
    expect(why->Option.map(why => why->String.startsWith("names is ambiguous")))->toEqual(
      Some(true),
    )
  })

  test("a name that is no part is refused, listing the valid ones", () => {
    let valid = ["own", ...Repos.verifyParts(repo), ...every]->Array.join(", ")
    expect(refusedParts(["own", "invalid"]))->toEqual(
      Some(`${Registry.label(repo)}'s check has no part invalid; the parts are ${valid}`),
    )
    expect(refusedParts(["own", "names"]))->toEqual(None)
  })

  testAsync("--all with parts is refused before any repository is read", async () => {
    let why = try {
      (await Repos.dispatch("verify", None, ~dry=true, ~everything=true, ~parts=["names"]))->ignore
      None
    } catch {
    | Registry.Refused(why) => Some(why)
    }
    expect(why)->toEqual(Some("--all and check parts cannot be combined"))
  })
})

describe("a full check's order", () => {
  let part = Check.Script(() => 0)
  let shared = ["names", "comments", "tasks", "lines", "shape"]->Array.map(name => (name, part))
  let steps = Repos.planned(shared, ["rust", "format"])
  let walk = async failing => {
    let ran = []
    let result = await Repos.walked(steps, async step => {
      let name = Repos.stepName(step)
      ran->Array.push(name)
      failing->Array.includes(name) ? (1, `error: ${name} failed`) : (0, `${name} passed`)
    })
    (result, ran)
  }

  test("runs the form parts, then the own format, then verify, then the other rules", () => {
    expect(steps->Array.map(Repos.stepName))->toEqual([
      "shape",
      "lines",
      "comments",
      "verify:format",
      "verify",
      "names",
      "tasks",
    ])
    expect(Repos.planned(shared, ["rust"])->Array.map(Repos.stepName))->toEqual([
      "shape",
      "lines",
      "comments",
      "verify",
      "names",
      "tasks",
    ])
  })

  testAsync(
    "a failed form part stops the repository before its verify, reported failed",
    async () => {
      let ((status, said), ran) = await walk(["lines"])
      expect(status)->toBe(1)
      expect(ran)->toEqual(["shape", "lines"])
      expect(said)->toBe("error: lines failed")
      let ((status, _), ran) = await walk(["verify:format"])
      expect(status)->toBe(1)
      expect(ran->Array.includes("verify"))->toBe(false)
    },
  )

  testAsync(
    "form parts that pass run the verify, and the rules go on past its failure",
    async () => {
      let ((status, said), ran) = await walk([])
      expect((status, said))->toEqual((0, ""))
      expect(ran)->toEqual(steps->Array.map(Repos.stepName))
      let ((status, said), ran) = await walk(["verify", "names"])
      expect(status)->toBe(1)
      expect(ran)->toEqual(steps->Array.map(Repos.stepName))
      expect(said)->toBe("error: verify failed\nerror: names failed")
    },
  )

  test("a part run here keeps what it logged beside its status", () => {
    let (status, said) = Repos.heard(
      () => {
        Console.log("  error: one finding")
        1
      },
    )
    expect((status, said))->toEqual((1, "  error: one finding"))
  })

  test("a failed summary ends with each failed repository's causes", () => {
    let causes = [("apps/rdm", ["error: a", "error: b"]), ("canmi/lib", []), ("seam", ["x"])]
    let lines = Repos.summaryLines("verify", [], ["apps/rdm", "seam"], ~causes)
    let tail = ["apps/rdm:", "  error: a", "  error: b", "seam:", "  x"]
    expect(lines->Array.slice(~start=-6))->toEqual(["failed: apps/rdm, seam", ...tail])
    expect(Repos.summaryLines("verify", [], []))->toEqual([])
  })

  test("--verbose is taken and passed on", () => {
    expect(Repos.parse(["verify", "apps/rdm", "--verbose"]).verbose)->toBe(true)
    expect(Repos.parse(["verify", "apps/rdm"]).verbose)->toBe(false)
  })
})

describe("an update's movers", () => {
  test("keeps actual flake revisions from a repository's dry report", () => {
    expect(
      Repos.ownItems(
        ~repository="monoflake/platform",
        "• Updated input 'nixpkgs':\n    'github:NixOS/nixpkgs/old' (2026-10-01)\n  → 'github:NixOS/nixpkgs/new' (2026-10-31)",
      ),
    )->toEqual([
      Reminder.item(
        ~repository="monoflake/platform",
        "flake",
        "nixpkgs",
        "github:NixOS/nixpkgs/old",
        "github:NixOS/nixpkgs/new",
      ),
    ])
    expect(
      Repos.ownItems(~repository="monoflake/platform", "would run nix flake update"),
    )->toEqual([])
  })

  test("keeps both in pin and across pin tool candidates", () => {
    let row: Tools.row = {
      where: Registry.root,
      tool: "pnpm",
      version: "11.24.0",
      pin: "11.24",
      line: Some("11.26.0"),
      newest: Some("12.0.0"),
    }
    expect(Tools.machineRows([row]))->toEqual([
      Reminder.item(~repository="workspace", "major", "pnpm", "11.24.0", "11.26.0"),
      Reminder.item(~repository="workspace", "major", "pnpm", "11.24.0", "12.0.0"),
    ])
    expect(Tools.machineRows([{...row, pin: "11"}])->Array.map(item => item.kind))->toEqual([
      "tool",
      "major",
    ])
    expect(Tools.machineRows([{...row, version: "12.0.0", line: Some("11.26.0")}]))->toEqual([])
  })
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

describe("the task roots mise reads", () => {
  test("a root ending in a star is read back as its path, a bare one is not", () => {
    expect(Registry.rootPath("repos/canmi/web*"))->toEqual(Some("repos/canmi/web"))
    expect(Registry.rootPath("repos/canmi/web"))->toEqual(None)
  })

  test("every root mise.toml writes ends in a star and names a listed repository", () => {
    let roots = Registry.taskRoots()
    expect(roots->Array.every(one => one->String.endsWith("*")))->toBe(true)
    let paths = roots->Array.filterMap(Registry.rootPath)->Array.toSorted(String.compare)
    let listed =
      Registry.paths()->Array.map(path => `repos/${path}`)->Array.toSorted(String.compare)
    expect(paths)->toEqual(listed)
  })
})

describe("what a check's blocks in work fail", () => {
  test("is named once each at the end, and nothing where none fail", () => {
    let lines = Repos.inWorkOf("a fails\nb fails\na fails\n")
    expect(lines)->toEqual(["a fails", "b fails"])
    expect(Repos.inWorkSaid(lines)->Array.length)->toEqual(3)
    expect(Repos.inWorkSaid([]))->toEqual([])
  })
})
