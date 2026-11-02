open Testing

describe("a lane's take", () => {
  test("reads both sides of a rename, a copy's new one, and a plain path", () => {
    expect(
      Lane_take.summaryPaths("M a/b\nD c\nR d/{e => f}/g\nR {h => i/j}\nC {k => l}\n"),
    )->toEqual(["a/b", "c", "d/e/g", "d/f/g", "h", "i/j", "l"])
  })

  test("refuses a path main moved or the checkout edited, and nothing else", () => {
    expect(Lane_take.blocked(~touched=["a", "b", "c"], ~moved=["b"], ~edited=["c", "z"]))->toEqual([
      "b: main moved it since the lane forked",
      "c: the main checkout holds an edit to it",
    ])
    expect(Lane_take.blocked(~touched=["a"], ~moved=[], ~edited=[]))->toEqual([])
  })
})

describe("a seat's check", () => {
  let plan = (parts, ~tasks=[]) => Lane_check.plan(parts, ~tasks, ~hasRescript=true, ~hasCargo=true)

  test("names what each part runs, by what the repository declares", () => {
    expect(plan(["format"], ~tasks=["formatted"]))->toEqual(Ok([Mise(["run", "formatted"])]))
    expect(plan(["format"], ~tasks=["verify:format"]))->toEqual(
      Ok([Mise(["run", "verify:format"])]),
    )
    expect(plan(["wire"], ~tasks=["check"]))->toEqual(Ok([Mise(["run", "check"])]))
    expect(plan(["names"]))->toEqual(Ok([Names]))
    expect(plan(["tests", "gateway"]))->toEqual(Ok([Mise(["run", "built", "gateway"])]))
    expect(plan(["tests", "names"], ~tasks=["test"]))->toEqual(Ok([Mise(["run", "test"]), Names]))
  })

  test("compiles both languages where both are, and refuses a word that is no part", () => {
    expect(plan(["compile"]))->toEqual(
      Ok([
        Mise(["x", "--", "rescript", "build"]),
        Mise(["x", "--", "cargo", "check", "--workspace", "--all-targets"]),
      ]),
    )
    expect(plan(["verify"]))->toEqual(Error("verify"))
  })

  test("runs the model's check for wire only where check is the model's", () => {
    expect(
      Lane_check.plan(
        ["wire"],
        ~tasks=["check"],
        ~hasRescript=true,
        ~hasCargo=false,
        ~hasModel=false,
      ),
    )->toEqual(Ok([Say("wire: this repository has no model to check")]))
  })

  test("tells a stale working copy from what jj said", () => {
    expect(
      Lane_check.staleSaid("Error: The working copy is stale (not updated since op x)"),
    )->toEqual(true)
    expect(Lane_check.staleSaid("Working copy changes:"))->toEqual(false)
  })
})
