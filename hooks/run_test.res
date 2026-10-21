open Testing

let root = Registry.root
let entry = Node.join([root, "hooks", "run.res.mjs"])

/** What both adapters run, walking up to the checkout with hooks/ and building it if need be. */
let command = `d=$(jj workspace root 2>/dev/null || pwd); while [ ! -f "$d/hooks/run.res" ] && [ "$d" != / ]; do d=$(dirname "$d"); done; [ -f "$d/hooks/run.res" ] || exit 0; e="$d/hooks/run.res.mjs"; r="$d/node_modules/.bin/rescript"; [ -f "$e" ] || { "$r" build >&2; [ -f "$e" ] || { "$r" clean >&2; "$r" build >&2; }; }; [ -f "$e" ] || { echo "hooks: $e is not built and building did not make it; run mise run build in $d" >&2; exit 1; }; exec node "$e"`

type adapter = {hooks: Dict.t<array<{"hooks": array<{"command": string}>}>>}
@scope("JSON") @val external parseAdapter: string => adapter = "parse"

let invoke = (~cwd=root, ~through=false, payload: string) => {
  let result = through
    ? Node.spawnSync(
        "/bin/sh",
        ["-c", command],
        {cwd, input: payload, encoding: "utf8", timeout: 20000},
      )
    : Node.spawnSync("node", [entry], {cwd, input: payload, encoding: "utf8", timeout: 20000})
  (
    result.status->Nullable.getOr(-1),
    result.stdout->Nullable.getOr(""),
    result.stderr->Nullable.getOr(""),
  )
}

let post = cwd =>
  JSON.stringifyAny({
    "cwd": cwd,
    "hook_event_name": "PostToolUse",
    "tool_name": "Bash",
    "tool_input": {"command": "pwd"},
  })->Option.getOr("{}")

describe("the shared entrypoint", () => {
  test("both vendor adapters are identical and run the one command", () => {
    let claude = parseAdapter(Node.readFileSync(Node.join([root, ".claude", "settings.json"])))
    let codex = parseAdapter(Node.readFileSync(Node.join([root, ".codex", "hooks.json"])))
    expect(claude.hooks)->toEqual(codex.hooks)
    codex.hooks
    ->Dict.valuesToArray
    ->Array.forEach(
      groups =>
        groups->Array.forEach(
          group => {
            expect(group["hooks"]->Array.length)->toBe(1)
            let first = group["hooks"]->Array.getUnsafe(0)
            expect(first["command"])->toBe(command)
          },
        ),
    )
  })

  test("a post-tool payload with nothing to say is silent", () => {
    expect(invoke(post(root)))->toEqual((0, "", ""))
  })

  test(
    "the adapter command resolves from a subdirectory and from inside a nested repository",
    () => {
      let docs = Node.join([root, "docs"])
      expect(invoke(~cwd=docs, ~through=true, post(docs)))->toEqual((0, "", ""))
      // The case the walk exists for, where jj answers about the project and not this repository.
      Registry.paths()
      ->Array.map(path => Node.join([Registry.repos, path]))
      ->Array.find(path => Node.existsSync(Node.join([path, ".jj"])))
      ->Option.forEach(
        nested => expect(invoke(~cwd=nested, ~through=true, post(nested)))->toEqual((0, "", "")),
      )
    },
  )

  test("outside any repository there is nothing to run, and no hang", () => {
    let (status, _, _) = invoke(~cwd=Node.tmpdir(), ~through=true, "{}")
    expect(status)->toBe(0)
  })

  test("a pre-tool rejection keeps the exit contract", () => {
    let (status, _, stderr) = invoke(
      JSON.stringifyAny({
        "cwd": root,
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": "jj commit -m 'Not conventional'"},
      })->Option.getOr("{}"),
    )
    expect(status)->toBe(2)
    expect(stderr)->toContain("Commit message rejected")
  })

  test("a second stop is let through in silence", () => {
    expect(
      invoke(
        JSON.stringifyAny({
          "cwd": root,
          "hook_event_name": "Stop",
          "stop_hook_active": true,
        })->Option.getOr("{}"),
      ),
    )->toEqual((0, "", ""))
  })

  test("post-tool observations are one context", () => {
    expect(Run.combined([Some("first"), None, Some("second")]))->toEqual(Some("first\n\nsecond"))
    expect(Run.combined([None, None]))->toEqual(None)
  })
})

describe("a jj command inside a shell line", () => {
  test("is found past assignments, global options and separators", () => {
    expect(Jj_command.invocations("FOO=1 jj --no-pager -R . commit -m \"a b\""))->toEqual([
      ("commit", ["-m", "a b"]),
    ])
    expect(Jj_command.invocations("cd a && jj describe -m 'fix: y' | cat"))->toEqual([
      ("describe", ["-m", "fix: y"]),
    ])
    expect(Jj_command.invocations("echo jj commit -m x"))->toEqual([])
  })

  test("a quote left open is no command at all", () => {
    expect(Jj_command.invocations("jj commit -m 'open"))->toEqual([])
  })
})
