open Testing

let start = (id, ~at=0., ~command="c") =>
  `{"kind":"start","id":"${id}","by":"b","command":"${command}","cwd":"/","pid":1,"at":${Float.toString(
      at,
    )},"output":"/o","quiet":false}`
let end_ = (id, ~at, ~status=0) =>
  `{"kind":"end","id":"${id}","status":${Int.toString(status)},"at":${Float.toString(at)}}`

@val external processPid: int = "process.pid"

describe("an integrator's own task", () => {
  test("is a job of its session, quiet, ended and read by its end, and classed apart", () => {
    let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "task-"]))
    let saved = ["RUNS_HOME", "CLAUDE_PID"]->Array.map(key => (key, Node.env->Dict.get(key)))
    Node.env->Dict.set("RUNS_HOME", root)
    Node.env->Dict.set("CLAUDE_PID", Int.toString(processPid))
    expect(Job.main(["task", "start", "write", "the", "doc"]))->toBe(0)
    let job = Ledger.jobs()->Array.getUnsafe(0)
    expect((job.command, job.quiet, job.pid, job.ended))->toEqual((
      "task: write the doc",
      true,
      processPid,
      None,
    ))
    expect(Classes.classOf(job.command))->toBe("integrator task")
    expect(Job.main(["stop", job.id]))->toBe(1)
    expect(Ledger.find(job.id)->Option.flatMap(one => one.ended))->toEqual(None)
    let savedSession = Node.env->Dict.get("CLAUDE_CODE_SESSION_ID")
    Node.env->Dict.set("CLAUDE_CODE_SESSION_ID", "another")
    expect(Job.main(["task", "end", job.id]))->toBe(1)
    switch savedSession {
    | Some(value) => Node.env->Dict.set("CLAUDE_CODE_SESSION_ID", value)
    | None => Node.env->Dict.delete("CLAUDE_CODE_SESSION_ID")
    }
    expect(Ledger.limitOf(job, ~all=[]))->toEqual(Some(Delegation.pieceMinutes->Int.toFloat *. 60.))
    let bound = Delegation.seatOpenSeconds->Int.toFloat *. 1000.
    expect(Ledger.runsUntil(job, ~now=job.started +. 2. *. bound))->toEqual(job.started +. bound)
    expect(Job.main(["task", "end", job.id]))->toBe(0)
    let closed = Ledger.find(job.id)->Option.getOrThrow
    expect((closed.status, Ledger.wasRead(closed)))->toEqual((Some(0), true))
    expect(Job.main(["task", "end", job.id]))->toBe(1)
    Node.env->Dict.delete("CLAUDE_PID")
    expect(Job.main(["task", "start", "x"]))->toBe(2)
    saved->Array.forEach(
      ((key, value)) =>
        switch value {
        | Some(value) => Node.env->Dict.set(key, value)
        | None => Node.env->Dict.delete(key)
        },
    )
    Node.rmSync(root, {recursive: true, force: true})
  })
})

describe("a session's registrations", () => {
  test("are kept per thread once written, its transcript filling in", () => {
    let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "registrations-"]))
    let saved = Node.env->Dict.get("RUNS_HOME")
    Node.env->Dict.set("RUNS_HOME", root)
    Ledger.registerSession(
      ~role="integrator",
      ~name="i",
      ~transcript=None,
      ~thread=Some("a"),
      ~at=1.,
    )
    Ledger.registerSession(
      ~role="integrator",
      ~name="i",
      ~transcript=Some("/t.jsonl"),
      ~thread=Some("a"),
      ~at=2.,
    )
    Ledger.registerSession(
      ~role="integrator",
      ~name="i",
      ~transcript=Some("/t.jsonl"),
      ~thread=Some("b"),
      ~at=3.,
    )
    Ledger.registerSession(
      ~role="integrator",
      ~name="i",
      ~transcript=Some("/u.jsonl"),
      ~thread=Some("a"),
      ~at=4.,
    )
    let found = Ledger.registrationsOf("a")
    expect(found->Array.map(one => (one.transcript, one.at)))->toEqual([
      (Some("/t.jsonl"), 1.),
      (Some("/u.jsonl"), 4.),
    ])
    expect(Ledger.registrationsOf("b")->Array.length)->toEqual(1)
    expect(Ledger.registrationsOf("none"))->toEqual([])
    switch saved {
    | Some(value) => Node.env->Dict.set("RUNS_HOME", value)
    | None => Node.env->Dict.delete("RUNS_HOME")
    }
    Node.rmSync(root, {recursive: true, force: true})
  })
})

