open Testing

@module("node:fs") external symlinkSync: (string, string) => unit = "symlinkSync"

let root = Registry.root
let entry = Node.join([root, "hooks", "run.res.mjs"])

/** What both adapters run, walking up to the checkout with hooks/, building it if it can, else a
 * lane falling back to its main checkout's; nothing built fails a pre-tool call closed. */
let command = fail =>
  `d=$(jj workspace root 2>/dev/null || pwd); while [ ! -f "$d/hooks/run.res" ] && [ "$d" != / ]; do d=$(dirname "$d"); done; [ -f "$d/hooks/run.res" ] || exit 0; e="$d/hooks/run.res.mjs"; r="$d/node_modules/.bin/rescript"; if [ ! -f "$e" ] && [ -x "$r" ]; then "$r" build >&2; [ -f "$e" ] || { "$r" clean >&2; "$r" build >&2; }; fi; if [ ! -f "$e" ] && [ -f "$d/.jj/repo" ]; then m=$(cd "$d/.jj" && cd "$(cat repo)/../.." && pwd); [ -f "$m/hooks/run.res.mjs" ] && e="$m/hooks/run.res.mjs"; fi; [ -f "$e" ] || { echo "hooks: $e is not built and building did not make it; run mise run build in $d" >&2; exit ${fail}; }; exec node "$e"`

type adapter = {hooks: Dict.t<array<{"hooks": array<{"command": string}>}>>}
@scope("JSON") @val external parseAdapter: string => adapter = "parse"

