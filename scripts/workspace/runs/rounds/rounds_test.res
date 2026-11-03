open Testing

type invocation = {env: Dict.t<string>, encoding: string, timeout: int}
@module("node:child_process")
external invoke: (string, array<string>, invocation) => Node.spawned = "spawnSync"

let slice = Delegation.roundSliceSeconds->Int.toFloat *. 1000.
let minute = slice /. 60000.
let span = (from, to): Rounds.span => {from: from *. slice, to: to *. slice}
let session = (~role="integrator", name): Watchdog.session => {
  name,
  role,
  transcript: Some(`/transcripts/${name}.jsonl`),
  thread: Some("trial"),
}
let idle = (~role="integrator", name): Rounds.activity => {
  session: session(~role, name),
  jobs: [],
  seats: [],
  reviews: [],
  turns: [],
  missing: [],
}
let first = Figures.Seat({name: "start", tooling: false, at: 0.})
let green = (step, at) => Figures.Green({step, at: at *. slice})
let steps: array<Charter.step> = [{id: "1", after: []}, {id: "2", after: []}]
let pending: array<Rounds.decision> = [{asked: 0., answered: None}]
let rounds = (~records=[first], ~steps=[], ~decisions=[], ~count=1., sessions) =>
  Rounds.roundsOf(~records, ~sessions, ~steps, ~decisions, ~now=count *. slice)
let total = (rounds: array<Rounds.round>) => {
  let round = rounds->Array.getUnsafe(0)
  let row = round.rows->Array.getUnsafe(0)
  row.minutes
}

describe("round slice precedence", () => {
  let own = {...idle("own"), turns: [span(0., 1.)]}
  test("a job beats review, turn, decision and ready", () => {
    let activity = {...own, jobs: [span(0., 1.)], reviews: [span(0., 1.)]}
    expect(rounds(~steps, ~decisions=pending, [activity])->total)->toEqual({
      ...Rounds.zero,
      job: minute,
    })
  })
  test("a seat beats a review and a turn", () => {
    let activity = {...own, seats: [span(0., 1.)], reviews: [span(0., 1.)]}
    expect(rounds([activity])->total)->toEqual({...Rounds.zero, job: minute})
  })
  test("a review beats a turn and a decision", () => {
    expect(rounds(~decisions=pending, [{...own, reviews: [span(0., 1.)]}])->total)->toEqual({
      ...Rounds.zero,
      review: minute,
    })
  })
  test("a turn beats a decision and ready", () => {
    expect(rounds(~steps, ~decisions=pending, [own])->total)->toEqual({
      ...Rounds.zero,
      turn: minute,
    })
  })
  test("a decision beats ready until its answer", () => {
    let decisions: array<Rounds.decision> = [{asked: slice, answered: Some(2. *. slice)}]
    expect(rounds(~steps, ~decisions, ~count=3., [idle("own")])->total)->toEqual({
      ...Rounds.zero,
      decision: minute,
      ready: 2. *. minute,
    })
  })
  test("nothing covers a slice without work", () => {
    expect(rounds([idle("own")])->total)->toEqual({...Rounds.zero, nothing: minute})
  })
  test("ready requires more steps than integrators running jobs or taking turns", () => {
    let busy = {...idle("busy"), jobs: [span(0., 1.)], turns: [span(1., 2.)]}
    let found = rounds(~steps=[{id: "1", after: []}], ~count=3., [idle("own"), busy])
    expect(found->total)->toEqual({...Rounds.zero, nothing: 2. *. minute, ready: minute})
    expect((rounds(~steps, [idle("own"), busy])->total).ready)->toEqual(minute)
  })
  test("reviewers and busy sessions of other roles do not consume integrator capacity", () => {
    let busy = {...idle(~role="supervisor", "busy"), jobs: [span(0., 1.)]}
    let review = {...idle("review"), reviews: [span(0., 1.)]}
    expect(
      (rounds(~steps=[{id: "1", after: []}], [idle("own"), busy, review])->total).ready,
    )->toEqual(minute)
  })
  test("ready follows charter dependencies and greens at each slice", () => {
    let steps: array<Charter.step> = [{id: "1", after: ["0"]}]
    let records = [first, green("0", 1.), green("1", 2.)]
    let found = rounds(~steps, ~records, ~count=3., [idle("own")])
    expect(found->Array.map(round => total([round]).ready))->toEqual([0., minute, 0.])
  })
})

