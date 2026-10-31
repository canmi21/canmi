open Testing

let refused = (role, command) => Agent_commands.reason(role, command) != None

describe("an implementer's commands", () => {
  test("refuse jj, check, deploying tasks, remote tools and git in any chain", () => {
    [
      "jj st",
      "ls && jj log",
      "env jj st",
      "bash -c 'jj st'",
      "mise run check",
      "mise check",
      "mise run check workspace",
      "mise run check --all",
      "mise run check workspace words --all",
      "mise run check workspace rules names",
      "mise run verify",
      "mise -C repos/monoflake/platform run verify",
      "mise run //repos/apps/rdm:verify",
      "mise run //repos/apps/rdm:check workspace words",
      "mise -C repos/monoflake/platform run check workspace words",
      "mise run check apps/rdm",
      "mise run check apps/rdm tasks",
      "mise check apps/rdm tasks",
      "mise run check monoflake/platform model",
      "mise run check workspace --pending",
      "mise run check workspace rules --pending",
      "mise run check --pending",
      "mise run audit",
      "mise audit apps/rdm",
      "mise -C repos/apps/rdm run check workspace words",
      "mise exec -- jj st",
      "mise x node@22 -- jj st",
      "mise exec -C repos/apps/rdm -- mise run check",
      "mise exec -C repos/apps/rdm -- mise run check workspace words",
      "mise run build ::: //repos/monoflake/cloud:switch",
      "mise run built control ::: check",
      "mise run built control ::: built other ::: //repos/monoflake/cloud:switch",
      "mise x -- git status",
      "mise exec -- ssh host",
      "mise x -- wrangler deploy",
      "mise exec -c 'jj st'",
      "mise exec -- bash -c 'jj st'",
      "mise run //repos/monoflake/platform:check",
      "mise run //repos/monoflake/platform:deploy",
      "mise //repos/monoflake/cloud:switch",
      "mise run push",
      "ssh host",
      "rsync a b",
      "wrangler deploy",
      "npx wrangler deploy",
      "git status",
      "ls\njj st",
      "mise -C repos/monoflake/platform run deploy",
      "mise run -j 4 check",
      "mise -j 4 run //repos/monoflake/cloud:switch",
      "timeout 60 jj st",
      "time jj st",
      "exec jj st",
      "pnpm exec jj st",
      "nice -n 5 jj st",
      "nohup jj st",
      "xargs -n 1 jj st",
      "npx -y wrangler deploy",
      "echo $(jj st)",
      "echo `jj st`",
      "echo \"$(ls; jj st)\"",
      "timeout 60 ssh host",
    ]->Array.forEach(
      command => expect((command, refused(Implementer, command)))->toEqual((command, true)),
    )
  })

  test("allow the logic layer and ordinary commands", () => {
    [
      "mise run built control",
      "mise exec -- ls",
      "mise x node@22 -- node a.js",
      "mise run accept control --from main",
      "mise run //repos/monoflake/platform:build",
      "mise run //repos/monoflake/driver:deploy",
      "ls | grep jj",
      "echo 'jj st'",
      "echo '$(jj st)'",
      "mise -C repos/monoflake/driver run deploy",
      "mise run -j 4 built control",
      "timeout 60 ls",
      "ls\necho jj",
    ]->Array.forEach(
      command => expect((command, refused(Refactorer, command)))->toEqual((command, false)),
    )
  })
})

describe("one part of the check", () => {
  test("is an implementer's, named after a repository, and no refactorer's", () => {
    [
      "mise run check workspace words",
      "mise run check workspace hooks",
      "mise run //:check workspace words",
      "mise run -j 4 check workspace words",
      "mise x -- mise run check workspace words",
      "mise exec -- mise run check workspace words",
    ]->Array.forEach(
      command => {
        expect((command, refused(Implementer, command)))->toEqual((command, false))
        expect((command, refused(Refactorer, command)))->toEqual((command, true))
      },
    )
  })
})

describe("a part from a repository's directory", () => {
  let platform = Node.join([Registry.root, "repos", "monoflake", "platform"])
  let inside = Node.join([platform, "model"])

  test("is refused where the nearest check task is not the workspace's", () => {
    [inside, platform]->Array.forEach(
      cwd =>
        expect((
          cwd,
          Agent_commands.reason(~cwd, Implementer, "mise run check workspace words") != None,
        ))->toEqual((cwd, true)),
    )
  })

  test("is allowed from the workspace root, or by the scoped workspace task", () => {
    expect(
      Agent_commands.reason(~cwd=Registry.root, Implementer, "mise run check workspace words"),
    )->toEqual(None)
    expect(
      Agent_commands.reason(~cwd=platform, Implementer, "mise run //:check workspace words"),
    )->toEqual(None)
    expect(
      Agent_commands.reason(
        ~cwd=platform,
        Implementer,
        "mise -C ../../.. run check workspace words",
      ),
    )->toEqual(None)
  })
})

