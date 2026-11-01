open Testing

let v = text => Numbers.parse(text)->Option.getOrThrow

let asked = (~base=?, ~now, ~changed=false, ~target=?, ~minor=false): Numbers.asked => {
  base: base->Option.map(v),
  now: v(now),
  changed,
  target,
  minor,
}

let rolled = (~base=?, ~now, ~changed=false, ~target=?, ~minor=false) =>
  Numbers.show(Numbers.rolled(asked(~base?, ~now, ~changed, ~target?, ~minor)))

let nothing: Project.versions = {
  counts: Dict.make(),
  serves: Dict.make(),
  contracts: None,
  repository: None,
  pin: None,
}

let package = (~name, directory, ~version="0.1.0", ~manifest=?, ~builds=[]): Packages.t => {
  directory,
  builds,
  name,
  version: v(version),
  manifests: manifest->Option.mapOr([], text => [
    {Packages.path: `${directory}/Cargo.toml`, kind: Cargo, text},
  ]),
}

let owing = (~versions=nothing, ~minors=[], ~before=?, ~after=?, packages, changes) =>
  Roll.owing(
    packages,
    ~baseOf=package => Some(package.version),
    ~changes=changes->Array.map(path => (path, Some("was"), Some("is"))),
    ~versions,
    ~minors,
    ~breaking=_ => false,
    ~before,
    ~after,
  )->Array.map(row => (row.package.name, Numbers.show(Numbers.rolled(row.asked))))

describe("a roll", () => {
  test("starts everything at zero and continues the rest", () => {
    expect(rolled(~base="0.0.0", ~now="0.0.0"))->toBe("0.1.0")
    expect(rolled(~base="0.0.0", ~now="0.0.0", ~target=3))->toBe("0.3.0")
    expect(rolled(~base="0.1.4", ~now="0.1.4"))->toBe("0.1.4")
    expect(rolled(~base="0.1.4", ~now="0.1.4", ~changed=true))->toBe("0.1.5")
  })

  test("raises the minor with the patch back to zero, and follows its one interface", () => {
    expect(rolled(~base="0.1.4", ~now="0.1.4", ~changed=true, ~minor=true))->toBe("0.2.0")
    expect(rolled(~base="0.1.4", ~now="0.1.4", ~changed=true, ~target=3))->toBe("0.3.0")
    expect(rolled(~base="0.3.4", ~now="0.3.4", ~changed=true, ~target=3))->toBe("0.3.5")
  })

  test("asks the same a second time and keeps a raise by hand", () => {
    expect(rolled(~base="0.1.4", ~now="0.1.5", ~changed=true))->toBe("0.1.5")
    expect(rolled(~base="0.1.4", ~now="0.4.0", ~changed=true))->toBe("0.4.0")
  })

  test("leaves a new package at the version it was written with", () => {
    expect(rolled(~now="0.2.1", ~changed=true))->toBe("0.2.1")
    expect(rolled(~now="0.0.0", ~changed=true))->toBe("0.1.0")
  })
})

describe("what the check refuses", () => {
  test("a changed package with no raise, and one raised passes", () => {
    expect(Numbers.broken(asked(~base="0.1.4", ~now="0.1.4", ~changed=true)))->toEqual([
      "stays 0.1.4, owing 0.1.5",
    ])
    expect(Numbers.broken(asked(~base="0.1.4", ~now="0.1.5", ~changed=true)))->toEqual([])
  })

  test("a major moved, and a version fallen", () => {
    expect(Numbers.broken(asked(~base="0.1.4", ~now="1.0.0", ~changed=true))->Array.length)->toBe(1)
    expect(Numbers.broken(asked(~base="0.1.4", ~now="0.1.3"))->Array.length)->toBe(2)
  })

  test("a minor apart from its one interface", () => {
    expect(Numbers.broken(asked(~base="0.2.0", ~now="0.2.0", ~target=3))->Array.length)->toBe(2)
  })
})