describe("round boundaries", () => {
  test("repeated greens cut in record order and a job crosses each boundary", () => {
    let records = [first, green("1", 1.), green("1", 2.)]
    let found = rounds(~records, ~count=3., [{...idle("own"), jobs: [span(0., 3.)]}])
    expect(found->Array.map(round => (round.heading, round.span)))->toEqual([
      ("1", span(0., 1.)),
      ("1", span(1., 2.)),
      ("running", span(2., 3.)),
    ])
    expect(found->Array.map(round => total([round]).job))->toEqual([minute, minute, minute])
  })
  test("an integrator's buckets sum to the span including partial slices", () => {
    let activity = {
      ...idle("own"),
      jobs: [span(0., 1.)],
      reviews: [span(1., 2.)],
      turns: [span(2., 3.)],
    }
    let decisions: array<Rounds.decision> = [{asked: 3. *. slice, answered: Some(4. *. slice)}]
    let records = [first, green("1", 5.)]
    let found = rounds(~records, ~steps=[{id: "1", after: []}], ~decisions, ~count=6.5, [activity])
    found->Array.forEach(
      round => {
        let total = total([round])
        let sum =
          total.job +. total.review +. total.turn +. total.decision +. total.ready +. total.nothing
        expect(Math.abs(sum -. (round.span.to -. round.span.from) /. 60000.) < 0.000001)->toEqual(
          true,
        )
      },
    )
    expect(found->total)->toEqual({
      job: minute,
      review: minute,
      turn: minute,
      decision: minute,
      ready: minute,
      nothing: 0.,
    })
    expect(total(found->Array.slice(~start=1)).nothing)->toEqual(1.5 *. minute)
  })
  test("empty records and a first green keep zero length rounds", () => {
    expect(Rounds.spansOf([], ~now=slice))->toEqual([("running", span(1., 1.))])
    expect(Rounds.spansOf([green("1", 1.)], ~now=2. *. slice))->toEqual([
      ("1", span(1., 1.)),
      ("running", span(1., 2.)),
    ])
  })
})

let job = (~session="own", ~ended=None, ~started=0., id): Ledger.job => {
  id,
  session,
  by: "lane",
  command: "compile",
  cwd: "/",
  pid: 1,
  started,
  output: "",
  limit: None,
  quiet: false,
  ended,
  status: None,
  read: None,
}

