open Testing

@module("node:fs") external appendFileSync: (string, string) => unit = "appendFileSync"
@module("node:fs") external utimesSync: (string, float, float) => unit = "utimesSync"

let dir = Node.mkdtempSync(Node.join([Node.tmpdir(), "stale-jobs-"]))
let at = 1_000_000_000_000.

let json = value => JSON.stringifyAny(value)->Option.getOr("")

let started = (~session, ~call, ~id, ~output, ~description, ~command="sleep 99", ~cwd="/tmp") =>
  [
    json({
      "type": "assistant",
      "sessionId": session,
      "cwd": cwd,
      "message": {
        "role": "assistant",
        "content": [
          {
            "type": "tool_use",
            "id": call,
            "name": "Bash",
            "input": {"command": command, "description": description, "run_in_background": true},
          },
        ],
      },
    }),
    json({
      "type": "user",
      "sessionId": session,
      "message": {
        "role": "user",
        "content": [
          {
            "type": "tool_result",
            "tool_use_id": call,
            "content": `Command running in background with ID: ${id}. Output is being written to: ${output}. You will be notified when it completes.`,
          },
        ],
      },
    }),
  ]->Array.join("\n")

/** A tool result of a call that is not the start of a job, with `text` in it. */
let quoting = (~session, ~call, text) =>
  [
    json({
      "type": "assistant",
      "sessionId": session,
      "message": {
        "role": "assistant",
        "content": [
          {"type": "tool_use", "id": call, "name": "Bash", "input": {"command": "grep -r x ."}},
        ],
      },
    }),
    json({
      "type": "user",
      "sessionId": session,
      "message": {
        "role": "user",
        "content": [{"type": "tool_result", "tool_use_id": call, "content": text}],
      },
    }),
  ]->Array.join("\n")

let notice = (~session, ~id) =>
  json({
    "type": "queue-operation",
    "operation": "enqueue",
    "sessionId": session,
    "content": `<task-notification>\n<task-id>${id}</task-id>\n<status>completed</status>\n</task-notification>`,
  })

let userSays = (~session, text) =>
  json({
    "type": "user",
    "sessionId": session,
    "message": {"role": "user", "content": text},
  })

let taskStop = (~session, ~call, ~id, ~result) =>
  [
    json({
      "type": "assistant",
      "sessionId": session,
      "message": {
        "role": "assistant",
        "content": [{"type": "tool_use", "id": call, "name": "TaskStop", "input": {"task_id": id}}],
      },
    }),
    json({
      "type": "user",
      "sessionId": session,
      "message": {
        "role": "user",
        "content": [
          {
            "type": "tool_result",
            "tool_use_id": call,
            "content": result
              ? `{"message":"Successfully stopped task: ${id} (sleep 9)"}`
              : "No such task",
          },
        ],
      },
    }),
  ]->Array.join("\n")

let write = (name, lines) => {
  let path = Node.join([dir, name])
  Node.writeFileSync(path, lines->Array.join("\n") ++ "\n")
  path
}

let output = (name, ~silent) => {
  let path = Node.join([dir, name])
  Node.writeFileSync(path, "x")
  let marker = (at -. silent->Int.toFloat *. 1000.) /. 1000.
  utimesSync(path, marker, marker)
  path
}

let payload = (~active=false, ~agent=?, transcript, session): Payload.t => {
  let fields = Dict.fromArray([
    ("transcript_path", JSON.String(transcript)),
    ("session_id", JSON.String(session)),
    ("stop_hook_active", JSON.Boolean(active)),
    ("cwd", JSON.String(dir)),
  ])
  agent->Option.forEach(id => fields->Dict.set("agent_id", JSON.String(id)))
  fields
}

let reset = input => Node.rmSync(Stale_jobs.ledger(input), {recursive: true, force: true})

let ids = input =>
  Stale_jobs.find(input, ~at)
  ->Result.getOr([])
  ->Array.map((found: Stale_jobs.stale) => found.job.id)

