open Testing

let known: Send_local.known = {
  sessions: ["workspace-87", "monoflake@workspace"],
  subagents: ["a2028374e9bf6e763", "tidy"],
  socket: path => path == "/tmp/cc-socks/47875.sock",
}
let refused = to => Send_local.why(to, ~known) != None

describe("a message", () => {
  test("is let through to what is on this machine", () => {
    [
      "main",
      "team-lead",
      "workspace-87",
      "monoflake@workspace",
      "a2028374e9bf6e763",
      "tidy",
      "uds:/tmp/cc-socks/47875.sock",
    ]->Array.forEach(to => expect((to, refused(to)))->toEqual((to, false)))
  })

  test("is refused to what is not", () => {
    [
      "made-up",
      "made-up [3fa9c1]",
      "workspace-87 [3fa9c1]",
      "main [r1]",
      "tidy [r1]",
      "uds:/tmp/cc-socks/47875.sock [r1]",
      "uds:/tmp/cc-socks/1.sock",
      "uds:/elsewhere/47875.sock",
    ]->Array.forEach(to => expect((to, refused(to)))->toEqual((to, true)))
  })

  test("asks for a socket when a ref cannot identify a machine", () => {
    expect(Send_local.why("workspace-87 [r1]", ~known)->Option.getOr(""))->toContain(
      "uds:/tmp/cc-socks/<pid>.sock",
    )
  })

  test("takes only a socket in the directory sessions listen in", () => {
    expect(Send_local.localSocket("/elsewhere/a.sock"))->toEqual(false)
    expect(Send_local.localSocket("/tmp/cc-socks/none.sock"))->toEqual(false)
  })
})

@val external pid: int = "process.pid"
@get external childPid: Node.spawned => int = "pid"

let payload = text => Payload.parse(text)->Option.getOr(Dict.make())
let message = to =>
  payload(
    JSON.stringify(
      JSON.Object(
        Dict.fromArray([
          ("tool_name", JSON.String("SendMessage")),
          ("tool_input", JSON.Object(Dict.fromArray([("to", JSON.String(to))]))),
        ]),
      ),
    ),
  )

describe("local records", () => {
  let root = temporaryRoot("send-local-")
  let previousHome = ref(None)
  beforeEach(() => {
    previousHome := Node.env->Dict.get("HOME")
    Node.env->Dict.set("HOME", root.contents)
  })
  afterEach(() =>
    switch previousHome.contents {
    | Some(value) => Node.env->Dict.set("HOME", value)
    | None => Node.env->Dict.delete("HOME")
    }
  )
  let records = files => tree(root.contents, files)
  let session = (name, pid) => `{"name":"${name}","pid":${Int.toString(pid)}}`
  let transcript = () => payload(`{"transcript_path":"${root.contents}/chat.jsonl"}`)

  test("admits only live session records", () => {
    let dead = Node.spawnSync(
      "node",
      ["-e", "process.kill(process.pid, 'SIGKILL')"],
      {timeout: 5000},
    )
    expect(Watchdog.alive(childPid(dead)))->toEqual(false)
    records([
      (".claude/sessions/live.json", session("live", pid)),
      (".claude/sessions/dead.json", session("remote-namesake", childPid(dead))),
      (".claude/sessions/no-pid.json", "{\"name\":\"no-pid\"}"),
      (".claude/sessions/invalid.json", "{"),
      (".claude/sessions/wrong-pid.json", "{\"name\":\"wrong-pid\",\"pid\":\"1\"}"),
      (".claude/sessions/ignored.txt", session("ignored", pid)),
    ])
    Node.mkdirAll(Node.join([root.contents, ".claude/sessions/unreadable.json"]))
    expect(Send_local.sessionNames())->toEqual(["live"])
    expect(Send_local.refuse(message("live")))->toEqual(0)
    expect(Send_local.refuse(message("remote-namesake")))->toEqual(2)
  })

  test("reads no sessions when the directory cannot be listed", () => {
    records([(".claude/sessions", "not a directory")])
    expect(Send_local.sessionNames())->toEqual([])
  })

  test("reads no subagents when the directory cannot be listed", () => {
    records([("chat/subagents", "not a directory")])
    expect(Send_local.subagentsOf(transcript()))->toEqual([])
  })

  test("refuses rather than throwing when both listings fault", () => {
    records([(".claude/sessions", "not a directory"), ("chat/subagents", "not a directory")])
    let fields = transcript()
    fields->Dict.set("tool_name", JSON.String("SendMessage"))
    fields->Dict.set("tool_input", JSON.Object(Dict.fromArray([("to", JSON.String("unknown"))])))
    expect(Send_local.refuse(fields))->toEqual(2)
  })

  test("reads subagent ids and names and skips unreadable names", () => {
    records([
      ("chat/subagents/agent-one.meta.json", "{\"name\":\"tidy\"}"),
      ("chat/subagents/agent-two.meta.json", "{"),
      ("chat/subagents/ignored.json", "{}"),
    ])
    expect(Send_local.subagentsOf(transcript())->Array.toSorted(String.compare))->toEqual([
      "one",
      "tidy",
      "two",
    ])
    expect(Send_local.subagentsOf(Dict.make()))->toEqual([])
  })

  test("uses the operating system home when HOME is empty or absent", () => {
    Node.env->Dict.set("HOME", "")
    let fallback = Send_local.home()
    expect(Node.isAbsolute(fallback))->toEqual(true)
    Node.env->Dict.delete("HOME")
    expect(Send_local.home())->toEqual(fallback)
  })

  test("refuses refs even when the name is a live local session", () => {
    records([(".claude/sessions/live.json", session("workspace-87", pid))])
    expect(Send_local.refuse(message("workspace-87 [r1]")))->toEqual(2)
  })

  test("leaves other tools and missing recipients alone", () => {
    expect(Send_local.refuse(payload("{\"tool_name\":\"Read\"}")))->toEqual(0)
    expect(Send_local.refuse(payload("{\"tool_name\":\"SendMessage\"}")))->toEqual(0)
  })
})