describe("what counts", () => {
  test("source and build files count, and the excluded do not", () => {
    [
      "src/a.rs",
      "Cargo.lock",
      "pnpm-lock.yaml",
      "mise.toml",
      ".github/workflows/a.yml",
    ]->Array.forEach(path => expect(Counted.counts(path))->toBe(true))
    [
      "docs/a.txt",
      "code/x/docs/b.txt",
      "tests/a.rs",
      "src/tests/a.rs",
      "src/a_test.res",
      "src/a_test.res.mjs",
      "rustfmt.toml",
      ".oxlintrc.json",
      "AGENTS.md",
      "LICENSE-MIT",
    ]->Array.forEach(path => expect(Counted.counts(path))->toBe(false))
  })

  test("a file belongs to the deepest package holding it", () => {
    let directories = ["", "machine", "machine/object"]
    expect(Counted.owner(directories, "machine/object/src/a.rs"))->toBe("machine/object")
    expect(Counted.owner(directories, "machine/src/a.rs"))->toBe("machine")
    expect(Counted.owner(directories, "machinery/a.rs"))->toBe("")
  })

  test("a roll alone is no change of a manifest or a lock", () => {
    expect(Counted.bare("a/Cargo.toml", "name = \"a\"\nversion = \"0.1.0\"\n"))->toBe(
      Counted.bare("a/Cargo.toml", "name = \"a\"\nversion = \"0.9.0\"\n"),
    )
    expect(Counted.bare("package.json", "{\n\t\"name\": \"a\"\n}\n"))->toBe(
      Counted.bare("package.json", "{\n\t\"version\": \"0.1.0\",\n\t\"name\": \"a\"\n}\n"),
    )
    let lock = version =>
      `[[package]]\nname = "a"\nversion = "${version}"\n\n[[package]]\nname = "b"\nversion = "1.0.0"\nsource = "registry"\n`
    expect(Counted.bare("Cargo.lock", lock("0.1.0")))->toBe(
      Counted.bare("Cargo.lock", lock("0.2.0")),
    )
    expect(Counted.bare("Cargo.lock", lock("0.1.0")))
    ->negated
    ->toBe(Counted.bare("Cargo.lock", lock("0.1.0")->String.replace("1.0.0", "1.0.1")))
  })

  test("a rename names both its sides", () => {
    expect(Counted.summarized("M a/b.rs"))->toEqual(["a/b.rs"])
    expect(Counted.summarized("R a/{b => c}/d.rs"))->toEqual(["a/b/d.rs", "a/c/d.rs"])
    expect(Counted.summarized("R a/{ => c}/d.rs"))->toEqual(["a/d.rs", "a/c/d.rs"])
  })
})

