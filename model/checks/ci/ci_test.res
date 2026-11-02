open Testing

let documents = (text, ~action=false) => [
  {Runs.file: "w.yml", action, jobs: Runs.read(text, ~action)},
]

let workflow = (~runsOn, steps) =>
  `jobs:
  build:
    runs-on: ${runsOn}
    steps:
${steps}`

describe("the cargo cache rule", () => {
  let cargo = "      - run: cargo test\n"
  let cached = "      - uses: Swatinem/rust-cache@d1527c8f67ef9af357290475d4af4b0fab8f12e0 # v2.9.3\n"
  test("holds a hosted job running cargo to rust-cache, a self-hosted one exempt", () => {
    expect(Caches.rustCacheProblems(documents(workflow(~runsOn="ubuntu-24.04", cargo))))->toEqual([
      "w.yml: job build runs cargo on a hosted runner without Swatinem/rust-cache",
    ])
    expect(
      Caches.rustCacheProblems(documents(workflow(~runsOn="ubuntu-24.04", cached ++ cargo))),
    )->toEqual([])
    expect(
      Caches.rustCacheProblems(documents(workflow(~runsOn="[self-hosted, ARM64]", cargo))),
    )->toEqual([])
    expect(
      Caches.rustCacheProblems(
        documents(workflow(~runsOn="ubuntu-24.04", "      - run: mise run rust:test\n")),
      ),
    )->toEqual(["w.yml: job build runs cargo on a hosted runner without Swatinem/rust-cache"])
  })
})

describe("the runner cache rule", () => {
  let cache = "      - uses: actions/cache@v4\n"
  test("refuses a GitHub cache on a self-hosted job and allows it on a hosted one", () => {
    expect(
      Caches.runnerProblems(documents(workflow(~runsOn="[self-hosted, ARM64]", cache))),
    )->toEqual(["w.yml: job build keeps actions/cache@v4 on a self-hosted runner"])
    expect(Caches.runnerProblems(documents(workflow(~runsOn="ubuntu-24.04", cache))))->toEqual([])
  })

  test("holds mise-action to following the runner in an action and a self-hosted job", () => {
    let mise = "      - uses: jdx/mise-action@v5\n"
    let off = "      - uses: jdx/mise-action@v5\n        with:\n          cache: false\n"
    let follows = "      - uses: jdx/mise-action@v5\n        with:\n          cache: ${{ runner.environment == 'github-hosted' }}\n"
    expect(Caches.runnerProblems(documents(workflow(~runsOn="[self-hosted]", mise))))->toEqual([
      "w.yml: job build keeps jdx/mise-action@v5 on a self-hosted runner",
    ])
    expect(Caches.runnerProblems(documents(workflow(~runsOn="[self-hosted]", off))))->toEqual([])
    let action = `runs:\n  using: composite\n  steps:\n${mise}`
    expect(Caches.runnerProblems(documents(action, ~action=true)))->toEqual([
      "w.yml: jdx/mise-action@v5 caches without following the runner",
    ])
    let followed = `runs:\n  using: composite\n  steps:\n${follows}`
    expect(Caches.runnerProblems(documents(followed, ~action=true)))->toEqual([])
  })
})