describe("a refusal", () => {
  test("says which rule holds it", () => {
    [
      (Agent_commands.Implementer, "mise run check apps/rdm tasks", "implementer-commands"),
      (
        Agent_commands.Implementer,
        "mise run check workspace rules --pending",
        "implementer-commands",
      ),
      (Agent_commands.Refactorer, "mise run check workspace words", "refactorer-commands"),
      (Agent_commands.Reviewer, "mise run check workspace words", "reviewer-commands"),
      (Agent_commands.Reviewer, "mise run audit", "reviewer-commands"),
    ]->Array.forEach(
      ((role, command, rule)) =>
        expect((
          command,
          Agent_commands.reason(role, command)->Option.mapOr(
            false,
            why => why->String.includes(rule),
          ),
        ))->toEqual((command, true)),
    )
  })
})

describe("a reviewer's cat", () => {
  test("reads files with its read-only flags, alone or piped into another reader", () => {
    [
      "cat hooks/run.res",
      "cat a.res b.res",
      "cat -n hooks/run.res",
      "cat -b a.res",
      "cat -s a.res",
      "cat -v a.res",
      "cat -e a.res",
      "cat -t a.res",
      "cat -A a.res",
      "cat -- a.res",
      "cat /Users/canmi/workspace/hooks/run.res",
      "cat ./hooks/.hidden/a.res",
      "cat 'src/routes/+page.svelte'",
      "cat a.res | head -20",
      "cat a.res | grep x | wc -l",
      "cat -n a.res | sed -n 10,20p",
      "cat -n a.res | sed -n '10,20p'",
      "cat -n a.res | tail -n +40 | head -60",
      "cat a.res 2>/dev/null | head",
      "cat a.res > /dev/null",
      "cat a.res | head -20; cat b.res | head -20",
      "cat a.res && cat b.res",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, false)),
    )
  })

  test("is refused whatever writes, beside it or after it", () => {
    [
      "cat a.res > b.res",
      "cat a.res >> b.res",
      "cat a.res | tee b.res",
      "cat a.res | tee -a b.res",
      "cat > b.res <<EOF\nx\nEOF",
      "cat <<EOF > b.res\nx\nEOF",
      "cat <<EOF >> b.res\nx\nEOF",
      "cat a.res; rm b.res",
      "cat a.res; touch b.res",
      "cat a.res && cp a.res b.res",
      "cat a.res || mv a.res b.res",
      "cat a.res | xargs rm",
      "cat a.res | sh",
      "cat -n secrets.json",
      "cat a.res secrets.json | head",
      "jq . machines/okra/secrets.json",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, true)),
    )
  })

  test("follows a cd, and echo or printf of literals, the widening of 2026-10-31", () => {
    [
      "cd /Users/canmi/workspace/lanes/readcat/workspace && cat -n hooks/run.res",
      "cd ../other; ls",
      "echo ===",
      "cat a.res; echo ===; cat b.res",
      "printf '%s\\n' a b",
      "printf '== %s ==\\n' a.res; cat a.res | head -20",
      "echo === > /dev/null",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, false)),
    )
  })

  test("refuses echo or printf that writes or runs another program, and what a cd leads to", () => {
    [
      "echo x > f",
      "echo x >> f",
      "echo x | tee f",
      "printf '%s' x > f",
      "echo $(rm f)",
      "echo $(cat a.res)",
      "echo `rm f`",
      "echo \"`id`\"",
      "printf \"$(id)\"",
      "echo $CLOUDFLARE_API_TOKEN",
      "printf -v X '%s' secrets.json; cat $X",
      "printf -v PATH '%s' bin; cat a.res",
      "cd $CLOUDFLARE_API_TOKEN",
      "cd `pwd`",
      "cat $(echo secrets.json)",
      "cat $(printf secr; printf ets.json)",
      "echo x | sh",
      "cd /tmp && rm f",
      "cd /tmp; touch f",
      "X=/tmp; cat $X/a",
      "cat a.res | sort",
      "cat a.res | cut -c1-80",
      "awk '{print}' a.res",
      "for f in a b; do cat $f; done",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, true)),
    )
  })

  test("on a secrets file names secrets-unprinted", () => {
    expect(Agent_commands.reason(Reviewer, "cat -n secrets.json | head"))->toEqual(
      Some("cat would print a secret, secrets-unprinted holds it"),
    )
  })
})