describe("who owes", () => {
  let packages = [
    package(~name="root", ""),
    package(~name="leaf", "code/leaf", ~manifest=""),
    package(~name="user", "code/user", ~manifest="leaf = { path = \"../leaf\" }\n"),
    package(~name="apart", "code/apart", ~manifest=""),
  ]

  test("a subpackage's change raises it and its dependents and not the root", () =>
    expect(owing(packages, ["code/leaf/src/a.rs"]))->toEqual([
      ("root", "0.1.0"),
      ("leaf", "0.1.1"),
      ("user", "0.1.1"),
      ("apart", "0.1.0"),
    ])
  )

  test("a root's own file raises the root alone", () =>
    expect(owing(packages, ["Cargo.lock", "docs/a.txt"]))->toEqual([
      ("root", "0.1.1"),
      ("leaf", "0.1.0"),
      ("user", "0.1.0"),
      ("apart", "0.1.0"),
    ])
  )

  test("a declared path counts for the package declaring it", () => {
    let versions = {...nothing, counts: dict{"code/apart": [".github/actions/setup"]}}
    expect(owing(~versions, packages, [".github/actions/setup/action.yml"]))->toEqual([
      ("root", "0.1.1"),
      ("leaf", "0.1.0"),
      ("user", "0.1.0"),
      ("apart", "0.1.1"),
    ])
  })

  test("a lockfile raises what it builds and the root, and no library", () => {
    let built = [
      package(~name="root", ""),
      package(~name="binary", "machine", ~manifest="", ~builds=[Cargo]),
      package(~name="library", "machine/lib", ~manifest=""),
      package(~name="worker", "worker", ~builds=[Node]),
    ]
    expect(owing(built, ["Cargo.lock"]))->toEqual([
      ("root", "0.1.1"),
      ("binary", "0.1.1"),
      ("library", "0.1.0"),
      ("worker", "0.1.0"),
    ])
    expect(owing(built, ["pnpm-lock.yaml"]))->toEqual([
      ("root", "0.1.1"),
      ("binary", "0.1.0"),
      ("library", "0.1.0"),
      ("worker", "0.1.1"),
    ])
  })

  test("a package serving several raises its minor when one of them rises", () => {
    let versions = {...nothing, serves: dict{"code/apart": ["a", "b"]}}
    expect(
      owing(
        ~versions,
        ~before=dict{"a": 1, "b": 1},
        ~after=dict{"a": 1, "b": 2},
        [package(~name="apart", "code/apart", ~version="0.4.2")],
        [],
      ),
    )->toEqual([("apart", "0.5.0")])
  })

  test("a package serving one takes its minor from it", () => {
    let versions = {...nothing, serves: dict{"code/apart": ["a"]}}
    expect(
      owing(
        ~versions,
        ~before=dict{"a": 2},
        ~after=dict{"a": 3},
        [package(~name="apart", "code/apart", ~version="0.2.2")],
        [],
      ),
    )->toEqual([("apart", "0.3.0")])
  })

  test("a lander's judgment raises the minor of the package it names", () =>
    expect(
      owing(
        ~minors=["apart"],
        [package(~name="apart", "code/apart", ~version="0.2.2")],
        ["code/apart/src/a.rs"],
      ),
    )->toEqual([("apart", "0.3.0")])
  )
})

describe("a manifest", () => {
  test("is written at a version, the rest untouched", () => {
    let cargo = "[package]\nname = \"a\"\nversion = \"0.0.0\"\n\n[dependencies]\nb = { version = \"1\" }\n"
    expect(Packages.written({path: "Cargo.toml", kind: Cargo, text: cargo}, (0, 1, 0)))->toBe(
      "[package]\nname = \"a\"\nversion = \"0.1.0\"\n\n[dependencies]\nb = { version = \"1\" }\n",
    )
    let node = "{\n\t\"name\": \"a\",\n\t\"version\": \"0.0.0\",\n\t\"private\": true\n}\n"
    expect(Packages.written({path: "package.json", kind: Node, text: node}, (0, 1, 0)))->toBe(
      "{\n\t\"name\": \"a\",\n\t\"version\": \"0.1.0\",\n\t\"private\": true\n}\n",
    )
    let bare = "{\n\t\"name\": \"a\",\n\t\"private\": true\n}\n"
    expect(Packages.written({path: "package.json", kind: Node, text: bare}, (0, 1, 0)))->toBe(
      node->String.replace("0.0.0", "0.1.0"),
    )
  })

  test("a crate's lock follows it, and a registry's crate of one name does not", () => {
    let lock = `[[package]]\nname = "a"\nversion = "0.0.0"\n\n[[package]]\nname = "b"\nversion = "0.0.0"\nsource = "registry"\n`
    let followed = Packages.lockFollowed(lock, [("a", (0, 1, 0)), ("b", (0, 1, 0))])
    expect(followed)->toBe(lock->String.replace("0.0.0", "0.1.0"))
    expect(Packages.lockStale(followed, [("a", (0, 1, 0))]))->toEqual([])
    expect(Packages.lockStale(lock, [("a", (0, 1, 0))])->Array.length)->toBe(1)
  })

  test("a directory holding both manifests is one package, and a fixture is none", () => {
    let files = dict{
      "package.json": "{\"name\": \"r\"}",
      "code/a/Cargo.toml": "[package]\nname = \"a\"\nversion = \"0.0.0\"\n",
      "code/a/package.json": "{\"name\": \"@x/a\", \"version\": \"0.0.0\"}",
      "tests/fixture/package.json": "{\"name\": \"f\"}",
      "Cargo.toml": "[workspace]\nmembers = []\n",
    }
    let (found, problems) = Packages.found(
      ~fallback="r",
      ~read=path => files->Dict.get(path),
      files->Dict.keysToArray,
    )
    expect(problems)->toEqual([])
    expect(found->Array.map(p => (p.directory, p.manifests->Array.length)))->toEqual([
      ("", 1),
      ("code/a", 2),
    ])
  })
})