describe("the workflow shell rules", () => {
  let run = script =>
    documents(workflow(~runsOn="ubuntu-24.04", `      - name: Go\n        run: |\n${script}`))
  let indent = script =>
    script->String.split("\n")->Array.map(line => `          ${line}`)->Array.join("\n") ++ "\n"

  test("ci-native-steps refuses a step chaining entries and allows one entry twice", () => {
    expect(Entries.nativeProblems(run(indent("mise run build\nmise run test"))))->toEqual([
      "w.yml: job build step \"Go\" chains 2 entries, mise run build, mise run test",
    ])
    expect(
      Entries.nativeProblems(
        run(indent("if x; then\n  mise run ring a\nelse\n  mise run ring b\nfi")),
      ),
    )->toEqual([])
  })

  test("ci-entries refuses a command beyond entries and plumbing, once to a step", () => {
    expect(
      Entries.entryProblems(run(indent("grep -q x f\ngrep y g\necho ok\nmise run a"))),
    )->toEqual(["w.yml: job build step \"Go\" runs grep, which is no entry"])
    expect(
      Entries.entryProblems(
        run(indent("names=$(mise run list)\necho \"$names\" >> \"$GITHUB_OUTPUT\"")),
      ),
    )->toEqual([])
    expect(Entries.entryProblems(run(indent("(cd ../m && npx rescript build)"))))->toEqual([])
  })

  test("ci-shell-minimal allows one shot over many lines and plain preparation", () => {
    expect(
      Entries.shellProblems(run(indent("mise run build \\\n  --flag a \\\n  --flag b"))),
    )->toEqual([])
    expect(
      Entries.shellProblems(run(indent("mkdir -p out\nexport A=1\nmise run build"))),
    )->toEqual([])
    expect(Entries.shellProblems(run(indent("sudo rm -f /etc/x"))))->toEqual([])
    expect(
      Entries.shellProblems(run(indent("${{ inputs.message || 'node scripts/m.res.mjs' }}"))),
    )->toEqual([])
    expect(Entries.shellProblems(run(indent("grep -E 'a|b' f"))))->toEqual([])
    expect(
      Entries.shellProblems(
        run(indent("names=$(mise run list)\necho \"$names\" >> \"$GITHUB_OUTPUT\"")),
      ),
    )->toEqual([])
  })

  test(
    "ci-shell-minimal refuses orchestration, a loop, a branch, a parse, a value, a sequence",
    () => {
      let says = kind => [`w.yml: job build step "Go" holds ${kind} in its shell`]
      expect(Entries.shellProblems(run(indent("for a in $LIST; do\n  mise run a\ndone"))))->toEqual(
        says("a loop"),
      )
      expect(Entries.shellProblems(run(indent("if a; then mise run a; fi"))))->toEqual(
        says("a branch"),
      )
      expect(Entries.shellProblems(run(indent("mise run list | grep x"))))->toEqual(says("a parse"))
      expect(Entries.shellProblems(run(indent("sed -i s/a/b/ f"))))->toEqual(says("a parse"))
      expect(Entries.shellProblems(run(indent("sleep 5"))))->toEqual(says("a retry"))
      expect(Entries.shellProblems(run(indent("x=$(mise run a)\nmise run b \"$x\""))))->toEqual(
        says("a value carried between commands"),
      )
      expect(Entries.shellProblems(run(indent("mise run a\nmise run b"))))->toEqual(
        says("several commands in sequence"),
      )
      expect(
        Entries.shellProblems(
          run(indent("if [ -n \"$n\" ]; then echo a=1; else echo a=0; fi >> \"$GITHUB_OUTPUT\"")),
        ),
      )->toEqual(says("a branch"))
    },
  )

  test("ci-shell-minimal reads composite actions", () => {
    let source = "runs:\n  steps:\n    - name: Go\n      run: |\n        mise run a\n        mise run b\n"
    let doc: Runs.document = {
      file: "a/action.yml",
      action: true,
      jobs: Runs.read(source, ~action=true),
    }
    expect(Entries.shellProblems([doc]))->toEqual([
      "a/action.yml: job action step \"Go\" holds several commands in sequence in its shell",
    ])
  })
})

describe("the crane rule", () => {
  test("refuses nixpkgs' Rust builder and passes crane's", () => {
    expect(Crane.problems("rustPlatform.buildRustPackage {}", ~file="p.nix"))->toEqual([
      "p.nix: builds Rust with buildRustPackage, which is not crane",
    ])
    expect(Crane.problems("craneLib.buildPackage {}", ~file="p.nix"))->toEqual([])
  })
})

describe("the custom domains rule", () => {
  test("wants both flags false at the top and refuses an env turning one on", () => {
    let read = text =>
      Wrangler.problems(Wrangler.read(text, ~file="wrangler.jsonc"), ~file="wrangler.jsonc")
    expect(read("{ \"workers_dev\": false, \"preview_urls\": false }"))->toEqual([])
    expect(read("{\n // note\n \"workers_dev\": false,\n \"preview_urls\": false,\n}"))->toEqual([])
    expect(read("{ \"workers_dev\": true, \"preview_urls\": false }"))->toEqual([
      "wrangler.jsonc: workers_dev is not false",
    ])
    expect(read("{ \"workers_dev\": false }"))->toEqual([
      "wrangler.jsonc: preview_urls is not false",
    ])
    expect(
      read(
        "{ \"workers_dev\": false, \"preview_urls\": false, \"env\": { \"a\": { \"workers_dev\": true } } }",
      ),
    )->toEqual(["wrangler.jsonc: env a turns workers_dev on"])
  })

  test("reads toml and passes a test's fixtures over", () => {
    expect(
      Wrangler.problems(
        Wrangler.read("workers_dev = false\npreview_urls = false", ~file="wrangler.toml"),
        ~file="wrangler.toml",
      ),
    )->toEqual([])
    expect(Wrangler.fixture("platform/tests/fixtures/wrangler.json"))->toBe(true)
    expect(Wrangler.fixture("driver/cloudflare/wrangler.json"))->toBe(false)
  })
})