describe("formatting what an agent wrote", () => {
  test("formats a file by its suffix and leaves an unowned or unparsable one", () => {
    let directory = Node.mkdtempSync(Node.join([Node.tmpdir(), "format-"]))
    let write = (name, text) => {
      let path = Node.join([directory, name])
      Node.writeFileSync(path, text)
      path
    }
    let payloadOf = path => Payload.parse(`{"tool_input":{"file_path":"${path}"}}`)
    let res = write("a.res", "let   x =   1\n")
    let toml = write("b.toml", "a   =   1\n")
    let broken = write("c.res", "let = = (\n")
    [res, toml, broken]->Array.forEach(
      path => expect(payloadOf(path)->Option.mapOr(1, Agent_commands.format))->toEqual(0),
    )
    expect(Node.readFileSync(res))->toEqual("let x = 1\n")
    expect(Node.readFileSync(toml))->toEqual("a   =   1\n")
    expect(Node.readFileSync(broken))->toEqual("let = = (\n")
  })

  test("reads the files a Codex patch adds, updates and moves, relative to its cwd", () => {
    let cwd = Node.mkdtempSync(Node.join([Node.tmpdir(), "format-cwd-"]))
    let patch =
      [
        "*** Begin Patch",
        "*** Add File: a.res",
        "+let x = 1",
        "*** Update File: /abs/b.res",
        "@@",
        "*** Delete File: gone.res",
        "*** Update File: c.res",
        "*** Move to: d.res",
        "*** End Patch",
      ]->Array.join("\n")
    let payload = Payload.parse(
      JSON.stringify(
        JSON.Object(
          dict{
            "cwd": JSON.String(cwd),
            "tool_name": JSON.String("apply_patch"),
            "tool_input": JSON.Object(dict{"command": JSON.String(patch)}),
          },
        ),
      ),
    )
    expect(payload->Option.mapOr([], Agent_commands.written))->toEqual([
      Node.join([cwd, "a.res"]),
      "/abs/b.res",
      Node.join([cwd, "c.res"]),
      Node.join([cwd, "d.res"]),
    ])
  })

  test("formats a file a Codex patch wrote, and an Edit's one alone where both are given", () => {
    let directory = Node.mkdtempSync(Node.join([Node.tmpdir(), "format-patch-"]))
    let path = Node.join([directory, "a.res"])
    Node.writeFileSync(path, "let   x =   1\n")
    let patch = `*** Begin Patch\n*** Update File: a.res\n*** End Patch`
    let payloadOf = input =>
      Payload.parse(
        JSON.stringify(
          JSON.Object(dict{"cwd": JSON.String(directory), "tool_input": JSON.Object(input)}),
        ),
      )
    expect(
      payloadOf(dict{"input": JSON.String(patch)})->Option.mapOr(1, Agent_commands.format),
    )->toEqual(0)
    expect(Node.readFileSync(path))->toEqual("let x = 1\n")
    expect(
      payloadOf(
        dict{
          "file_path": JSON.String("/elsewhere.res"),
          "command": JSON.String(patch),
        },
      )->Option.mapOr([], Agent_commands.written),
    )->toEqual(["/elsewhere.res"])
  })
})

