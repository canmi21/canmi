open Testing

let job = (
  ~by="alpha",
  ~session="parent",
  ~command="mise run build",
  ~started=0.,
  ~seconds=10.,
  ~ended=true,
  (),
): Ledger.job => {
  id: "trial",
  by,
  session,
  command,
  cwd: "/trial",
  pid: 0,
  started,
  output: "",
  limit: None,
  quiet: false,
  ended: ended ? Some(started +. seconds *. 1000.) : None,
  status: Some(0),
  read: None,
}
let timed = (~since=0., ~activity=[], ~records=[], jobs) =>
  Classes.timings(~jobs, ~activity, ~records, ~since)
let shown = timings => Classes.shown(~timings, ~landings=[])

describe("class table", () => {
  test("conform's class tells real runs from dry runs, one kind and its build", () => {
    [
      ("mise run conform root@okra --app a", "conform"),
      ("mise run conform root@okra --kind databases", "conform one kind"),
      ("mise run conform root@okra --dry-run", "conform dry run"),
      ("mise run built conform", "built"),
      ("mise run accept conform --from a", "other"),
      ("sh -c 'cd lane && mise run conform x'", "conform"),
    ]->Array.forEach(
      ((command, class_)) =>
        expect((command, Classes.classOf(command)))->toEqual((command, class_)),
    )
  })

  let root = temporaryRoot("classes-")
  test("classes follow model order and the first match wins", () => {
    expect(Classes.names())->toEqual(
      Array.concat(
        Delegation.jobClasses->Array.map(((name, _)) => name),
        ["other", "Claude seat", "review", "landing"],
      ),
    )
    Delegation.jobClasses->Array.forEach(
      ((name, _)) => expect(Classes.rows([], [])->Array.some(row => row.kind == name))->toBe(true),
    )
    expect(Classes.classOf("codex exec mise run check"))->toBe("Codex seat")
    expect(Classes.classOf("unknown"))->toBe("other")
    expect(Classes.rows([], [])->Array.map(row => row.kind))->toEqual(Classes.names())
  })
  test("empty classes show dashes and timing sorts the bottleneck first", () => {
    let values = timed([job(), job(~command="mise run conform root@okra", ~seconds=30., ())])
    expect((Classes.rows(values, [])->Array.getUnsafe(0)).kind)->toBe("conform")
    expect(shown(values))->toContain("review | - | - | - | - | - | -")
    expect(shown(values))->toContain("build | 1 | 10.0 | 10.0 | 10.0 | 0 | 1")
  })
  test("median covers odd and even populations", () => {
    expect(Classes.median([8., 2., 4.]))->toEqual(Some(4.))
    expect(Classes.median([8., 2., 4., 6.]))->toEqual(Some(5.))
    expect(Classes.median([]))->toEqual(None)
  })
  test("since excludes earlier and unfinished jobs and clips transcript stretches", () => {
    let activity: array<Classes.activity> = [
      {kind: "review", who: "reader", description: "review", spans: [{from: 0., to: 20000.}]},
    ]
    let values = timed(
      ~since=10000.,
      ~activity,
      [job(), job(~started=10000., ()), job(~started=20000., ~ended=false, ())],
    )
    expect(values->Array.map(one => one.seconds))->toEqual([10., 10.])
    expect(timed(~since=30000., ~activity, [job()]))->toEqual([])
  })
  test("two seats normalize paths hashes ids lane names and numbers to one command", () => {
    let first = "codex exec --cd /lanes/alpha --resume 0xabcdef a1b2c3d4 --lane alpha 17"
    let second = "codex exec --cd /lanes/beta --resume 0x123456 deadbeef --lane beta 42"
    expect(Classes.normalized(~lanes=["alpha", "beta"], first))->toBe(
      Classes.normalized(~lanes=["alpha", "beta"], second),
    )
    expect(Classes.normalized("mise run //:built"))->toBe("mise run //:built")
    expect(Classes.normalized("mise run //:check"))
    ->negated
    ->toBe(Classes.normalized("mise run //:built"))
  })
  test("repeated commands across days recur and a same day retry is one off", () => {
    expect(timed([job(), job(~started=86400000., ())])->Array.map(one => one.recurring))->toEqual([
      Some(true),
      Some(true),
    ])
    expect(timed([job(), job(~started=20000., ())])->Array.map(one => one.recurring))->toEqual([
      Some(false),
      Some(false),
    ])
  })
  test("a green between runs recurs only inside a common thread", () => {
    let records: array<Classes.thread> = [
      {sessions: ["parent", "second"], records: [Figures.Green({step: "1", at: 15000.})]},
    ]
    let jobs = [job(), job(~session="second", ~started=20000., ())]
    expect(timed(~records, jobs)->Array.map(one => one.recurring))->toEqual([
      Some(true),
      Some(true),
    ])
  })
  test("a green during a run does not split it into recurring work", () => {
    let records: array<Classes.thread> = [
      {sessions: ["parent"], records: [Figures.Green({step: "1", at: 5000.})]},
    ]
    expect(
      timed(~records, [job(), job(~started=20000., ())])->Array.map(one => one.recurring),
    )->toEqual([Some(false), Some(false)])
  })
  test("greens in unrelated threads do not make a command recurring", () => {
    let records: array<Classes.thread> = [
      {sessions: ["parent"], records: [Figures.Green({step: "1", at: 15000.})]},
      {sessions: ["second"], records: []},
    ]
    expect(
      timed(~records, [job(), job(~session="second", ~started=20000., ())])->Array.map(
        one => one.recurring,
      ),
    )->toEqual([Some(false), Some(false)])
  })
  test("the normalized command classifies every run of the same work", () => {
    let records: array<Classes.thread> = [
      {sessions: ["parent"], records: [Figures.Green({step: "1", at: 15000.})]},
    ]
    expect(
      timed(
        ~records,
        [job(), job(~started=20000., ()), job(~session="unregistered", ~started=40000., ())],
      )->Array.map(one => one.recurring),
    )->toEqual([Some(true), Some(true), Some(true)])
    expect(Classes.normalized("probe 12.5"))->toBe(Classes.normalized("probe 42"))
  })
  test("agentType separates reviewer and probe seats and duplicate transcripts count once", () => {
    let transcript = Node.join([root.contents, "parent.jsonl"])
    let stamps = "{\"timestamp\":\"2026-11-01T00:00:00Z\"}\n{\"timestamp\":\"2026-11-01T00:00:10Z\"}\n"
    tree(
      root.contents,
      [
        ("parent/subagents/reader.jsonl", stamps),
        ("parent/subagents/reader.meta.json", "{\"agentType\":\"reviewer\"}"),
        ("parent/subagents/probe.jsonl", stamps),
        ("parent/subagents/probe.meta.json", "{\"agentType\":\"probe\"}"),
      ],
    )
    let session: Watchdog.session = {
      name: "parent",
      role: "integrator",
      thread: Some("trial"),
      transcript: Some(transcript),
    }
    let activity = Classes.activityOf([session, session])
    expect(activity->Array.length)->toBe(2)
    let values = timed(~activity, [])
    expect(values->Array.map(one => one.kind)->Array.toSorted(String.compare))->toEqual([
      "Claude seat",
      "review",
    ])
    expect(values->Array.map(one => one.seconds))->toEqual([10., 10.])
    expect(shown(values))->toContain("review | 1 | 10.0 | 10.0 | 10.0 | - | -")
  })
  test("failed jj is reported rather than counted as zero", () => {
    let result: Node.spawned = {
      status: Nullable.make(1),
      error: Nullable.null,
      stdout: Nullable.make(""),
      stderr: Nullable.make("broken history"),
    }
    let landing = Classes.landingOf(~repository="trial", result)
    expect(Classes.shown(~timings=[], ~landings=[landing]))->toContain(
      "  trial: jj failed: broken history",
    )
    expect(Classes.shown(~timings=[], ~landings=[landing]))->negated->toContain("  trial: 0")
    let success = Classes.landingOf(
      ~repository="passed",
      {
        ...result,
        status: Nullable.make(0),
        stdout: Nullable.make("first\nsecond\n"),
        stderr: Nullable.make(""),
      },
    )
    expect(Classes.shown(~timings=[], ~landings=[success]))->toContain(
      "landing | 2 | - | - | - | - | -",
    )
  })
  test("every class can exceed the piece limit and commands are cut to 72 columns", () => {
    let command = "x"->String.repeat(90)
    let values = timed([
      job(~command, ~seconds=Delegation.pieceMinutes->Int.toFloat *. 60. +. 1., ()),
    ])
    expect((values->Array.getUnsafe(0)).description->String.length)->toBe(72)
    expect(shown(values))->toContain("other | alpha |")
    expect(shown(values))->toContain("warning and never blocking")
  })
  describe("green to push", () => {
    let green = (step, at): Figures.record => Green({step, at})
    let landed = (at): Figures.record => Landed({repository: "r", commit: "c", subject: "s", at})
    test(
      "a green reads the first landing at or after it",
      () => {
        expect(Figures.greenToPush([green("1", 1000.), landed(61000.)]))->toEqual([
          ("1", 1000., Some(60.)),
        ])
        expect(Figures.greenToPush([landed(500.), green("1", 1000.), landed(1000.)]))->toEqual([
          ("1", 1000., Some(0.)),
        ])
      },
    )
    test(
      "a green with no landing after it is not pushed yet",
      () => {
        expect(Figures.greenToPush([green("1", 1000.), landed(999.)]))->toEqual([
          ("1", 1000., None),
        ])
      },
    )
    test(
      "two greens before one landing both read it",
      () => {
        expect(
          Figures.greenToPush([green("1", 1000.), green("2", 31000.), landed(61000.)]),
        )->toEqual([("1", 1000., Some(60.)), ("2", 31000., Some(30.))])
      },
    )
    test(
      "since filters greens and a thread without one says nothing",
      () => {
        let named = [
          ("a", [green("1", 1000.), green("2", 5000.), landed(65000.)]),
          ("b", [landed(1000.)]),
          ("c", [green("3", 100.), landed(200.)]),
        ]
        let lines = Classes.pushesOf(named, ~since=2000.)
        expect(lines)->toEqual([{thread: "a", step: "2", seconds: Some(60.)}])
        let text = Classes.shown(~timings=[], ~landings=[], ~pushes=lines)
        expect(text)->toContain(Classes.greenToPushUnmeasured)
        expect(text)->negated->toContain("a step 2:")
        expect(text)->negated->toContain("minutes\na step")
        expect(Classes.shown(~timings=[], ~landings=[], ~pushes=[]))
        ->negated
        ->toContain("green to push")
      },
    )
  })
})