describe("the plan's line", () => {
  test("counts the patches past the last Release", () => {
    expect(Released.said(~main=(0, 1, 9), ~last=Some(((0, 1, 4), "2026.10.27"))))->toBe(
      "monoflake/driver main is 0.1.9, 5 patches past Release 0.1.4 (2026.10.27)",
    )
    expect(Released.said(~main=(0, 2, 1), ~last=Some(((0, 1, 4), "t"))))->toBe(
      "monoflake/driver main is 0.2.1, a minor and 1 patch past Release 0.1.4 (t)",
    )
  })

  test("takes the highest version the Releases list of the program", () => {
    let entry = (name, version, release) =>
      JSON.parseOrThrow(`{"name":"${name}","version":"${version}","release":"${release}"}`)
    expect(
      Released.lastOf([
        entry("other", "9.0.0", "x"),
        entry("driver-machine", "0.1.2", "a"),
        entry("driver-machine", "0.1.4", "b"),
        entry("driver-machine", "0.1.3", "c"),
      ]),
    )->toEqual(Some(((0, 1, 4), "b")))
  })
})

describe("bump arguments", () => {
  test("refuses a repository name absent from the registry", () => {
    let refused = try {
      Bump.chosen({dry: true, everything: false, minors: [], names: ["typo"]})->ignore
      false
    } catch {
    | Registry.Refused(_) => true
    }
    expect(refused)->toBe(true)
  })
})

describe("the update before rolling", () => {
  test("keeps every check part except versions", () => {
    expect(Repos.updateParts()->Array.includes("versions"))->toBe(false)
    expect(Repos.updateParts())->toEqual(
      ["rules", ...Check.known->Array.filter(name => name != "versions")],
    )
    expect(Check.known->Array.includes("versions"))->toBe(true)
  })
})

describe("a sibling checkout", () => {
  let root = temporaryRoot("beside-")
  test("takes the declared pin only for its sibling", () => {
    let root = root.contents
    let pin = "1234567890123456789012345678901234567890"
    tree(
      root,
      [
        ("workspace.toml", "[versions]\nrepository = \"../platform\"\npin = \"pin.yml\"\n"),
        ("pin.yml", `ref: ${pin} # monoflake/platform@main\n`),
      ],
    )
    expect(Beside.reference(~root, ~sibling=Node.resolve([root, "../platform"])))->toBe(pin)
    expect(Beside.reference(~root, ~sibling=Node.resolve([root, "../other"])))->toBe("main")
    expect(Beside.reference(~root=Node.join([root, "absent"]), ~sibling="/other"))->toBe("main")
  })
  test("a path cycle visits every directory once", () => {
    let root = root.contents
    let sibling = Node.join([root, "platform"])
    tree(
      root,
      [
        ("a/Cargo.toml", "b = { path = \"../b\" }\n"),
        ("b/Cargo.toml", "a = { path = \"../a\" }\nlib = { path = \"../platform/lib\" }\n"),
        ("platform/lib/Cargo.toml", "a = { path = \"../../a\" }\n"),
      ],
    )
    expect(Packages.siblingCrates(~root, ~sibling, ["a"]))->toEqual(["lib"])
  })
})