describe("a background job gone silent", () => {
  test("is said with its id, description and seconds, and is held once at a stop", () => {
    let out = output("a.out", ~silent=90)
    let transcript = write(
      "a.jsonl",
      [
        started(
          ~session="s1",
          ~call="t1",
          ~id="bhang1",
          ~output=out,
          ~description="Build the site",
        ),
      ],
    )
    let input = payload(transcript, "s1")
    reset(input)
    switch Stale_jobs.find(input, ~at) {
    | Ok([found]) =>
      expect(found.job.id)->toBe("bhang1")
      expect(found.job.description)->toBe("Build the site")
      expect(found.silent)->toBe(90)
      expect(Stale_jobs.describe(found))->toContain("bhang1 (Build the site)")
      expect(Stale_jobs.describe(found))->toContain("silent for 90 seconds")
      expect(Stale_jobs.describe(found))->toContain("Look at it now")
    | _ => expect("one job")->toBe("not found")
    }
    let held = Stale_jobs.response(input, ~at)
    expect(JSON.stringify(held->Option.getOr(JSON.Null)))->toContain("\"decision\":\"block\"")
    // The same job and silence is not held a second time, so no loop forms.
    expect(Stale_jobs.response(input, ~at))->toEqual(None)
    reset(input)
  })

  test("is held again when it spoke and fell silent anew", () => {
    let out = output("b.out", ~silent=60)
    let transcript = write(
      "b.jsonl",
      [started(~session="s2", ~call="t1", ~id="bagain", ~output=out, ~description="Wait")],
    )
    let input = payload(transcript, "s2")
    reset(input)
    expect(Stale_jobs.response(input, ~at)->Option.isSome)->toBe(true)
    expect(Stale_jobs.response(input, ~at))->toEqual(None)
    output("b.out", ~silent=45)->ignore
    expect(Stale_jobs.response(input, ~at)->Option.isSome)->toBe(true)
    reset(input)
  })

  test("is not said while within the stall, finished, quiet or another session's", () => {
    let fresh = output("c1.out", ~silent=5)
    let finished = output("c2.out", ~silent=500)
    let quiet = output("c3.out", ~silent=500)
    let foreign = output("c4.out", ~silent=500)
    let transcript = write(
      "c.jsonl",
      [
        started(~session="s3", ~call="a", ~id="bfresh", ~output=fresh, ~description="Fresh"),
        started(~session="s3", ~call="b", ~id="bdone", ~output=finished, ~description="Done"),
        notice(~session="s3", ~id="bdone"),
        started(
          ~session="s3",
          ~call="c",
          ~id="bquiet",
          ~output=quiet,
          ~description="Soak, quiet by design",
        ),
        started(~session="other", ~call="d", ~id="bother", ~output=foreign, ~description="Theirs"),
      ],
    )
    let input = payload(transcript, "s3")
    reset(input)
    expect(ids(input))->toEqual([])
    expect(Stale_jobs.context(input, ~at))->toEqual(None)
    expect(Stale_jobs.response(input, ~at))->toEqual(None)
    reset(input)
  })

  test(
    "is said for each silent job in the post-tool context, and a second stop is let through",
    () => {
      let one = output("d1.out", ~silent=100)
      let two = output("d2.out", ~silent=200)
      let transcript = write(
        "d.jsonl",
        [
          started(~session="s4", ~call="a", ~id="bone", ~output=one, ~description="One"),
          started(~session="s4", ~call="b", ~id="btwo", ~output=two, ~description="Two"),
        ],
      )
      let input = payload(transcript, "s4")
      reset(input)
      expect(ids(input))->toEqual(["bone", "btwo"])
      let said = Stale_jobs.context(input, ~at)->Option.getOr("")
      expect(said)->toContain("bone (One) has been silent for 100 seconds")
      expect(said)->toContain("btwo (Two) has been silent for 200 seconds")
      expect(Stale_jobs.response(payload(~active=true, transcript, "s4"), ~at))->toEqual(None)
      reset(input)
    },
  )

  test("fails open at a stop and names an unreadable transcript", () => {
    let input = payload(Node.join([dir, "missing.jsonl"]), "s5")
    let text = JSON.stringify(Stale_jobs.response(input, ~at)->Option.getOr(JSON.Null))
    expect(text)->toContain("were not checked")
    expect(text)->toContain("missing.jsonl")
    expect(text->String.includes("block"))->toBe(false)
    expect(Stale_jobs.context(input, ~at))->toEqual(None)
  })

  test("is ended by a TaskStop that succeeded and not by one that failed", () => {
    let out = output("e.out", ~silent=500)
    let transcript = write(
      "e.jsonl",
      [
        started(~session="s6", ~call="a", ~id="bstopped", ~output=out, ~description="Stopped"),
        taskStop(~session="s6", ~call="z", ~id="bstopped", ~result=true),
        started(~session="s6", ~call="b", ~id="bkept", ~output=out, ~description="Kept"),
        taskStop(~session="s6", ~call="y", ~id="bkept", ~result=false),
      ],
    )
    let input = payload(transcript, "s6")
    reset(input)
    expect(ids(input))->toEqual(["bkept"])
    reset(input)
  })

  test("is said by a post-tool call at most every five minutes, and a last time at an hour", () => {
    let out = output("f.out", ~silent=100)
    let transcript = write(
      "f.jsonl",
      [started(~session="s7", ~call="a", ~id="bslow", ~output=out, ~description="Slow")],
    )
    let input = payload(transcript, "s7")
    reset(input)
    let say = (~at) => Stale_jobs.context(input, ~at, ~mtime=_ => Some(at -. 100_000.))
    expect(say(~at)->Option.isSome)->toBe(true)
    expect(say(~at=at +. 60_000.))->toEqual(None)
    expect(say(~at=at +. 299_000.))->toEqual(None)
    expect(say(~at=at +. 301_000.)->Option.isSome)->toBe(true)
    let silentFor = (~at, seconds) =>
      Stale_jobs.context(input, ~at, ~mtime=_ => Some(at -. seconds *. 1000.))
    let last = silentFor(~at=at +. 4_000_000., 3700.)
    expect(last->Option.getOr(""))->toContain("the last time it is said")
    expect(silentFor(~at=at +. 4_400_000., 4100.))->toEqual(None)
    reset(input)
  })
})