let invoke = (~cwd=root, ~through=false, ~fail="2", payload: string) => {
  let result = through
    ? Node.spawnSync(
        "/bin/sh",
        ["-c", command(fail)],
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
  let isolated = run => {
    let directory = Node.mkdtempSync(Node.join([Node.tmpdir(), "compact-role-"]))
    let keys = ["RUNS_HOME", "THREADS_HOME", "XDG_CACHE_HOME"]
    let previous = keys->Array.map(key => (key, Node.env->Dict.get(key)))
    keys->Array.forEach(key => Node.env->Dict.set(key, directory))
    let clean = () => {
      previous->Array.forEach(((key, value)) =>
        switch value {
        | Some(value) => Node.env->Dict.set(key, value)
        | None => Node.env->Dict.delete(key)
        }
      )
      Node.rmSync(directory, {recursive: true, force: true})
    }
    try {
      run(directory)
      clean()
    } catch {
    | error =>
      clean()
      throw(error)
    }
  }
  let compact = (~source="compact", ~transcript="/registered.jsonl") =>
    dict{
      "hook_event_name": JSON.String("SessionStart"),
      "source": JSON.String(source),
      "transcript_path": JSON.String(transcript),
    }

  test("a registered transcript recovers its role and thread files after compaction", () => {
    isolated(
      _ => {
        Ledger.registerSession(~role="advisor", ~name="other", ~transcript=Some("/other.jsonl"))
        Ledger.registerSession(
          ~role="supervisor",
          ~name="flow",
          ~transcript=Some("/registered.jsonl"),
          ~thread=Some("trial"),
        )
        let identity = `You are supervisor flow of thread trial; its files are in ${Figures.directory(
            "trial",
          )}; read status.md, then your role's file.`
        expect(Run.opening(compact()))->toBe(`${Run.afterCompaction}\n\n${identity}`)
        let (status, stdout, stderr) = invoke(JSON.stringify(JSON.Object(compact())))
        expect(status)->toBe(0)
        expect(stderr)->toBe("")
        expect(
          Payload.parse(stdout)
          ->Option.flatMap(fields => fields->Payload.object("hookSpecificOutput"))
          ->Option.flatMap(fields => fields->Payload.text("additionalContext")),
        )->toEqual(Some(`${Run.afterCompaction}\n\n${identity}`))
      },
    )
  })

  test("a registered session without a thread recovers its role and name alone", () => {
    isolated(
      _ => {
        Ledger.registerSession(
          ~role="integrator",
          ~name="base",
          ~transcript=Some("/registered.jsonl"),
        )
        expect(Run.opening(compact()))->toBe(`${Run.afterCompaction}\n\nYou are integrator base.`)
        expect(Run.opening(compact(~source="startup")))->toBe("")
      },
    )
  })

  test("an unregistered or missing transcript keeps the existing compaction text", () => {
    isolated(
      _ => {
        Ledger.registerSession(~role="seat", ~name="blind", ~transcript=None)
        expect(Run.opening(compact()))->toBe(Run.afterCompaction)
        expect(Run.opening(dict{"source": JSON.String("compact")}))->toBe(Run.afterCompaction)
      },
    )
  })

  test("a broken registry leaves the existing context and reminder unchanged", () => {
    isolated(
      _ => {
        let cache = Reminder.directory()
        Node.mkdirAll(cache)
        Node.writeFileSync(
          Node.join([cache, "summary.json"]),
          JSON.stringifyAny({
            "items": [
              {
                "item": Reminder.item(~repository="workspace", "action", "sample", "1", "2"),
                "firstSeen": "2026-01-01",
              },
            ],
          })->Option.getOr("{}"),
        )
        let expected = `${Run.afterCompaction}\n\n${Reminder.line()}`
        expect(Reminder.line() != "")->toBe(true)
        Node.mkdirAll(Ledger.sessions())
        Node.writeFileSync(Node.join([Ledger.sessions(), "broken.json"]), "{broken")
        expect(Run.opening(compact()))->toBe(expected)
        Node.rmSync(Ledger.sessions(), {recursive: true, force: true})
        Node.writeFileSync(Ledger.sessions(), "not a directory")
        expect(Run.opening(compact()))->toBe(expected)
      },
    )
  })

  test("a session started by a compaction is told what to read again", () => {
    let (status, stdout, _) = invoke(
      JSON.stringifyAny({
        "cwd": root,
        "hook_event_name": "SessionStart",
        "source": "compact",
      })->Option.getOr("{}"),
    )
    expect(status)->toBe(0)
    expect(stdout)->toContain("Your context was compacted")
    expect(stdout)->toContain("docs/voice.md")
    let (_, fresh, _) = invoke(
      JSON.stringifyAny({
        "cwd": root,
        "hook_event_name": "SessionStart",
        "source": "startup",
      })->Option.getOr("{}"),
    )
    expect(fresh->String.includes("Your context was compacted"))->toBe(false)
  })

  test("SessionStart provides the reminder as context and is silent without it", () => {
    expect(Run.session(""))->toEqual(None)
    expect(Run.session("1 action; mise run update --dry-run for detail"))->toEqual(
      Some(
        JSON.Object(
          Dict.fromArray([
            (
              "hookSpecificOutput",
              JSON.Object(
                Dict.fromArray([
                  ("hookEventName", JSON.String("SessionStart")),
                  (
                    "additionalContext",
                    JSON.String("1 action; mise run update --dry-run for detail"),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    )
  })
  test("both vendor adapters are identical and run the one command", () => {
    // SendMessage is Claude's tool alone, so its matcher names it and Codex's does not.
    let claude = parseAdapter(
      Node.readFileSync(Node.join([root, ".claude", "settings.json"]))->String.replace(
        "|SendMessage",
        "",
      ),
    )
    let codex = parseAdapter(Node.readFileSync(Node.join([root, ".codex", "hooks.json"])))
    expect(claude.hooks)->toEqual(codex.hooks)
    codex.hooks
    ->Dict.toArray
    ->Array.forEach(
      ((event, groups)) =>
        groups->Array.forEach(
          group => {
            expect(group["hooks"]->Array.length)->toBe(1)
            let first = group["hooks"]->Array.getUnsafe(0)
            expect(first["command"])->toBe(command(event == "PreToolUse" ? "2" : "1"))
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

  test(
    "a lane without its own build runs its main checkout's hooks, and nothing built fails closed",
    () => {
      let lane = Node.mkdtempSync(Node.join([Node.tmpdir(), "hook-lane-"]))
      Node.mkdirAll(Node.join([lane, "hooks"]))
      Node.mkdirAll(Node.join([lane, ".jj"]))
      Node.writeFileSync(Node.join([lane, "hooks", "run.res"]), "")
      // A main checkout of its own, its hooks this tree's, so no real .jj is read.
      let main = Node.mkdtempSync(Node.join([Node.tmpdir(), "hook-main-"]))
      Node.mkdirAll(Node.join([main, ".jj", "repo"]))
      symlinkSync(Node.join([root, "hooks"]), Node.join([main, "hooks"]))
      let repository = Node.join([main, ".jj", "repo"])
      Node.writeFileSync(Node.join([lane, ".jj", "repo"]), repository)
      let rejected = JSON.stringifyAny({
        "cwd": root,
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": "jj commit -m 'Not conventional'"},
      })->Option.getOr("{}")
      let (status, _, stderr) = invoke(~cwd=lane, ~through=true, rejected)
      expect(status)->toBe(2)
      expect(stderr)->toContain("Commit message rejected")
      Node.writeFileSync(
        Node.join([lane, ".jj", "repo"]),
        Node.join([lane, "nowhere", ".jj", "repo"]),
      )
      let (status, _, _) = invoke(~cwd=lane, ~through=true, rejected)
      expect(status)->toBe(2)
      let (status, _, _) = invoke(~cwd=lane, ~through=true, ~fail="1", "{}")
      expect(status)->toBe(1)
      Node.rmSync(lane, {recursive: true, force: true})
      Node.rmSync(main, {recursive: true, force: true})
    },
  )

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

  test("each event shape exits as designed, never throws and prints only valid JSON", () => {
    let cwd = JSON.stringifyAny(root)->Option.getOr("\"\"")
    let event = (name, rest) => `{"cwd": ${cwd}, "hook_event_name": "${name}"${rest}}`
    let bash = `, "tool_name": "Bash", "tool_input": {"command": "echo hello"}`
    let shapes = [
      ("a pre-tool Bash call", event("PreToolUse", bash)),
      ("a post-tool call", event("PostToolUse", bash)),
      ("a stop", event("Stop", "")),
      ("a session start", event("SessionStart", `, "source": "startup"`)),
      ("an unknown event", event("Unheard", "")),
      ("an empty payload", ""),
      ("an empty object", "{}"),
      ("a malformed payload", "{not json"),
      ("a payload that is no object", "[1, 2]"),
    ]
    let valid = text =>
      try {
        JSON.parseOrThrow(text)->ignore
        true
      } catch {
      | _ => false
      }
    shapes->Array.forEach(
      ((shape, payload)) => {
        let (status, stdout, stderr) = invoke(payload)
        expect((shape, status))->toEqual((shape, 0))
        expect((shape, stderr->String.includes("Error")))->toEqual((shape, false))
        expect((shape, stdout == "" || valid(stdout)))->toEqual((shape, true))
      },
    )
    // Where it should speak it does: a compaction is told what to read again.
    let (_, spoken, _) = invoke(event("SessionStart", `, "source": "compact"`))
    expect(spoken != "" && valid(spoken))->toBe(true)
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
    expect(Jj_command.invocations("true;jj commit -m x"))->toEqual([("commit", ["-m", "x"])])
    expect(Jj_command.invocations("a 2>&1|b&&jj new; echo 'x;y'"))->toEqual([("new", [])])
  })

  test("a quote left open is no command at all", () => {
    expect(Jj_command.invocations("jj commit -m 'open"))->toEqual([])
  })

  test("keeps a message after a command substitution and finds the inner invocation", () => {
    expect(
      Jj_command.invocations(
        "cd /x && jj commit $(jj diff --name-only | grep flake.lock) -m 'build: update lock' 2>&1 | tail -1",
      ),
    )->toEqual([
      ("commit", ["$(jj diff --name-only | grep flake.lock)", "-m", "build: update lock", "2>&1"]),
      ("diff", ["--name-only"]),
    ])
  })

  test("checks the subject width after a command substitution", () => {
    [96, 97]->Array.forEach(
      width => {
        let message = "build: " ++ "a"->String.repeat(width - 7)
        let command = `cd /x && jj commit $(jj diff --name-only | grep flake.lock) -m '${message}' 2>&1 | tail -1`
        let payload =
          Payload.parse(
            JSON.stringifyAny({"tool_input": {"command": command}})->Option.getOr("{}"),
          )->Option.getOrThrow
        expect(Commit.messages(command))->toEqual([message])
        expect(Commit.refuse(payload))->toBe(width == 96 ? 0 : 2)
      },
    )
  })

  test("keeps separators inside substitutions within their containing word", () => {
    ["|", "&&", ";"]->Array.forEach(
      separator => {
        let inner = `jj diff ${separator} jj log`
        ["$(" ++ inner ++ ")", "`" ++ inner ++ "`"]->Array.forEach(
          span => {
            let word = "before" ++ span ++ "after"
            expect(Jj_command.words(`jj commit ${word} -m 'fix: x' | cat`))->toEqual(
              Some(["jj", "commit", word, "-m", "fix: x", "|", "cat"]),
            )
            expect(Jj_command.invocations(`jj commit ${word} -m 'fix: x' | cat`))->toEqual([
              ("commit", [word, "-m", "fix: x"]),
              ("diff", []),
              ("log", []),
            ])
          },
        )
      },
    )
  })

  test("balances nested substitutions and plain parentheses", () => {
    let nested = "$(echo $(jj diff | cat) && jj log)"
    expect(Jj_command.invocations(`jj commit ${nested} -m 'fix: x'`))->toEqual([
      ("commit", [nested, "-m", "fix: x"]),
      ("log", []),
      ("diff", []),
    ])
    let grouped = "$( (echo x) | cat)"
    expect(Jj_command.words(`jj commit ${grouped} -m 'fix: x'`))->toEqual(
      Some(["jj", "commit", grouped, "-m", "fix: x"]),
    )
  })

  test("respects quotes inside a substitution and keeps finding inner commands", () => {
    ["'", "\""]->Array.forEach(
      quote => {
        let span = "$(echo " ++ quote ++ ") | && ; (" ++ quote ++ "; jj diff)"
        expect(Jj_command.invocations(`jj commit ${span} -m 'fix: x'`))->toEqual([
          ("commit", [span, "-m", "fix: x"]),
          ("diff", []),
        ])
      },
    )
    let nested = "$(echo \"$(echo ')'; jj diff)\"; jj log)"
    expect(Jj_command.invocations(`jj commit "${nested}" -m 'fix: x'`))->toEqual([
      ("commit", [nested, "-m", "fix: x"]),
      ("log", []),
      ("diff", []),
    ])
  })

  test("keeps escaped delimiters inside substitutions", () => {
    ["$(echo \\) | jj diff)", "`echo \\` | jj diff`"]->Array.forEach(
      span =>
        expect(Jj_command.invocations(`jj commit ${span} -m 'fix: x'`))->toEqual([
          ("commit", [span, "-m", "fix: x"]),
          ("diff", []),
        ]),
    )
  })

  test("leaves quoted and escaped substitution openers literal", () => {
    expect(Jj_command.words("jj commit '$(jj diff | cat)' -m 'fix: x'"))->toEqual(
      Some(["jj", "commit", "$(jj diff | cat)", "-m", "fix: x"]),
    )
    expect(Jj_command.invocations("echo '$(jj diff)' '`jj log`'"))->toEqual([])
    expect(Jj_command.words("echo \\$(open \\`open"))->toEqual(Some(["echo", "$(open", "`open"]))
  })

  test("an open substitution or inner quote is no command at all", () => {
    [
      "jj commit $(jj diff | cat -m 'fix: x'",
      "jj commit $(echo $(jj diff) -m 'fix: x'",
      "jj commit \"$(jj diff\" -m 'fix: x'",
      "jj commit $(echo ') -m 'fix: x'",
      "jj commit `jj diff -m 'fix: x'",
      "jj commit $(jj diff) -m 'open",
    ]->Array.forEach(
      command => {
        expect(Jj_command.words(command))->toEqual(None)
        expect(Jj_command.invocations(command))->toEqual([])
      },
    )
  })
})

describe("a command a job is given", () => {
  let payload = command =>
    Dict.fromArray([
      ("tool_name", JSON.String("Bash")),
      ("tool_input", JSON.Object(Dict.fromArray([("command", JSON.String(command))]))),
    ])

  test("meets the gates it would meet typed by itself, in any prefixed form", () => {
    [
      "mise run //:job start -- pkill node",
      "FOO=1 mise run //:job start -- pkill node",
      "(mise run //:job start -- pkill node)",
      "timeout 60 mise run //:job start -- jj git push",
      "mise run //:job start -- rm -rf $D/x",
      "KEY='a b' mise run //:job start pkill x",
      "KEY='a b' mise run //:job start jj git push",
      "mise run //:job start -- jj commit -m 'Bad subject'",
      `mise run //:job start -- sh -c 'jj commit -m "Bad subject"'`,
      `mise run //:job start -- bash -lc 'cd x && jj commit -m "Bad subject"'`,
    ]->Array.forEach(
      command =>
        expect((command, Run.refusedInJob(payload(command)) != 0))->toEqual((command, true)),
    )
  })

  test("a shell's line is read for a commit's message, the trailer's spelling included", () => {
    let wrong = "fix: x\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
    let line = `sh -c 'jj commit -m "${wrong}"'`
    expect(Commit.messages(line))->toEqual([wrong])
    expect(Commit.refuse(payload(line)))->toBe(2)
    expect(Run.refusedInJob(payload(`mise run //:job start -- ${line}`)))->toBe(2)
    expect(Commit.refuse(payload(`sh -c 'jj commit -m "fix: x"'`)))->toBe(0)
  })

  test("keeps its quoting, so what only names a thing passes", () => {
    [
      "mise run //:job start -- rg 'a; pkill b' docs",
      "mise run //:job start -- mise run check",
      "mise run //:job start -- 'sleep 9 & P=$!; kill $P'",
      "ls",
    ]->Array.forEach(
      command => expect((command, Run.refusedInJob(payload(command))))->toEqual((command, 0)),
    )
  })
})