describe("the ledger", () => {
  test("folds a start, an end and a read, passing over an unreadable line", () => {
    let jobs = Ledger.fold(
      [
        start("a"),
        "not json",
        end_("a", ~at=5000.),
        `{"kind":"read","id":"a","at":6000}`,
      ]->Array.join("\n"),
    )
    expect(jobs->Array.length)->toEqual(1)
    let job = jobs->Array.getUnsafe(0)
    expect(job.status)->toEqual(Some(0))
    expect(Ledger.seconds(job))->toEqual(Some(5.))
    expect(Ledger.wasRead(job))->toEqual(true)
  })

  test("a read before the end is not a read of the result", () => {
    let job =
      Ledger.fold(
        [start("a"), `{"kind":"read","id":"a","at":1}`, end_("a", ~at=5.)]->Array.join("\n"),
      )->Array.getUnsafe(0)
    expect(Ledger.wasRead(job))->toEqual(false)
  })

  test("takes the limit from the job, else twice the p95 once there is history", () => {
    let runs = n =>
      Array.fromInitializer(
        ~length=n,
        at => [start(`r${Int.toString(at)}`), end_(`r${Int.toString(at)}`, ~at=10000.)],
      )
      ->Array.flat
      ->Array.join("\n")
    let live = Ledger.fold(start("live"))->Array.getUnsafe(0)
    expect(Ledger.limitOf(live, ~all=Ledger.fold(runs(4))))->toEqual(None)
    expect(Ledger.limitOf(live, ~all=Ledger.fold(runs(5))))->toEqual(Some(20.))
    expect(Ledger.limitOf({...live, limit: Some(3.)}, ~all=[]))->toEqual(Some(3.))
  })

  test("sums the table by command, the bottleneck first", () => {
    let rows = Ledger.table(
      Ledger.fold(
        [
          start("a", ~command="x"),
          end_("a", ~at=1000.),
          start("b", ~command="y"),
          end_("b", ~at=9000.),
          start("c", ~command="x"),
          end_("c", ~at=1000.),
        ]->Array.join("\n"),
      ),
    )
    expect(rows->Array.map(row => (row.command, row.count, row.total)))->toEqual([
      ("y", 1, 9.),
      ("x", 2, 2.),
    ])
  })
})

describe("the job's command", () => {
  test("is one word as written and several quoted", () => {
    expect(Job.lineOf(["a && b"]))->toEqual("a && b")
    expect(Job.lineOf(["mise", "run", "x y"]))->toEqual("mise run 'x y'")
  })

  test("takes the flags before it, with or without the dashes", () => {
    let given = Job.parseGiven(
      ["--by", "me", "--limit", "9", "--quiet", "--", "ls", "--by"],
      ~defaultBy="d",
    )
    expect((given.by, given.limit, given.quiet, given.command))->toEqual((
      "me",
      Some(9.),
      true,
      ["ls", "--by"],
    ))
    expect(Job.parseGiven(["ls", "-a"], ~defaultBy="d").command)->toEqual(["ls", "-a"])
  })

  test("reads its id from the output path alone", () => {
    expect(Ledger.idOfOutput(Ledger.outputOf("20261102-000000-abcd")))->toEqual(
      Some("20261102-000000-abcd"),
    )
    expect(Ledger.idOfOutput("/elsewhere/a.log"))->toEqual(None)
  })
})

describe("stopping a job", () => {
  let job: Ledger.job = {
    id: "a",
    by: "seat-a",
    session: "one",
    command: "c",
    cwd: "/",
    pid: 1,
    started: 0.,
    output: "/o",
    limit: None,
    quiet: false,
    ended: None,
    status: None,
    read: None,
  }

  test("is its starter's alone, and the refusal says whose it is", () => {
    expect(Job.notOwn(job, ~session="one", ~by="seat-a"))->toEqual(None)
    expect(Job.notOwn(job, ~session="one", ~by="seat-b"))->toEqual(Some("seat-a in session one"))
    expect(Job.notOwn(job, ~session="two", ~by="seat-a"))->toEqual(Some("seat-a in session one"))
    expect(Job.notOwn({...job, session: ""}, ~session="", ~by="other"))->toEqual(Some("seat-a"))
  })
})

describe("a job whose process is gone", () => {
  let job = Ledger.fold(start("gone"))->Array.getUnsafe(0)

  test("is died in the list and in the read result", () => {
    expect(Job.listState(job, ~alive=_ => false))->toEqual("died")
    expect(Job.unfinished(job, ~alive=_ => false))->toEqual("job gone: died, output /o")
    expect(Job.died(job, ~alive=_ => false))->toEqual(true)
  })

  test("keeps live jobs and pid zero running", () => {
    expect(Job.listState(job, ~alive=_ => true))->toEqual("running")
    expect(Job.unfinished(job, ~alive=_ => true))->toEqual("job gone: still running, output /o")
    expect(Job.listState({...job, pid: 0}, ~alive=_ => false))->toEqual("running")
    expect(Job.unfinished({...job, pid: 0}, ~alive=_ => false))->toEqual(
      "job gone: still running, output /o",
    )
  })

  test("keeps a recorded end even after the process disappears", () => {
    let done = {...job, ended: Some(1000.), status: Some(2)}
    expect(Job.died(done, ~alive=_ => false))->toEqual(false)
    expect(Job.listState(done, ~alive=_ => false))->toEqual("2 unread")
    expect(Job.listState({...done, read: Some(1000.)}, ~alive=_ => false))->toEqual("2")
  })
})
