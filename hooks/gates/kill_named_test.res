open Testing

let refused = command => Kill_named.why(command) != None

describe("killing a process", () => {
  test("is refused by name, in every form", () => {
    [
      "pkill node",
      "pkill -f 'sh -c foo'",
      "pkill -9 -f workerd",
      "killall node",
      "/usr/bin/pkill node",
      "kill $(pgrep node)",
      "kill -9 $(pgrep -f workerd)",
      "kill `pgrep node`",
      "pgrep node | xargs kill",
      "pgrep -f workerd | xargs -n1 kill -9",
      "ps ax | awk '/x/{print $1}' | xargs kill",
      "find . -name x -exec kill {} ;",
      "sudo pkill node",
      "env pkill node",
      "timeout 5 pkill node",
      "sh -c 'pkill node'",
      "bash -lc 'kill $(pgrep node)'",
      "(pkill node)",
      "(pkill node) &",
      "echo $(pkill node)",
      "eval 'pkill node'",
      "true && pkill node",
      "P=$(pgrep node); kill $P",
      "for p in $(pgrep node); do kill $p; done",
      "kill $P",
      "kill \"$SOMETHING\"",
      "kill $(cat pidfile)",
      "mise exec -- pkill node",
      "mise x -- kill $(pgrep node)",
      "sudo -u root pkill node",
      "builtin kill $(pgrep x)",
      "ssh host pkill -f x",
      "ssh -o ConnectTimeout=5 root@host 'pkill -f x'",
      "ps | awk '{print \"kill \" $1}' | sh",
    ]->Array.forEach(command => expect((command, refused(command)))->toEqual((command, true)))
  })

  test("is allowed by a pid recorded", () => {
    [
      "kill 12345",
      "kill -9 12345",
      "kill -TERM 12345 12346",
      "kill -s TERM 12345",
      "kill -- -12345",
      "kill %1",
      "kill -TERM -12345",
      "sleep 9 & P=$!; kill $P 2> /dev/null",
      "sleep 9 & P=$!; kill $P > /dev/null",
      "sleep 9 & P=$!; kill $P 2>/dev/null",
      "sleep 9 & P=$!; kill $P &>/dev/null",
      "ssh host kill 12345",
      "ssh host uptime",
      "sleep 9 & kill $!",
      "sleep 9 & P=$!; kill $P",
      "sleep 9 & P=$!; sleep 1; kill -9 \"$P\"",
      "sleep 9 & P=\"$!\"; kill ${P}",
      "mise run //:job stop 20261102-000000-abcd",
    ]->Array.forEach(command => expect((command, refused(command)))->toEqual((command, false)))
  })

  test("is not found in what only names it", () => {
    [
      "pgrep node",
      "grep pkill docs/lessons.md",
      "find . -name kill",
      "sudo grep kill file",
      "kill -l",
      "rg 'kill \\$' hooks",
      "echo pkill",
      "cat <<'E'\npkill node\nE",
    ]->Array.forEach(command => expect((command, refused(command)))->toEqual((command, false)))
  })

  test("refuses with a status the harness reads, and passes another tool's call", () => {
    let payload = command =>
      Dict.fromArray([
        ("tool_name", JSON.String("Bash")),
        ("tool_input", JSON.Object(Dict.fromArray([("command", JSON.String(command))]))),
      ])
    expect(Kill_named.refuse(payload("ls")))->toEqual(0)
    expect(Kill_named.refuse(Dict.fromArray([("tool_name", JSON.String("Read"))])))->toEqual(0)
  })
})
