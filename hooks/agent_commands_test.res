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

  test("allow jj only as diff, log, show, file show and file list", () => {
    [
      "jj diff -r @-",
      "jj log",
      "jj show @",
      "jj -R a show @",
      "jj file show -r @ x",
      "jj file list",
      "jj file list -r @-",
      "jj log --no-graph | head",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, false)),
    )
  })

  test("refuse every other jj subcommand, jj status included, and a bare jj", () => {
    [
      "jj",
      "jj commit -m x",
      "jj st",
      "jj status",
      "jj new",
      "jj file",
      "jj file annotate x",
      "jj file track x",
      "jj -R a st",
      "git status",
      "git log",
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

  test("allow the programs that only inspect", () => {
    [
      "cat a",
      "head -n 5 a",
      "tail -f a",
      "grep -rn x .",
      "rg x",
      "rg -n x src",
      "ls",
      "ls -la docs",
      "wc -l a",
      "diff a b",
      "find . -name '*.res'",
      "find . -type f -print",
      "/usr/bin/cat a",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, false)),
    )
  })

  test("refuse every program beside them, a shell and mise among them", () => {
    [
      "rm a",
      "trash a",
      "touch a",
      "mkdir a",
      "cp a b",
      "mv a b",
      "echo hi",
      "tee a",
      "node a.js",
      "python3 a.py",
      "curl localhost",
      "xargs rm",
      "bash -c 'ls'",
      "sh -c 'cat a'",
      "zsh -c ls",
      "fish -c ls",
      "bash a.sh",
      "ssh host",
      "wrangler deploy",
      "npx wrangler deploy",
      "mise run built control",
      "mise exec -- ls",
      "mise exec -- jj log",
      "mise x -- ls",
      "mise x node@22 -- cat a",
      "mise exec -c 'ls'",
      "mise run //repos/apps/rdm:verify",
      "mise ls",
      "mise tasks",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, true)),
    )
  })

  test("allow sed only quiet", () => {
    [
      "sed -n 5p a",
      "sed -n '1,10p' a",
      "sed --quiet 5p a",
      "sed --silent 5p a",
      "sed -nE 's/a/b/p' a",
      "sed -En 's/a/b/p' a",
      "sed -n -e 5p a",
      "sed -ne 5p a",
      "sed 5p -n a",
      "sed -n '/-i/p' a",
      "sed -n -- 5p a",
      "cat a | sed -n 2p",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, false)),
    )
    [
      "sed 5p a",
      "sed 's/a/b/' a",
      "sed -E 's/a/b/' a",
      "sed -e 5p a",
      "sed -s 5p a",
      "sed 5p a --",
      "sed -- -n a",
      "sed",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, true)),
    )
  })

  test("refuse sed in place, in any spelling", () => {
    [
      "sed -i 's/a/b/' a",
      "sed -n -i 's/a/b/' a",
      "sed -ni 's/a/b/' a",
      "sed -in 's/a/b/' a",
      "sed -Ei 's/a/b/' a",
      "sed -i.bak 's/a/b/' a",
      "sed -n -i.bak 's/a/b/' a",
      "sed -i'' 's/a/b/' a",
      "sed -i '' 's/a/b/' a",
      "sed -n -i '' 's/a/b/' a",
      "sed -I 's/a/b/' a",
      "sed --in-place 's/a/b/' a",
      "sed --in-place=.bak 's/a/b/' a",
      "sed --in-pl 's/a/b/' a",
      "sed -n --in-place 's/a/b/' a",
      "sed --quiet --in-place 's/a/b/' a",
      "sed --silent --in-place=.bak 's/a/b/' a",
      "ls | sed -n -i 5p a",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, true)),
    )
  })

  test("refuse find given -exec or -delete", () => {
    [
      "find . -exec rm {} ;",
      "find . -name a -exec cat {} +",
      "find . -delete",
      "find . -type f -name '*.tmp' -delete",
      "find . -name a -print -delete",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, true)),
    )
    expect(refused(Reviewer, "find . -name '-exec'"))->toEqual(true)
    expect(refused(Reviewer, "find . -name exec"))->toEqual(false)
  })

  test("judge each segment of a chain or a pipeline", () => {
    [
      "rg x | head",
      "rg x | head -n 5 | wc -l",
      "ls && cat a",
      "ls; jj log",
      "cat a || jj diff",
      "ls\njj show @",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, false)),
    )
    [
      "ls && mise run fmt",
      "ls && rm a",
      "rg x | xargs rm",
      "cat a | sh",
      "ls; jj new",
      "ls\nrm a",
      "ls | sed -i 5p a",
      "ls && find . -delete",
      "ls $(rm a)",
      "cat `rm a`",
      "cat \"$(mise run fmt)\"",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, true)),
    )
  })

  test("refuse an output redirection to a file and a process substitution", () => {
    [
      "cat a > b",
      "cat a >b",
      "cat a >> b",
      "cat a 2> b",
      "cat a &> b",
      "cat a &>> b",
      "cat a >| b",
      "cat a >& b",
      "cat a <> b",
      "cat a > \"b\"",
      "cat a > $HOME/b",
      "cat a >",
      "rg x > /dev/nullx",
      "diff <(rm a) b",
      "diff a >(rm b)",
      "diff <(cat a) b",
      "cat \"$(cat a > b)\"",
      "cat `cat a > b`",
      "cat $(ls > b)",
      "rm $'\\'' a",
      "cat 'a",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, true)),
    )
  })

  test("allow /dev/null, a duplicated descriptor and input read from a file", () => {
    [
      "cat a 2>/dev/null",
      "cat a >/dev/null",
      "cat a > /dev/null 2>&1",
      "grep -n x f 2>&1 | head",
      "rg x 2>/dev/null | head",
      "cat a &>/dev/null",
      "wc -l < a",
      "rg '>' a",
      "grep \"a > b\" f",
      "grep 'a & b' f",
      "rg x | head",
      "cat a 1>&2",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, false)),
    )
  })

  test("judge a command run by & as one of its own", () => {
    [
      "ls & rm a",
      "ls &rm a",
      "cat a & mise run fmt",
      "ls & jj st",
      "cat a |& rm b",
      "cat $(ls & rm a)",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, true)),
    )
    ["ls & cat a", "rg x & jj log"]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, false)),
    )
  })

  test("refuse sed given a writing or running script, or a script file", () => {
    [
      "sed -n -l -i '' 's/a/b/' f",
      "sed -nl -i 's/a/b/' f",
      "sed -n 'w out' f",
      "sed -n '1w out' f",
      "sed -n '/x/w out' f",
      "sed -n 's/a/b/w out' f",
      "sed -n 's/a/b/gw out' f",
      "sed -n 's/a/b/e' f",
      "sed -n e f",
      "sed -n '1e' f",
      "sed -n 'W out' f",
      "sed -n '1,5W out' f",
      "sed -n -e p -e 'w out' f",
      "sed -n --expression='w out' f",
      "sed -n --expr 'w out' f",
      "sed -ne 'w out' f",
      "sed -n -e '1{w out' -e '}' f",
      "sed -n '1{w out}' f",
      "sed -n 'p;w out' f",
      "sed -n ':a;w out' f",
      "sed -n '/[a/b]/w out' f",
      "sed -n '\\,x,w out' f",
      "sed -n '1!w out' f",
      "sed -n 's/a/b' f",
      "sed -n '/x' f",
      "sed -n 1 f",
      "sed -n -f script.sed f",
      "sed -nf script.sed f",
      "sed -n --file=script.sed f",
      "sed -n 'k' f",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, true)),
    )
    [
      "sed -n '1,20p' f",
      "sed -n '/error/p' f",
      "sed -n 's/hello/world/gp' f",
      "sed -n '/x/,/y/p' f",
      "sed -n '$p' f",
      "sed -n '1!p' f",
      "sed -n '/[/]/p' f",
      "sed -n 's|a|b|p' f",
      "sed -n '\\,x,p' f",
      "sed -n '1{p;p}' f",
      "sed -n -e '1p' -e '2p' f",
      "sed -n -l '1p' f",
      "sed -n 'y/abc/xyz/;p' f",
      "sed -n '/x/{=;p}' f",
      "sed -n '1~2p' f",
      "sed -n '5q' f",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, false)),
    )
  })

  test("refuse find, rg and jj given a flag that writes or runs a program", () => {
    [
      "find . -fprint out",
      "find . -fprint0 out",
      "find . -fprintf out %p",
      "find . -fls out",
      "find . -ok rm {} ;",
      "find . -okdir rm {} ;",
      "find . -execdir rm {} ;",
      "rg --pre cat x",
      "rg --pre=cat x",
      "rg -n --pre ./run x .",
      "jj diff --tool meld",
      "jj diff --tool=meld",
      "jj --config ui.pager=x log",
      "jj log --config=ui.pager=x",
      "jj --config-file x log",
      "jj show --config-file=x @",
      "jj --tool x diff",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, true)),
    )
    [
      "jj diff --from a --to b",
      "find . -name '*.res'",
      "rg --pretty x",
      "rg -n x src | head",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, false)),
    )
  })

  test("name the rule in every refusal", () => {
    [
      "jj st",
      "jj",
      "git status",
      "rm a",
      "bash -c ls",
      "mise exec -- ls",
      "sed 5p a",
      "sed -i 5p a",
      "find . -delete",
    ]->Array.forEach(
      command =>
        expect((
          command,
          Agent_commands.reason(Reviewer, command)->Option.mapOr(
            false,
            why => why->String.includes("reviewer-commands"),
          ),
        ))->toEqual((command, true)),
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
