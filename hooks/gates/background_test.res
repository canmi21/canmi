open Testing

let payload = (~background=false, ~timeout=?, ~tool=?, command): Payload.t => {
  let input = Dict.fromArray([
    ("command", JSON.String(command)),
    ("run_in_background", JSON.Boolean(background)),
  ])
  timeout->Option.forEach(ms => input->Dict.set("timeout", JSON.Number(ms)))
  let fields = Dict.fromArray([("tool_input", JSON.Object(input))])
  tool->Option.forEach(name => fields->Dict.set("tool_name", JSON.String(name)))
  fields
}

describe("a command that holds the conversation", () => {
  test("is a foreground loop that sleeps, however it is written", () => {
    expect(Background.polls("until grep -q done log; do sleep 5; done"))->toEqual(true)
    expect(Background.polls("while true; do s=$(gh run view 1); sleep 20; done"))->toEqual(true)
    expect(Background.polls("f=out; until [ -s $f ]\ndo\n  sleep 3\ndone\ncat $f"))->toEqual(true)
  })

  test("is not a loop without a sleep, a lone sleep, or a loop in a quoted here-document", () => {
    expect(Background.polls("while read -r line; do echo $line; done < list"))->toEqual(false)
    expect(Background.polls("for f in a b; do cat $f; done"))->toEqual(false)
    expect(Background.polls("sleep 2; cat out"))->toEqual(false)
    expect(
      Background.polls("python3 - <<'EOF'\nwhile x: do_it(); sleep(1)\ndone = 1\nEOF"),
    )->toEqual(false)
  })

  test("is refused in the foreground and passed in the background", () => {
    expect(Background.refuse(payload("until test -e f; do sleep 2; done")))->toEqual(2)
    expect(
      Background.refuse(payload(~background=true, "until test -e f; do sleep 2; done")),
    )->toEqual(0)
    expect(Background.refuse(payload("ls")))->toEqual(0)
  })

  test("refuses a Monitor following a job's output with tail, and passes the watcher", () => {
    let log = "/Users/a/.local/state/workspace/runs/outputs/20261111-093552-c53b.log"
    expect(
      Background.refuse(payload(~tool="Monitor", `tail -n +1 -f ${log} | grep --line-buffered x`)),
    )->toEqual(2)
    expect(Background.refuse(payload(~tool="Monitor", `tail -F ${log}`)))->toEqual(2)
    expect(
      Background.refuse(payload(~tool="Monitor", "mise run //:watch 20261111-093552-c53b")),
    )->toEqual(0)
    expect(
      Background.refuse(payload(~tool="Monitor", "tail -n 0 -F /Users/a/.local/state/runs/events")),
    )->toEqual(0)
    expect(Background.refuse(payload(`tail -5 ${log}`)))->toEqual(0)
  })

  test("runs a landing in the background and a push in the foreground, by the user's word", () => {
    expect(Background.refuse(payload("mise run land monoflake/console -m x")))->toEqual(2)
    expect(
      Background.refuse(payload(~background=true, "mise run land monoflake/console -m x")),
    )->toEqual(0)
    expect(Background.refuse(payload("mise run push monoflake/console")))->toEqual(0)
  })

  test("is passed when Monitor runs it, and refused when Bash does", () => {
    let command = "until grep -q 'exited with code' out.log; do sleep 3; done; cat out.log"
    expect(Background.refuse(payload(~tool="Monitor", command)))->toEqual(0)
    expect(Background.refuse(payload(~tool="Bash", command)))->toEqual(2)
    expect(Background.refuse(payload(command)))->toEqual(2)
  })

  test("recognizes Monitor arriving as Bash by its timeout_ms field", () => {
    let call = payload(~tool="Bash", "while true; do cat out.log; sleep 60; done")
    let input = call->Payload.object("tool_input")->Option.getOrThrow
    input->Dict.set("description", JSON.String("Watch the job output"))
    expect(Background.refuse(call))->toEqual(2)
    input->Dict.set("timeout_ms", JSON.Number(1800000.))
    expect(Background.refuse(call))->toEqual(0)
  })

  test("keeps Bash's timeout subject to the foreground seconds", () => {
    expect(Background.refuse(payload(~tool="Bash", ~timeout=1800000., "cat out.log")))->toEqual(2)
  })

  test("is a foreground call asking for more than the foreground seconds", () => {
    expect(Background.refuse(payload(~timeout=600000., "curl localhost")))->toEqual(2)
    expect(Background.refuse(payload(~timeout=120000., "curl localhost")))->toEqual(2)
    expect(Background.refuse(payload(~timeout=15000., "curl localhost")))->toEqual(0)
    expect(
      Background.refuse(payload(~background=true, ~timeout=600000., "mise run check")),
    )->toEqual(0)
  })
})