describe("transcript and decision inputs", () => {
  let root = temporaryRoot("rounds-")
  let iso = time => Date.fromTime(time)->Date.toISOString
  let line = time => `not JSON "timestamp":"${iso(time)}" trailing data\n`
  test("reads timestamps with a regex and joins only gaps within the turn limit", () => {
    let gap = Delegation.turnGapSeconds->Int.toFloat *. 1000.
    let text =
      line(0.) ++
      "invalid\n" ++
      line(gap) ++
      line(2. *. gap +. 1.) ++ "{\"timestamp\":\"invalid\"}\n"
    expect(text->Rounds.timestamps->Rounds.stretches)->toEqual([
      {from: 0., to: gap},
      {from: 2. *. gap +. 1., to: 2. *. gap +. 1.},
    ])
    expect(Rounds.holds([{from: 1., to: 1.}], {from: 0., to: 10.}))->toEqual(true)
    expect(Rounds.holds([{from: 0., to: 10.}], {from: 10., to: 20.}))->toEqual(false)
  })
  test("reads subagent metadata and matches ledger sessions by transcript basename", () => {
    let transcript = Node.join([root.contents, "own.jsonl"])
    tree(
      root.contents,
      [
        ("own.jsonl", line(0.) ++ line(slice)),
        ("own/subagents/seat.jsonl", line(0.) ++ line(slice)),
        ("own/subagents/seat.meta.json", "{\"agentType\":\"implementer\"}"),
        ("own/subagents/review.jsonl", line(slice) ++ line(2. *. slice)),
        ("own/subagents/review.meta.json", "{\"agentType\":\"reviewer\"}"),
        ("own/subagents/other.jsonl", line(2. *. slice) ++ line(3. *. slice)),
      ],
    )
    let session = {...session("registered-name"), transcript: Some(transcript)}
    let jobs = [job("live"), job(~ended=Some(slice), "done"), job(~session="other", "other")]
    let found = Rounds.activityOf(session, ~jobs, ~now=3. *. slice, ~alive=_ => true)
    expect(found.turns)->toEqual([span(0., 1.)])
    expect(found.seats)->toEqual([span(2., 3.), span(0., 1.)])
    expect(found.reviews)->toEqual([span(1., 2.)])
    expect(found.jobs)->toEqual([span(0., 3.), span(0., 1.)])
    expect(Rounds.activityOf(session, ~jobs, ~now=3. *. slice, ~alive=_ => false).jobs)->toEqual([
      span(0., 1.),
    ])
  })
  test("missing and unreadable transcripts produce no activity and one warning each", () => {
    let file = Node.join([root.contents, "missing.jsonl"])
    let session = {...session("missing"), transcript: Some(file)}
    let missing = Rounds.activityOf(session, ~jobs=[], ~now=slice, ~alive=_ => false)
    let unreadable = Rounds.activityOf(
      {...session, transcript: Some(root.contents)},
      ~jobs=[],
      ~now=slice,
      ~alive=_ => false,
    )
    expect(missing.turns)->toEqual([])
    expect(unreadable.turns)->toEqual([])
    let text = Rounds.shown(
      ~name="trial",
      ~rounds=rounds(~records=[first, green("1", 0.5)], [missing]),
      ~untimed=2,
      ~missing=[file, file],
    )
    expect(
      text->String.split("no activity from missing or unreadable transcript:")->Array.length,
    )->toEqual(2)
    expect(text->String.split("untimed decision blocks:")->Array.length)->toEqual(2)
  })
  test("only decisions with an Asked time are timed and Answered closes them", () => {
    let found = Rounds.decisionsOf(
      `# Decisions\n\n## Open\nAsked: ${iso(slice)}\n\n## Done\nAsked: ${iso(0.)}\nAnswered: ${iso(
          slice,
        )}\n\n## Old\nAnswer: open\n\n## Template\nAsked: time in UTC.\n`,
    )
    expect(found)->toEqual({
      timed: [{asked: slice, answered: None}, {asked: 0., answered: Some(slice)}],
      untimed: 2,
    })
  })
  test("the command filters registered threads and writes exactly what it prints", () => {
    let started = Date.now() -. 2. *. slice
    tree(
      root.contents,
      [
        (
          "threads/trial/figures.jsonl",
          Ledger.line([
            ("kind", JSON.String("seat")),
            ("name", JSON.String("own")),
            ("at", JSON.Number(started)),
          ]),
        ),
        ("threads/trial/charter.md", "1. Ready.\n   after: none\n"),
        ("threads/trial/decisions.md", "## Legacy\nAnswer: open\n"),
        (
          "runs/sessions/own.json",
          "{\"name\":\"own\",\"role\":\"integrator\",\"thread\":\"trial\"}",
        ),
        (
          "runs/sessions/other.json",
          "{\"name\":\"other\",\"role\":\"advisor\",\"thread\":\"elsewhere\"}",
        ),
      ],
    )
    let env = Node.envCopy(Node.env)
    env->Dict.set("THREADS_HOME", Node.join([root.contents, "threads"]))
    env->Dict.set("RUNS_HOME", Node.join([root.contents, "runs"]))
    let script = Node.join([Registry.root, "scripts/workspace/runs/thread.res.mjs"])
    let result = invoke("node", [script, "rounds", "trial"], {env, encoding: "utf8", timeout: 5000})
    expect(result.status->Nullable.toOption)->toEqual(Some(0))
    let text = Node.readFileSync(Node.join([root.contents, "threads/trial/rounds.txt"]))
    expect(result.stdout->Nullable.getOr(""))->toEqual(text)
    expect(text->String.includes("integrator own:"))->toEqual(true)
    expect(text->String.includes("advisor other:"))->toEqual(false)
    expect(text->String.includes("thread trial: ready"))->toEqual(true)
    expect(text->String.includes("untimed decision blocks: 1\n"))->toEqual(true)
  })
})