describe("a subagent's call", () => {
  test("says nothing of the parent's jobs and leaves the parent's ledger alone", () => {
    let out = output("g.out", ~silent=500)
    let transcript = write(
      "g.jsonl",
      [started(~session="s8", ~call="a", ~id="bparent", ~output=out, ~description="Parent's")],
    )
    let parent = payload(transcript, "s8")
    let child = payload(~agent="agent1", transcript, "s8")
    reset(parent)
    reset(child)
    expect(Stale_jobs.context(child, ~at))->toEqual(None)
    expect(Stale_jobs.response(child, ~at))->toEqual(None)
    expect(Stale_jobs.find(child, ~at))->toEqual(Ok([]))
    expect(Node.existsSync(Stale_jobs.ledger(parent)))->toBe(false)
    // The same transcript read as the parent names the job.
    expect(ids(parent))->toEqual(["bparent"])
    reset(parent)
  })

  test("names its own jobs when its own transcript is found", () => {
    let mine = output("h1.out", ~silent=500)
    let theirs = output("h2.out", ~silent=500)
    let transcript = write(
      "h.jsonl",
      [started(~session="s9", ~call="a", ~id="bparent", ~output=theirs, ~description="Parent's")],
    )
    Node.mkdirAll(Node.join([dir, "h", "subagents"]))
    Node.writeFileSync(
      Node.join([dir, "h", "subagents", "agent-agent2.jsonl"]),
      started(~session="s9", ~call="b", ~id="bchild", ~output=mine, ~description="Child's") ++ "\n",
    )
    let child = payload(~agent="agent2", transcript, "s9")
    reset(child)
    expect(ids(child))->toEqual(["bchild"])
    reset(child)
    reset(payload(transcript, "s9"))
  })
})

describe("a transcript read in pieces", () => {
  test("is read once and then only what was appended", () => {
    let out = output("i.out", ~silent=500)
    let first = started(~session="s10", ~call="a", ~id="bpiece", ~output=out, ~description="Piece")
    let transcript = write("i.jsonl", [first])
    let input = payload(transcript, "s10")
    reset(input)
    expect(ids(input))->toEqual(["bpiece"])
    // The old bytes are blanked, so only the kept state can still know the job.
    Node.writeFileSync(transcript, " "->String.repeat(first->String.length + 1))
    expect(ids(input))->toEqual(["bpiece"])
    appendFileSync(transcript, notice(~session="s10", ~id="bpiece") ++ "\n")
    expect(ids(input))->toEqual([])
    reset(input)
    expect(ids(input))->toEqual([])
    reset(input)
  })

  test("is read from the start again when the file shrinks, and a half line waits", () => {
    let out = output("j.out", ~silent=500)
    let first = started(~session="s11", ~call="a", ~id="bhalf", ~output=out, ~description="Half")
    let transcript = Node.join([dir, "j.jsonl"])
    Node.writeFileSync(transcript, first)
    let input = payload(transcript, "s11")
    reset(input)
    // The last line has no newline yet, so the job is not seen.
    expect(ids(input))->toEqual([])
    appendFileSync(transcript, "\n")
    expect(ids(input))->toEqual(["bhalf"])
    Node.writeFileSync(transcript, "\n")
    expect(ids(input))->toEqual([])
    reset(input)
  })
})

