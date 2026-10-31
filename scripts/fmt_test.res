open Testing

let root = ref("")
beforeEach(() => root := Node.mkdtempSync(Node.join([Node.tmpdir(), "fmt-test-"])))
afterEach(() => Node.run("trash", [root.contents])->ignore)

let write = files => tree(root.contents, files)
let names = commands => commands->Array.map(({Fmt.program: program}) => program)

describe("the shared repository formatter", () => {
  test("keeps existing callers' default glob and Cargo detection", () => {
    expect(Fmt.commands(root.contents, [], ~dry=false))->toEqual([
      {Fmt.program: "oxfmt", args: ["--no-error-on-unmatched-pattern", Fmt.defaultGlob]},
    ])
    write([("Cargo.toml", "")])
    expect(Fmt.commands(root.contents, [], ~dry=false)->names)->toEqual(["cargo", "oxfmt"])
    expect(Fmt.commands(root.contents, [], ~dry=true)->Array.getUnsafe(0))->toEqual({
      Fmt.program: "cargo",
      args: ["fmt", "--all", "--check", "--message-format", "short"],
    })
  })

  test("keeps each declared oxfmt pattern without absorbing other options", () => {
    let args = ["--rescript", "--glob", "*.md", "*.json", "docs/**/*.md", "--nixfmt", "."]
    let commands = Fmt.commands(root.contents, args, ~dry=true)
    expect(commands)->toEqual([
      {Fmt.program: "rescript", args: ["format", "--check"]},
      {
        program: "oxfmt",
        args: [
          "--list-different",
          "--no-error-on-unmatched-pattern",
          "*.md",
          "*.json",
          "docs/**/*.md",
        ],
      },
    ])
    expect(Fmt.values(["--glob", "*.md", "--rescript", "--glob", "*.json"], "--glob"))->toEqual([
      "*.md",
      "*.json",
    ])
  })

  test("a live failure stops later formatters and keeps the failing status", () => {
    write([("Cargo.toml", "")])
    let called = []
    let status = Fmt.format(
      ~root=root.contents,
      ~args=["--rescript"],
      ~dry=false,
      ~run=command => {
        called->Array.push(command.program)
        command.program == "cargo" ? 7 : 0
      },
    )
    expect((status, called))->toEqual((7, ["rescript", "cargo"]))
  })

  test("a dry run reports every formatter and succeeds after findings", () => {
    write([("Cargo.toml", "")])
    let called = []
    let status = Fmt.format(
      ~root=root.contents,
      ~args=["--rescript"],
      ~dry=true,
      ~run=command => {
        called->Array.push(command.program)
        1
      },
    )
    expect((status, called))->toEqual((0, ["rescript", "cargo", "oxfmt"]))
  })

  test("the CLI's dry flags report real formatter findings without changing files", () => {
    let files = [
      (
        "Cargo.toml",
        "[package]\nname = \"fmt-fixture\"\nversion = \"0.0.0\"\nedition = \"2024\"\n[workspace]\n",
      ),
      ("src/lib.rs", "pub fn value( )->u32{1}\n"),
      ("rescript.json", "{\"name\":\"fmt-fixture\",\"sources\":[\"src\"]}\n"),
      ("src/value.res", "let   value =   1\n"),
    ]
    write(files)
    let script = Node.resolve(["scripts/fmt.res.mjs"])
    ["--dry-run", "-n"]->Array.forEach(
      flag => {
        let result = Node.spawnSync(
          "node",
          [script, "--rescript", "--glob", "*.json", flag],
          {
            cwd: root.contents,
            encoding: "utf8",
          },
        )
        expect(result.status->Nullable.toOption)->toEqual(Some(0))
        let output = result.stdout->Nullable.getOr("") ++ result.stderr->Nullable.getOr("")
        expect(output)->toContain("value.res")
        expect(output)->toContain("lib.rs")
        expect(output)->toContain("rescript.json")
        files->Array.forEach(
          ((path, original)) =>
            expect(Node.readFileSync(Node.join([root.contents, path])))->toBe(original),
        )
      },
    )
    let environment = Node.envCopy(Node.env)
    environment->Dict.set("usage_dry_run", "true")
    expect(
      Node.spawnWithEnv(
        "node",
        [script, "--rescript", "--glob", "*.json"],
        {
          cwd: root.contents,
          env: environment,
        },
      ).status->Nullable.toOption,
    )->toEqual(Some(0))
    files->Array.forEach(
      ((path, original)) =>
        expect(Node.readFileSync(Node.join([root.contents, path])))->toBe(original),
    )
  })

  test("machine's Nix selection stays inside its four declared locations", () => {
    write([
      ("flake.nix", "{}"),
      ("system/nested/module.nix", "{}"),
      ("local/module.nix", "{}"),
      (".github/runner/flake.nix", "{}"),
      ("elsewhere/module.nix", "{}"),
    ])
    let jobs = Fmt.nix(
      root.contents,
      [
        "--nixfmt",
        ".",
        "--nix-files",
        "flake.nix",
        "system/**/*.nix",
        "local/**/*.nix",
        ".github/**/*.nix",
      ],
    )
    expect(jobs)->toEqual([
      {
        Fmt.flake: root.contents,
        files: [
          ".github/runner/flake.nix",
          "flake.nix",
          "local/module.nix",
          "system/nested/module.nix",
        ],
      },
    ])
  })

  test("cloud keeps each machine and planned pin and uses the first machine for cache", () => {
    write([
      ("machines/one/flake.nix", "{}"),
      ("machines/one/nested/ignored.nix", "{}"),
      ("planned/two/flake.nix", "{}"),
      ("cache/cache.nix", "{}"),
      (".github/runner/flake.nix", "{}"),
    ])
    expect(
      Fmt.nix(root.contents, ["--nixfmt", "machines/*", "planned/*", "--nix-extra", "cache/*.nix"]),
    )->toEqual([
      {
        Fmt.flake: Node.join([root.contents, "machines/one"]),
        files: ["machines/one/flake.nix", "cache/cache.nix"],
      },
      {flake: Node.join([root.contents, "planned/two"]), files: ["planned/two/flake.nix"]},
    ])
    expect(Fmt.nix(root.contents, ["--nixfmt", "missing/*"]))->toEqual([])
  })

  test("nixfmt checks a copied pin and leaves the repository untouched in a dry run", () => {
    write([("flake.nix", "{}"), ("flake.lock", "pin"), ("module.nix", "{  }\n")])
    let copies = []
    let jobs = Fmt.nix(root.contents, ["--nixfmt", "."])
    let status = Fmt.formatNix(
      ~dry=true,
      jobs->Array.getUnsafe(0),
      ~run=command => {
        let copy = command.args->Array.getUnsafe(2)->String.slice(~start=5)
        copies->Array.push(copy)
        expect(Node.readFileSync(Node.join([copy, "flake.lock"])))->toBe("pin")
        expect(Node.readdir(copy)->Array.toSorted(String.compare))->toEqual([
          "flake.lock",
          "flake.nix",
        ])
        expect(command.program)->toBe("nix")
        expect(command.args->Array.slice(~start=3))->toEqual([
          "nixpkgs#nixfmt",
          "--",
          "--check",
          "flake.nix",
          "module.nix",
        ])
        1
      },
    )
    expect(status)->toBe(1)
    expect(Node.existsSync(copies->Array.getUnsafe(0)))->toBe(false)
    expect(Node.readFileSync(Node.join([root.contents, "module.nix"])))->toBe("{  }\n")
    expect(Node.readdir(root.contents)->Array.toSorted(String.compare))->toEqual([
      "flake.lock",
      "flake.nix",
      "module.nix",
    ])
  })

  test("live nixfmt omits check mode and a dry run continues after its finding", () => {
    write([
      ("one/flake.nix", "{}"),
      ("one/flake.lock", "one"),
      ("two/flake.nix", "{}"),
      ("two/flake.lock", "two"),
    ])
    let called = []
    let run = (command: Fmt.command) => {
      called->Array.push(command)
      command.program == "nix" ? 3 : 0
    }
    expect(
      Fmt.format(~root=root.contents, ~args=["--nixfmt", "one", "two"], ~dry=false, ~run),
    )->toBe(3)
    expect(called->names)->toEqual(["oxfmt", "nix"])
    let liveNix = called->Array.getUnsafe(1)
    expect(liveNix.args->Array.includes("--check"))->toBe(false)
    let dryCalls = []
    expect(
      Fmt.format(
        ~root=root.contents,
        ~args=["--nixfmt", "one", "two"],
        ~dry=true,
        ~run=command => {
          dryCalls->Array.push(command.program)
          3
        },
      ),
    )->toBe(0)
    expect(dryCalls)->toEqual(["oxfmt", "nix", "nix"])
  })
})