describe("formatting by a repository's own table", () => {
  let scratch = () => Node.mkdtempSync(Node.join([Node.tmpdir(), "format-table-"]))
  let payloadOf = path => Payload.parse(`{"tool_input":{"file_path":"${path}"}}`)
  let formatted = path => payloadOf(path)->Option.mapOr(1, Agent_commands.format)

  test("passes over test data and an unformatted suffix, and never touches a lock", () => {
    let root = scratch()
    Node.writeFileSync(
      Node.join([root, "workspace.toml"]),
      "[format]\nunformatted = [\".res\"]\ntest_data = [\"data\"]\n",
    )
    Node.mkdirAll(Node.join([root, "data"]))
    let write = (name, text) => {
      let path = Node.join([root, name])
      Node.writeFileSync(path, text)
      path
    }
    let data = write("data/a.sh", "if true;then\necho   hi\nfi\n")
    let own = write("b.res", "let   x =   1\n")
    let lock = write("c.lock", "a   =   1\n")
    [data, own, lock]->Array.forEach(path => expect(formatted(path))->toEqual(0))
    expect(Node.readFileSync(data))->toEqual("if true;then\necho   hi\nfi\n")
    expect(Node.readFileSync(own))->toEqual("let   x =   1\n")
    expect(Node.readFileSync(lock))->toEqual("a   =   1\n")
  })

  test("formats a misformatted shell script", () => {
    let root = scratch()
    Node.writeFileSync(Node.join([root, "workspace.toml"]), "")
    let path = Node.join([root, "a.sh"])
    Node.writeFileSync(path, "if true;then\necho   hi\nfi\n")
    expect(formatted(path))->toEqual(0)
    expect(Node.readFileSync(path))->toEqual("if true; then\n\techo hi\nfi\n")
  })

  test("runs no Nix where the repository has no lock", () => {
    let root = scratch()
    Node.writeFileSync(Node.join([root, "workspace.toml"]), "")
    let path = Node.join([root, "a.nix"])
    Node.writeFileSync(path, "{   a=1; }\n")
    expect(formatted(path))->toEqual(0)
    expect(Node.readFileSync(path))->toEqual("{   a=1; }\n")
  })
})

describe("printing a secret", () => {
  test("is refused to every role, wherever the command is nested", () => {
    [
      "printenv",
      "printenv CLOUDFLARE_API_TOKEN",
      "env",
      "env -0",
      "export",
      "export -p",
      "set",
      "declare -p",
      "typeset -x",
      "mise env",
      "mise env --json",
      "mise -C repos/monoflake/cloud env",
      "mise set",
      "sops -d secrets.json",
      "sops --decrypt machines/okra/secrets.json",
      "sops decrypt --extract '[\"X\"]' secrets.json",
      "sops exec-env secrets.json 'true'",
      "sops edit secrets.json",
      "cat secrets.json",
      "cat ../cloud/machines/okra/secrets.json",
      "jq . secrets.json",
      "ls && mise env | head",
      "bash -c 'printenv'",
      "mise exec -- env",
    ]->Array.forEach(
      command =>
        [Agent_commands.Implementer, Refactorer, Reviewer]->Array.forEach(
          role => expect((command, refused(role, command)))->toEqual((command, true)),
        ),
    )
  })

  test("leaves a command that only sets or reads what is not secret", () => {
    [
      "env FOO=1 node script.mjs",
      "env -i PATH=/bin ls",
      "export FOO=1",
      "set -euo pipefail",
      "mise run test",
      "sops filestatus secrets.json",
      "jq 'del(.sops)|keys' package.json",
      "cat secrets.md",
    ]->Array.forEach(
      command =>
        expect((command, refused(Agent_commands.Implementer, command)))->toEqual((command, false)),
    )
  })

  test("names its rule", () => {
    expect(Agent_commands.reason(Agent_commands.Implementer, "mise env"))->toEqual(
      Some("mise would print a secret, secrets-unprinted holds it"),
    )
  })
})

describe("an implementer's writes", () => {
  let lane = Node.join([Agent_commands.lanesRoot, "flows"])
  let other = Node.join([Agent_commands.lanesRoot, "wiring"])

  test("pass inside the lane its working directory lies in, and in a temporary directory", () => {
    let cwd = Node.join([lane, "monoflake", "machine"])
    expect(
      Agent_commands.outside(
        ~cwd,
        [
          "src/flow.rs",
          Node.join([lane, "monoflake", "machine", "tests", "a.rs"]),
          Node.join([Node.tmpdir(), "scratch.txt"]),
          "/private/tmp/claude-501/report.txt",
        ],
      ),
    )->toEqual([])
  })

  test("are refused outside that lane, in another lane, in the main checkout, or by ..", () => {
    let cwd = Node.join([lane, "monoflake", "machine"])
    let main = Node.join([Registry.root, "repos", "monoflake", "machine", "src", "lib.rs"])
    let sibling = Node.join([other, "monoflake", "machine", "a.rs"])
    let home = "/Users/someone/.cargo/config.toml"
    expect(
      Agent_commands.outside(~cwd, [main, sibling, home, "../../../../repos/x.res"]),
    )->toEqual([main, sibling, home, Node.resolve([cwd, "../../../../repos/x.res"])])
  })

  test("from outside every lane pass in any lane and nowhere else", () => {
    let cwd = Registry.root
    let inLane = Node.join([other, "workspace", "hooks", "a.res"])
    let main = Node.join([Registry.root, "hooks", "a.res"])
    expect(Agent_commands.outside(~cwd, [inLane, main]))->toEqual([main])
  })
})
