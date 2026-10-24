open Testing

let refused = (role, command) => Agent_commands.reason(role, command) != None

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

  test("refuse env, exec, xargs and an assignment before a command", () => {
    [
      "env -u cat rm a",
      "env ls",
      "exec -a cat rm a",
      "exec ls",
      "xargs --arg-file cat rm",
      "find . -name x | xargs cat",
      "RIPGREP_CONFIG_PATH=x rg y",
      "JJ_CONFIG=x jj log",
      "ls && LC_ALL=C grep x f",
      "rg --hostname-bin=x y",
      "rg --hostname-bin x y",
    ]->Array.forEach(
      command => expect((command, refused(Reviewer, command)))->toEqual((command, true)),
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
