open Testing

let known = ["lane-task", "single-writer"]

describe("a record of friction", () => {
  test("is named for its date and its rule's id, a counter allowed after the id", () => {
    expect(Friction.parse("2026-11-01-lane-task.md", ~known))->toEqual(
      Ok({Friction.date: "2026-11-01", rule: "lane-task"}),
    )
    expect(Friction.parse("2026-11-01-lane-task-2.md", ~known))->toEqual(
      Ok({Friction.date: "2026-11-01", rule: "lane-task"}),
    )
  })

  test("is refused when the name has no date, no known rule or another suffix", () => {
    [
      "lane-task.md",
      "2026-13-45-lane-task.md",
      "2026-11-01-nothing.md",
      "2026-11-01-lane-task.txt",
    ]->Array.forEach(file => expect(Friction.parse(file, ~known)->Result.isError)->toBe(true))
  })
})

describe("the sum of friction", () => {
  test("counts and dates each rule, the most frictional first", () => {
    let one = (date, rule): Friction.record => {date, rule}
    expect(
      Friction.sum([
        one("2026-11-01", "single-writer"),
        one("2026-10-30", "lane-task"),
        one("2026-11-01", "lane-task"),
      ])->Array.map(Friction.shown),
    )->toEqual([
      "lane-task: 2 records, 2026-10-30 to 2026-11-01",
      "single-writer: 1 record, 2026-11-01",
    ])
  })

  let base = Testing.temporaryRoot("friction-")
  test("reads a directory of files, and none where there is none", () => {
    Testing.tree(base.contents, [("2026-11-01-lane-task.md", "x"), ("notes.txt", "y")])
    expect(Friction.problems(~directory=base.contents)->Array.length)->toBe(1)
    expect(Friction.problems(~directory=Node.join([base.contents, "absent"])))->toEqual([])
  })
})
