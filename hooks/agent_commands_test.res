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

describe("a reviewer's commands", () => {
  test("refuse every check, part or whole, every audit and --pending", () => {
    [
      "mise run check",
      "mise check workspace words",
      "mise run check workspace hooks",
      "mise run check apps/rdm tasks",
      "mise run check --all",
      "mise run audit",
      "mise audit apps/rdm",
      "mise run check workspace --pending",
      "mise run check workspace rules --pending",
      "mise exec -- mise run check workspace words",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, true)),
    )
  })

  test("allow jj only to read", () => {
    [
      "jj diff -r @-",
      "jj file show -r @ x",
      "jj log",
      "jj -R a show @",
      "ls",
      "mise exec -- jj log",
      "mise x -- ls",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, false)),
    )
    [
      "jj commit -m x",
      "jj st",
      "jj file list",
      "git status",
      "ls && jj new",
      "ls\njj st",
      "timeout 60 jj st",
      "time jj st",
      "exec jj st",
      "pnpm exec jj st",
      "echo $(jj st)",
      "echo `jj st`",
      "mise exec -- jj st",
      "mise x -- git log",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, true)),
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
