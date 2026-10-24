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
      "mise run check workspace words",
      "mise check",
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

describe("a reviewer's commands", () => {
  test("allow jj only to read", () => {
    ["jj diff -r @-", "jj file show -r @ x", "jj log", "jj -R a show @", "ls"]->Array.forEach(
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