describe("a command that sleeps in the foreground", () => {
  let loop = "for i in 1 2 3; do grep -q x f && break; sleep 8; done"
  let refused = (~background=false, ~tool=?, command) =>
    Background.refuse(payload(~background, ~tool?, command))

  test("is refused as a for loop, and passed in the background or under Monitor", () => {
    expect(refused(loop))->toEqual(2)
    expect(refused(~background=true, loop))->toEqual(0)
    expect(refused(~tool="Monitor", loop))->toEqual(0)
    expect(refused("select x in a b; do sleep 1; break; done"))->toEqual(2)
  })

  test("is passed as a for loop without a sleep, or one only in a here-document", () => {
    expect(refused("for f in a b; do echo $f; done"))->toEqual(0)
    expect(refused(`cat <<'EOF'\n${loop}\nEOF`))->toEqual(0)
  })

  test("is not a loop when its words sit inside a quoted argument", () => {
    ["while :; do :; done", "until :; do :; done", "for i in 1 2; do :; done"]->Array.forEach(
      body => {
        expect(refused(`pkill -f 'sh -c ${body}'; sleep 1; pgrep sh`))->toEqual(0)
        expect(refused(`pkill -f "sh -c ${body}"; sleep 1; pgrep sh`))->toEqual(0)
      },
    )
    expect(refused("while grep -q 'x' f; do sleep 1; done"))->toEqual(2)
  })

  test("is refused when its sleeps add up past the foreground seconds", () => {
    expect(refused("sleep 6; sleep 5; sleep 5; echo done"))->toEqual(2)
    expect(refused("sleep 1"))->toEqual(0)
    expect(refused("sleep 5; sleep 5; sleep 5"))->toEqual(0)
    expect(refused(~background=true, "sleep 6; sleep 5; sleep 5"))->toEqual(0)
    expect(refused(~tool="Monitor", "sleep 6; sleep 5; sleep 5"))->toEqual(0)
  })
})

describe("a refusal", () => {
  test("names the tool and the field it judged", () => {
    expect(Background.judged(payload(~tool="Bash", "ls")))->toEqual("tool_name Bash, field command")
    expect(Background.judged(payload("ls")))->toEqual("tool_name (none), field command")
  })
})