describe("nothing in the gate", () => {
  test("throws out of it, whatever the ledger or the transcript is", () => {
    let out = output("k.out", ~silent=500)
    let transcript = write(
      "k.jsonl",
      [started(~session="s12", ~call="a", ~id="bthrow", ~output=out, ~description="Throw")],
    )
    let input = payload(transcript, "s12")
    reset(input)
    // A directory where the ledger should be, then a ledger that is not JSON.
    Node.mkdirAll(Stale_jobs.ledger(input))
    expect(Stale_jobs.context(input, ~at)->Option.isSome)->toBe(true)
    reset(input)
    Node.writeFileSync(Stale_jobs.ledger(input), "{not json")
    expect(Stale_jobs.response(input, ~at)->Option.isSome)->toBe(true)
    reset(input)
    Node.writeFileSync(Stale_jobs.ledger(input), "{\"v\":1}")
    expect(Stale_jobs.context(input, ~at))->toEqual(None)
    reset(input)
    // A directory as the transcript is unreadable and named, not thrown.
    let broken = payload(dir, "s12")
    expect(JSON.stringify(Stale_jobs.response(broken, ~at)->Option.getOr(JSON.Null)))->toContain(
      "were not checked",
    )
    expect(Stale_jobs.context(broken, ~at))->toEqual(None)
  })
})

describe("a start, a stop and a notice", () => {
  test("are taken from their structured place, and a quotation of them counts for nothing", () => {
    let real = output("l1.out", ~silent=500)
    let fake = output("l2.out", ~silent=500)
    let start = `Command running in background with ID: bfake. Output is being written to: ${fake}. You will be notified`
    let transcript = write(
      "l.jsonl",
      [
        started(~session="s13", ~call="a", ~id="breal", ~output=real, ~description="Real"),
        quoting(~session="s13", ~call="q1", start),
        quoting(~session="s13", ~call="q2", "Successfully stopped task: breal (sleep)"),
        quoting(
          ~session="s13",
          ~call="q3",
          "<task-notification>\n<task-id>breal</task-id>\n</task-notification>",
        ),
        userSays(
          ~session="s13",
          "look at this <task-notification><task-id>breal</task-id></task-notification>",
        ),
      ],
    )
    let input = payload(transcript, "s13")
    reset(input)
    expect(ids(input))->toEqual(["breal"])
    // The same notice at the start of a user message does end it.
    appendFileSync(
      transcript,
      userSays(
        ~session="s13",
        "<task-notification>\n<task-id>breal</task-id>\n</task-notification>",
      ) ++ "\n",
    )
    expect(ids(input))->toEqual([])
    reset(input)
  })
})

describe("a job that redirects its output", () => {
  test("is alive while its target grows, and said when the target is silent too", () => {
    let out = output("m.out", ~silent=500)
    let log = output("m.log", ~silent=3)
    let transcript = write(
      "m.jsonl",
      [
        started(
          ~session="s14",
          ~call="a",
          ~id="bredir",
          ~output=out,
          ~description="Redirected",
          ~command="make all > m.log 2>&1",
          ~cwd=dir,
        ),
      ],
    )
    let input = payload(transcript, "s14")
    reset(input)
    expect(ids(input))->toEqual([])
    output("m.log", ~silent=400)->ignore
    expect(ids(input))->toEqual(["bredir"])
    reset(input)
    ignore(log)
  })

  test("is found by its targets, past a stream, a device, a variable and a here-document", () => {
    let targets = command => Stale_jobs.targetsOf(command, ~cwd="/w")
    expect(targets("make > out.log 2>&1"))->toEqual(["/w/out.log"])
    expect(targets("make >> /var/log/x.log"))->toEqual(["/var/log/x.log"])
    expect(targets("make &> all.log"))->toEqual(["/w/all.log"])
    expect(targets("make 2>err.log >out.log"))->toEqual(["/w/err.log", "/w/out.log"])
    expect(targets("make 2>&1"))->toEqual([])
    expect(targets("make > /dev/null"))->toEqual([])
    expect(targets("make > $LOG"))->toEqual([])
    expect(targets("make"))->toEqual([])
    expect(targets("cat <<EOF\nx > y.log\nEOF\nmake"))->toEqual([])
  })
})
