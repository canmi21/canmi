open Testing

let built = String.repeat("1", 40)
let before = String.repeat("2", 40)
let head = String.repeat("3", 40)
let zero = String.repeat("0", 40)

let answering = commit => () => commit
let unanswered = () => throw(Base.Unanswered("HTTP 403"))
let always = _ => true

describe("the base a push plans against", () => {
  test("is the last commit built, not its before", () => {
    // The cancelled pending run's commit is `before`; the last run that succeeded built `built`.
    let (chosen, why) = Base.base(answering(Some(built)), before, head, always)
    expect(chosen)->toBe(built)
    expect(why)->toContain(built)
  })

  test("is everything with no run built", () => {
    let (chosen, _) = Base.base(answering(None), before, head, always)
    expect(chosen)->toBe("")
  })

  test("is everything for a commit HEAD does not descend from", () => {
    let (chosen, why) = Base.base(answering(Some(built)), before, head, _ => false)
    expect(chosen)->toBe("")
    expect(why)->toContain("does not descend")
  })

  test("falls back to before when the API does not answer, and says so", () => {
    let (chosen, why) = Base.base(unanswered, before, head, always)
    expect(chosen)->toBe(before)
    expect(why)->toContain("HTTP 403")
    expect(why)->toContain("github.event.before")
    expect(Base.base(unanswered, zero, head, always)->Pair.first)->toBe("")
    expect(Base.base(unanswered, "", head, always)->Pair.first)->toBe("")
  })

  test("is its before for a re-run of the commit built", () =>
    expect(Base.base(answering(Some(head)), before, head, always)->Pair.first)->toBe(before)
  )
})

type outcome = Built(option<string>) | Refused(string)

/** What `lastBuilt` makes of one answer from `gh`, and the arguments it asked with. */
let asked = (~status=Nullable.make(0), ~stdout="", ~stderr="", ~error=?) => {
  let given = ref([])
  let ask: Base.run = (_, args) => {
    given := args
    {status, stdout, stderr, error}
  }
  let outcome = switch Base.lastBuilt("monoflake/platform", ~ask) {
  | found => Built(found)
  | exception Base.Unanswered(why) => Refused(why)
  }
  (outcome, given.contents)
}

describe("the last commit built", () => {
  test("is the newest push run on main that succeeded", () => {
    let (answer, args) = asked(
      ~stdout=`{"workflow_runs": [{"head_sha": "${built}", "event": "push"}]}`,
    )
    expect(answer)->toEqual(Built(Some(built)))
    let path = args[1]->Option.getOr("")
    expect(
      path->String.startsWith("repos/monoflake/platform/actions/workflows/deploy.yml/runs?"),
    )->toBe(true)
    ["branch=main", "event=push", "status=success", "per_page=1"]->Array.forEach(
      one => expect(path)->toContain(one),
    )
  })

  test("is none when none succeeded", () =>
    expect(asked(~stdout=`{"total_count": 0, "workflow_runs": []}`)->Pair.first)->toEqual(
      Built(None),
    )
  )

  test("is unanswered for every answer it cannot read", () => {
    let refused = outcome =>
      switch outcome {
      | Refused(_) => true
      | Built(_) => false
      }
    [
      asked(~status=Nullable.make(1), ~stderr="HTTP 403: Resource not accessible by integration\n"),
      asked(~stdout="not json"),
      asked(~stdout=`{"message": "Not Found"}`),
      asked(~stdout=`{"workflow_runs": [{}]}`),
      asked(~status=Nullable.null, ~error=Net.error("spawnSync gh ENOENT")),
      asked(~status=Nullable.null, ~error=Net.error("spawnSync gh ETIMEDOUT")),
    ]->Array.forEach(((outcome, _)) => expect(refused(outcome))->toBe(true))
  })

  test("is unanswered with no repository named", () => {
    let refused = switch Base.lastBuilt("") {
    | _ => false
    | exception Base.Unanswered(_) => true
    }
    expect(refused)->toBe(true)
  })
})

describe("a commit held", () => {
  // Against a real repository: two commits on one line, and one on a line of its own.
  let checkout = temporaryRoot("base-")
  let git = args =>
    Node.execFileSync(
      "git",
      Array.concat(["-c", "user.name=t", "-c", "user.email=t@t.invalid"], args),
      {cwd: checkout.contents, encoding: "utf8"},
    )->String.trim
  let first = ref("")
  let aside = ref("")
  beforeEach(() => {
    git(["init", "-q", "-b", "main"])->ignore
    git(["commit", "-q", "--allow-empty", "-m", "first"])->ignore
    first := git(["rev-parse", "HEAD"])
    git(["checkout", "-q", "--orphan", "aside"])->ignore
    git(["commit", "-q", "--allow-empty", "-m", "aside"])->ignore
    aside := git(["rev-parse", "HEAD"])
    git(["checkout", "-q", "main"])->ignore
    git(["commit", "-q", "--allow-empty", "-m", "second"])->ignore
  })

  test("is one HEAD descends from, its own among them", () => {
    expect(Base.holds(first.contents, ~checkout=checkout.contents))->toBe(true)
    expect(Base.holds(git(["rev-parse", "HEAD"]), ~checkout=checkout.contents))->toBe(true)
  })

  test("is not one off its line, or one unknown", () => {
    expect(Base.holds(aside.contents, ~checkout=checkout.contents))->toBe(false)
    expect(Base.holds(String.repeat("4", 40), ~checkout=checkout.contents))->toBe(false)
  })
})