describe("a command that always runs long", () => {
  let refused = command => Background.refuse(payload(command))
  let refusedWith = (~timeout, command) => Background.refuse(payload(~timeout, command))

  ["EOF", "'EOF'", "\"EOF\"", "-EOF"]->Array.forEach(delimiter => {
    test(
      `allows compound text writes with <<${delimiter}`,
      () => {
        let tab = delimiter == "-EOF" ? "\t" : ""
        let body = `${tab}$HEAD\n${tab}mise run check\n${tab}mise run protocol\n${tab}EOF`
        let command =
          `S=notes; HEAD='text'; cat > $S/a.txt <<${delimiter}\n${body}\n` ++
          `cat > $S/b.txt <<${delimiter}\n${body}\n`
        expect(refused(command))->toEqual(0)
        expect(refused(`${command}; mise run check`))->toEqual(2)
        expect(refused(`mise run check; ${command}`))->toEqual(2)
      },
    )
  })

  test("keeps every body on a compound command line out of the command scan", () => {
    let command =
      "S=notes; cat > $S/a <<EOF; cat > $S/b <<'END'\n" ++ "mise run check\nEOF\nmise run protocol\nEND\n"
    expect(refused(command))->toEqual(0)
    expect(refused(`${command}mise run check`))->toEqual(2)
    expect(refused("cat <<EOF\n' ) & $(mise run check)\nEOF\nmise run check"))->toEqual(2)
    expect(refused("cat <<EOF\n' ) & $(mise run check)\nEOF\n"))->toEqual(0)
  })

  test("preserves heredoc lookalikes in arguments and here strings", () => {
    expect(refused("echo '<<EOF'; mise run check"))->toEqual(2)
    expect(refused("cat <<< EOF\nmise run check"))->toEqual(2)
    expect(refused("cat <<EOF\nEOF extra\nmise run check\nEOF"))->toEqual(0)
    expect(refused("cat <<-EOF\n\tmise run check\n\tEOF\nmise run check"))->toEqual(2)
  })

  ["&>", ">&", "&>>", "|&"]->Array.forEach(operator => {
    test(
      `keeps ${operator} in the foreground`,
      () => {
        [
          `mise run check ${operator} /tmp/example.log`,
          `(mise run check; echo done) ${operator} /tmp/example.log`,
          `mise run check ${operator} /tmp/example.log; echo done`,
        ]->Array.forEach(command => expect((command, refused(command)))->toEqual((command, 2)))
        if operator == "|&" {
          expect(refused("echo ready |& mise run check"))->toEqual(2)
        }
      },
    )

    test(
      `allows ${operator} with a real background operator`,
      () => {
        expect(refused(`(mise run check ${operator} /tmp/example.log; echo done) &`))->toEqual(0)
        if operator != "|&" {
          expect(refused(`mise run check ${operator} /tmp/example.log &`))->toEqual(0)
        }
      },
    )
  })

  test("passes every command inside a background group", () => {
    // Splitting at the inner semicolon used to lose the background scope of the build.
    [
      "(node_modules/.bin/rescript build > /tmp/b.log 2>&1; echo $? > /tmp/b.status) &",
      "(rescript build; cargo test; echo done) &",
      "((cargo test; rescript build); mise run build) &",
      "(echo 'quoted ) & ('; cargo test; echo done) &",
      "(echo \"quoted ) & (\"; cargo test) &",
      "(echo escaped \\); cargo test) &",
      "(echo $(printf ')'); cargo test) &",
      "(echo `printf ')'`; cargo test) &",
      "(echo \"escaped \\\" ) &\"; cargo test) &",
      "(cargo test; echo done)& echo started",
      "(cargo test; echo done) &\ncat /tmp/b.log",
      "(until test -e f; do sleep 2; done) &",
      "sh -c '(rescript build; echo done) &'",
    ]->Array.forEach(command => expect((command, refused(command)))->toEqual((command, 0)))
  })

  test("refuses foreground work around groups", () => {
    [
      "(rescript build; echo done)",
      "((cargo test); echo done)",
      "(echo done; cargo test)",
      "(cargo test; echo done) && echo started",
      "(cargo test; echo done) '&'",
      "(cargo test; echo done) \"&\"",
      "(cargo test; echo done) \\&",
      "(cargo test; echo done) & rescript build",
      "(cargo test; echo done) & (rescript build; echo done)",
      "rescript build; (cargo test; echo done) &",
      "((cargo test; echo done) & rescript build)",
      "(echo done) & until test -e f; do sleep 2; done",
      "(until test -e f; do sleep 2; done)",
      "cargo test '&'",
      "cargo test \"&\"",
      "cargo test 'quoted&'",
      "cargo test \\&",
      "cargo test && echo done",
      "sh -c '(rescript build; echo done)'",
    ]->Array.forEach(command => expect((command, refused(command)))->toEqual((command, 2)))
  })

  test("keeps redirected groups together through their background operator", () => {
    // Redirections after a closing group used to separate its work from the background operator.
    [
      "(a && b) > f 2>&1 &",
      "cmd > f 2>&1 &",
      "{ a; b; } > f &",
      "(a) 2>/dev/null >f &",
    ]->Array.forEach(
      command => {
        expect(Background.foregroundText(command)->String.trim)->toEqual(";")
        expect(refused(command))->toEqual(0)
      },
    )
    [
      "(cargo test && rescript build) > f 2>&1 &",
      "cargo test > f 2>&1 &",
      "{ cargo test; rescript build; } > f &",
      "(cargo test) 2>/dev/null >f &",
      "(cargo test) > 'quoted & file' 2>&1 &; echo $!",
      "(cargo test) > f 2>&1 & echo started",
      "{ (cargo test); rescript build; } > f &",
      "(pnpm exec rescript format ... && pnpm exec rescript build) > /tmp/ctrla-build.log 2>&1 & echo $!",
      "(pnpm exec rescript format ... && pnpm exec rescript build) > /tmp/ctrla-build.log 2>&1 &",
    ]->Array.forEach(command => expect((command, refused(command)))->toEqual((command, 0)))
  })

  test("still refuses foreground work beside redirected background groups", () => {
    [
      "for i in 1 2 3; do sleep 8; done",
      "mise run build",
      "echo ready & mise run build",
      "(cargo test) > f 2>&1",
      "{ cargo test; rescript build; } > f",
      "(cargo test) > f 2>&1 & rescript build",
      "{ cargo test; } > f & mise run build",
      "mise run build; (cargo test) > f &",
      "(cargo test) > f && echo done",
      "(cargo test) > f \\&",
    ]->Array.forEach(command => expect((command, refused(command)))->toEqual((command, 2)))
  })

  test("is refused in the foreground whatever its timeout, or none", () => {
    [
      "mise run check",
      "mise run check workspace --all",
      "mise run verify",
      "mise run audit",
      "mise run build",
      "mise r test",
      "mise run update --major",
      "mise run fmt",
      "mise run -q check",
      "mise run //repos/apps/rdm:verify",
      "mise run verify:rust",
      "mise run systems tester x86_64-linux",
      "mise run iterate buf",
      "mise run nudge all --wait 12",
      "mise -C repos/x run built dev",
      "mise exec -- cargo test",
      "vitest run",
      "npx vitest",
      "pnpm exec vitest",
      "cargo build --release",
      "cargo +nightly test",
      "cargo clippy",
      "cargo nextest run",
      "nix build .#x",
      "nix flake check",
      "rescript build",
      "gh run watch 12",
      "pnpm install",
      "/opt/bin/cargo test",
      "timeout 600 mise run check",
      "cd lanes/x && mise run check",
      "ls; mise run check | tail -5",
      "echo $(mise run check)",
      "sh -c 'mise run check'",
      "x=1 mise run check",
    ]->Array.forEach(
      command => {
        expect((command, refused(command)))->toEqual((command, 2))
        expect((command, refusedWith(~timeout=5000., command)))->toEqual((command, 2))
        expect((command, refusedWith(~timeout=900000., command)))->toEqual((command, 2))
      },
    )
  })

  test("is passed in the background, with a trailing ampersand, or as a quoted word", () => {
    expect(Background.refuse(payload(~background=true, "mise run check")))->toEqual(0)
    expect(Background.refuse(payload("mise run check > out.txt 2>&1 &")))->toEqual(0)
    expect(Background.refuse(payload("mise run check >out&")))->toEqual(0)
    expect(Background.refuse(payload("nohup cargo test & echo started")))->toEqual(0)
    expect(Background.refuse(payload("mise run check & mise run build")))->toEqual(2)
    expect(Background.refuse(payload("git log --grep 'mise run check'")))->toEqual(0)
    expect(Background.refuse(payload("echo mise run check")))->toEqual(0)
    expect(Background.refuse(payload("grep -rn \"cargo test\" docs")))->toEqual(0)
    expect(
      Background.refuse(payload("jj commit -m 'docs: mise run check and cargo test are long'")),
    )->toEqual(0)
    expect(
      Background.refuse(payload("cat > note <<'EOF'\nmise run check\ncargo test\nEOF\ncat note")),
    )->toEqual(0)
  })

  test("leaves the fast calls allowed, reads, jj, a dry run, a list and a short task", () => {
    [
      "ls -la",
      "cat docs/agents/agent-protocol.md",
      "rg -n foo hooks",
      "jj st",
      "jj log -r @ --no-graph",
      "jj diff --summary",
      "jj commit -m 'fix: x'",
      "mise run check --dry-run",
      "mise run check workspace -n",
      "mise run check workspace --pending",
      "mise run update --dry-run",
      "mise run fmt -n",
      "mise run brief rdm",
      "mise run plan",
      "mise run repos list",
      "mise run tools check",
      "mise run watch out.txt",
      "mise run nudge buf",
      "mise tasks ls",
      "mise run each --dry-run check",
      "cargo --version",
      "nix --version",
      "gh run list",
      "gh pr view 3",
      "pnpm --version",
      "node scripts/x.res.mjs",
      "tail -n 5 out.txt",
    ]->Array.forEach(
      command => {
        expect((command, refused(command)))->toEqual((command, 0))
        expect((command, refusedWith(~timeout=10000., command)))->toEqual((command, 0))
      },
    )
  })
})

describe("the run ledger's entry", () => {
  test("returns at once, whatever it is given; waiting on it runs long", () => {
    expect(Background.long("mise run job start -- mise run check monoflake/platform"))->toEqual(
      false,
    )
    expect(Background.long("mise run job run -- mise run check"))->toEqual(true)
    expect(Background.long("mise run job start --wait -- ls"))->toEqual(true)
    expect(Background.long("mise run //:lane check compile"))->toEqual(true)
    expect(Background.long("mise run //:job start -- mise run check"))->toEqual(false)
  })
})
